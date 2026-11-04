"""Native Qwen tool schemas and parsing; tool output remains data."""
import json,re

SCHEMA_VERSION=1

def _tool(name,description,properties=None,required=()):
 return dict(type='function',function=dict(name=name,description=description,
  parameters=dict(type='object',properties=properties or {},required=list(required),additionalProperties=False)))

TOOLS=[
 _tool('camera_capture','查看当前真实画面时获取摄像头当前帧；已有用户上传图片可直接分析。'),
 _tool('linux_query','查询板端Linux的实际状态。',{'query':dict(type='string',enum=['system','memory','disk','network','usb','temperature','cpu','services'])},['query']),
 _tool('git_clone','把用户指定的HTTPS Git仓库克隆到工作目录。',{'url':dict(type='string'),'directory':dict(type='string')},['url']),
 _tool('git_status','读取工作目录内仓库状态。',{'path':dict(type='string')},['path']),
 _tool('read_file','读取工作目录内文件，如仓库README。',{'path':dict(type='string'),'max_chars':dict(type='integer',minimum=1,maximum=8192)},['path']),
 _tool('list_directory','列出工作目录中的文件。',{'path':dict(type='string')})
]
_SCHEMAS={tool['function']['name']:tool['function']['parameters'] for tool in TOOLS}
MODES=('chat','agent','camera')

def normalize_mode(value):
 if value not in MODES:raise ValueError('请选择对话、Agent 或摄像模式')
 return value

def mode_for_record(record):
 if record and record.get('interaction_mode') in MODES:return record['interaction_mode']
 # Keep existing exact-token history usable; new conversations default to chat.
 return 'agent' if record and record.get('agent_schema_version') else 'chat'

def tools_for_mode(mode):
 mode=normalize_mode(mode)
 return [] if mode=='chat' else [t for t in TOOLS if (t['function']['name']=='camera_capture')==(mode=='camera')]

def registration_tools(record,mode):
 tools=tools_for_mode(mode)
 if not tools:return None
 if record and record.get('agent_schema_version')==SCHEMA_VERSION and record.get('agent_tool_mode')==mode:return None
 return tools
_EOS=re.compile(r'<\|(?:im_end|endoftext)\|>')
_CALL=re.compile(r'<tool_call>\s*<function=([A-Za-z_][A-Za-z0-9_]*)>\s*(.*?)\s*</function>\s*</tool_call>',re.S)
_PARAM=re.compile(r'<parameter=([A-Za-z_][A-Za-z0-9_]*)>\s*(.*?)\s*</parameter>',re.S)

def _outside_fences(text,index):
 return len(re.findall(r'(?m)^\s*```',text[:index]))%2==0

def parse_tool_call(text):
 """Return one complete native XML call, None for an ordinary answer.

 Truncated or malformed calls never execute. Thinking and EOS are accepted;
 quoted examples inside Markdown fences remain ordinary response text.
 """
 if not isinstance(text,str):raise ValueError('模型工具输出必须为文本')
 text=_EOS.sub('',text)
 text=re.sub(r'<think>.*?</think>','',text,flags=re.S)
 matches=[match for match in _CALL.finditer(text) if _outside_fences(text,match.start())]
 if not matches:
  markers=[m for m in re.finditer(r'<tool_call(?:>|\s|$)',text) if _outside_fences(text,m.start())]
  if markers:raise ValueError('工具调用未完整结束')
  return None
 if len(matches)!=1:raise ValueError('每次只调用一个工具')
 match=matches[0];name,body=match.groups()
 if text[match.end():].strip():raise ValueError('工具调用结束后包含额外输出')
 if name not in _SCHEMAS:raise ValueError('未知模型工具：'+name)
 schema=_SCHEMAS[name];arguments={};cursor=0
 for item in _PARAM.finditer(body):
  if body[cursor:item.start()].strip():raise ValueError('工具参数格式无效')
  key,value=item.groups();cursor=item.end()
  if key in arguments or key not in schema['properties']:raise ValueError('工具参数重复或未知：'+key)
  definition=schema['properties'][key]
  if definition['type']=='integer':
   if not re.fullmatch(r'[0-9]{1,8}',value):raise ValueError('工具参数须为整数：'+key)
   value=int(value)
   if not definition.get('minimum',value)<=value<=definition.get('maximum',value):raise ValueError('工具参数超出范围：'+key)
  elif definition['type']=='string':
   if value.startswith('"') and value.endswith('"'):
    try:decoded=json.loads(value)
    except ValueError:decoded=value
    if isinstance(decoded,str):value=decoded
   if len(value)>4096:raise ValueError('工具参数过长：'+key)
   if 'enum' in definition and value not in definition['enum']:raise ValueError('工具参数不受支持：'+key)
  arguments[key]=value
 if body[cursor:].strip():raise ValueError('工具参数格式无效')
 if any(key not in arguments for key in schema['required']):raise ValueError('工具调用缺少必需参数')
 return dict(name=name,arguments=arguments)

def format_tool_response(result):
 """Compact observation text; image pixels are passed separately to vision."""
 def clean(value):
  if isinstance(value,dict):
   return {str(key):clean(item) for key,item in value.items()
           if key not in ('image_base64','image_url','private_image_url','rgb','image_bytes',
                          'terminal','argv','cwd','launch_argv','started_at','finished_at',
                          'executed','stdout_truncated','stderr_truncated','kind','operation','paths')}
  if isinstance(value,(list,tuple)):return [clean(item) for item in value[:64]]
  if isinstance(value,str):return value[:6000]+('…[截断]' if len(value)>6000 else '')
  if value is None or isinstance(value,(int,float,bool)):return value
  return str(value)[:1000]
 value=clean(result)
 text=json.dumps(value,ensure_ascii=False,separators=(',',':'))
 if len(text)>18000:
  text=json.dumps(dict(name=result.get('name'),ok=result.get('ok'),source=result.get('source'),
   truncated=True,summary=text[:16000]),ensure_ascii=False,separators=(',',':'))
 return text
