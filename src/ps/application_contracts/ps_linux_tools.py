"""Small read-only Linux query catalog, executed as fixed argv without a shell."""
from pathlib import Path
import datetime,os,socket,subprocess,time
from linux_tool_contract import CATALOG
def execute(query):
 if query not in CATALOG:raise ValueError('未知的 Linux 查询')
 item=CATALOG[query];rows=[];start=time.monotonic()
 for argv in item['commands']:
  try:
   p=subprocess.run(argv,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,errors='replace',timeout=4)
   rows.append(dict(argv=argv,exit_code=p.returncode,stdout=p.stdout[:2400],stderr=p.stderr[:600],truncated=len(p.stdout)>2400 or len(p.stderr)>600))
  except subprocess.TimeoutExpired:rows.append(dict(argv=argv,exit_code=None,stdout='',stderr='查询超时',timed_out=True))
  except FileNotFoundError:rows.append(dict(argv=argv,exit_code=None,stdout='',stderr='该命令未安装'))
 if query=='temperature':
  lines=[]
  for zone in sorted(Path('/sys/class/thermal').glob('thermal_zone*')):
   try:lines.append((zone/'type').read_text().strip()+': '+str(int((zone/'temp').read_text().strip())/1000)+' °C')
   except (OSError,ValueError):continue
  rows.append(dict(argv=['read','/sys/class/thermal/thermal_zone*/temp'],exit_code=0,stdout='\n'.join(lines) or '未发现内核导出的温度传感器',stderr=''))
 if query=='cpu':
  lines=['在线 CPU: '+str(os.cpu_count()),'loadavg: '+Path('/proc/loadavg').read_text().strip()]
  freq=Path('/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq')
  if freq.exists():lines.append('PS CPU0 当前频率: '+str(int(freq.read_text().strip())/1000)+' MHz')
  rows.append(dict(argv=['read','/proc/loadavg','/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq'],exit_code=0,stdout='\n'.join(lines),stderr=''))
 return dict(source='ps-linux',query=query,title=item['title'],hostname=socket.gethostname(),
  executed_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),elapsed_seconds=round(time.monotonic()-start,3),commands=rows)
