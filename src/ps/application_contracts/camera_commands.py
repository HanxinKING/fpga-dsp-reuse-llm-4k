"""Explicit chat camera requests: fresh PS snapshot -> existing image inference."""
import base64,re,time

def wants_camera(text):
    if not isinstance(text,str):return False
    value=re.sub(r'\s+','',text).lower()
    if re.search(r'(?:不要|不用|别|停止|关闭|取消).{0,8}(?:摄像头|camera|webcam|拍照|拍摄|抓帧|读取|获取|查看)',value):return False
    if re.match(r'^/camera(?:$|\s|[：:，,、])',text.strip().lower()):return True
    # Configuration/definition questions must remain ordinary text requests.
    explicit=re.search(r'(?:读取|获取|抓取).{0,8}(?:当前帧|摄像头.{0,6}(?:画面|图像|数据))|(?:摄像头|camera|webcam).{0,6}(?:当前|现在).{0,6}(?:画面|图像)|看看.{0,6}摄像头',value)
    if not explicit and re.search(r'驱动|原理|代码|接口|协议|安装|配置|分辨率|帧率|型号|参数|权限|报错|故障|如何|怎么|能不能|是否',value):return False
    camera=re.search(r'摄像头|摄像机|camera|webcam',value)
    action=re.search(r'看看|看一下|查看|获取|读取|拍照|拍摄|抓帧|抓取|识别|分析|描述|告诉我|拍到了什么|里面?有什么',value)
    if camera and action:return True
    return bool(re.match(r'^(?:(?:请|帮我|给我|麻烦|现在|你|先|再|立即|马上)){0,6}(?:拍(?:张|一张|一下|照)|抓取(?:当前|一)?帧|获取当前帧|看看(?:当前|现在)的?画面)',value))

def submit_camera(session,text,maximum,capture,thinking=False):
    if not isinstance(text,str) or not text.strip() or len(text)>131072 or not 1<=maximum<=2048:raise ValueError('输入或输出范围无效')
    if not session.operation_lock.acquire(False):raise RuntimeError('会话操作正在进行')
    started=time.monotonic()
    try:
        with session.lock:
            if session.model.key!='q9':raise ValueError('摄像头分析需要 9B PS＋PL 配置')
            if not session.adapter.capable or session.resident_encoder()!='bf16' or session.busy or session.request or session.preparing:
                raise RuntimeError('请先连接并验证板卡，等待当前任务完成')
            session.phase='camera';session.emit('state',session.state())
        frame=capture()  # Always capture now; never substitute the last saved preview.
        image=base64.b64decode(frame['image_base64'],validate=True)
        if not image or len(image)>10*1024*1024:raise ValueError('摄像头图像大小无效')
        metadata={k:v for k,v in frame.items() if k!='image_base64'}
        result=session.submit(text,maximum,image,'bf16',operation_reserved=True,submitted_at=started,image_origin='camera-tool',**(dict(thinking=True) if thinking else {}))
        with session.lock:
            turn=next(t for t in session.turns if t['rid']==result['rid'])
            turn['camera']=metadata;session.emit('turn',turn)
        return dict(result,input_source='ps-camera',camera=metadata,max_new=maximum)
    finally:
        with session.lock:
            if not session.busy and not session.request:session.phase='ready'
        session.operation_lock.release();session.emit('state',session.state())
