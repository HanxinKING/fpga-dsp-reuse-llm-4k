"""Bounded snapshot capture from the PS USB UVC camera; no browser camera."""
from pathlib import Path
import base64,datetime,fcntl,hashlib,io,json,os,shutil,subprocess,tempfile,time,uuid
from PIL import Image

ROOT=Path('/run/q9-camera-preview')
class CameraError(RuntimeError):
 def __init__(self,message,status=503):super().__init__(message);self.status=status

def status():
 devices=[]
 for node in sorted(Path('/sys/class/video4linux').glob('video*')):
  try:
   # V4L2_CAP_DEVICE_CAPS resolves metadata-only nodes correctly.
   with open('/dev/'+node.name,'rb',buffering=0) as fd:
    cap=bytearray(104);fcntl.ioctl(fd,0x80685600,cap)
   caps=int.from_bytes(cap[84:88],'little');device_caps=int.from_bytes(cap[88:92],'little')
   effective=device_caps if caps&0x80000000 else caps
   if not effective&1 or 'usb' not in str(node.resolve()):continue
   devices.append(dict(device='/dev/'+node.name,name=(node/'name').read_text().strip()))
  except OSError:continue
 return dict(available=bool(devices) and bool(shutil.which('v4l2-ctl')),source='ps-usb',devices=devices,mode='snapshot',message='拍照后输入问题并发送' if devices else 'PS 未发现 USB 图像摄像头')

def capture():
 ROOT.mkdir(parents=True,exist_ok=True)
 with (ROOT/'capture.lock').open('a') as lock:
  try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
  except BlockingIOError:raise CameraError('摄像头正在拍照，请稍后重试',409)
  info=status()
  if not info['available']:raise CameraError(info['message'])
  device=info['devices'][0];started=time.monotonic()
  with tempfile.TemporaryDirectory(prefix='capture-',dir=ROOT) as tmp:
   output=Path(tmp)/'frames.mjpg'
   try:
    p=subprocess.run(['v4l2-ctl','--device',device['device'],'--set-fmt-video=width=1280,height=720,pixelformat=MJPG','--set-parm=30','--stream-mmap=4','--stream-count=8','--stream-to='+str(output)],capture_output=True,timeout=12)
   except subprocess.TimeoutExpired:raise CameraError('摄像头取帧超时，请检查连接')
   if p.returncode:
    message=p.stderr.decode(errors='replace')
    raise CameraError('摄像头被其他程序占用' if 'busy' in message.lower() else '摄像头取帧失败，请检查 USB 连接',409 if 'busy' in message.lower() else 503)
   raw=output.read_bytes();starts=[];offset=0
   while True:
    offset=raw.find(bytes([255,216]),offset)
    if offset<0:break
    starts.append(offset);offset+=2
   jpeg=None
   for start in reversed(starts):
    end=raw.find(bytes([255,217]),start)
    if end<0:continue
    candidate=raw[start:end+2]
    try:
     image=Image.open(io.BytesIO(candidate));image.load()
     if image.format!='JPEG' or image.size!=(1280,720):continue
     jpeg=candidate;break
    except (OSError,ValueError):continue
   if jpeg is None:raise CameraError('摄像头未返回完整 JPEG 图像')
   identifier=uuid.uuid4().hex
   metadata=dict(source='ps-usb',camera_name=device['name'],device=device['device'],capture_id=identifier,
    filename='ps-usb-camera-'+identifier[:12]+'.jpg',mime='image/jpeg',width=image.width,height=image.height,
    captured_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),capture_seconds=round(time.monotonic()-started,3),
    bytes=len(jpeg),sha256=hashlib.sha256(jpeg).hexdigest())
   # Retain one latest preview only. Model/session storage remains the normal image path.
   temp=ROOT/'latest.next.jpg';temp.write_bytes(jpeg);os.replace(temp,ROOT/'latest.jpg')
   temp=ROOT/'latest.next.json';temp.write_text(json.dumps(metadata));os.replace(temp,ROOT/'latest.json')
   return dict(metadata,image_base64=base64.b64encode(jpeg).decode())
