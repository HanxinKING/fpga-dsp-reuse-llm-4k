"""FPGAUI1: bounded ASCII framing, little-endian CRC32 request payload."""
import struct
import zlib
from dataclasses import dataclass
from models import MODELS

class ProtocolError(ValueError):
    pass

@dataclass(frozen=True)
class ParsedLine:
    kind: str
    text: str = ''
    index: int | None = None
    token_id: int | None = None
    core_cycles: int | None = None
    data: dict | None = None

class ChatAdapter:
    def __init__(self, model=None):
        self.model = model or MODELS['q7']
        self.reset()

    def reset(self):
        self.capable = False
        self.active_rid = None

    @staticmethod
    def crc32_request(rid, max_new, ids):
        return zlib.crc32(struct.pack('<III', rid, max_new, len(ids)) +
                          struct.pack('<' + str(len(ids)) + 'I', *ids)) & 0xffffffff

    def ping_bytes(self, rid, newline=b'\n'):
        if type(rid) is not int or not 0 < rid <= 0xffffffff:
            raise ProtocolError('请求编号无效')
        return f'FPGAUI1 PING {rid}'.encode('ascii') + newline

    def run_bytes(self, rid, max_new, ids, newline=b'\n'):
        m = self.model
        if not self.capable:
            raise ProtocolError('串口协议尚未验证')
        if not 0 < rid <= 0xffffffff or not 1 <= max_new <= m.max_new or not ids or len(ids)+max_new-1 > m.context:
            raise ProtocolError('输入及输出超出当前硬件上下文')
        if any(type(x) is not int or not 0 <= x < m.vocab for x in ids):
            raise ProtocolError('输入 token 超出词表')
        crc = self.crc32_request(rid, max_new, ids)
        payload = f"FPGAUI1 RUN {rid} {max_new} {len(ids)} {crc:08x} " + ' '.join(map(str, ids))
        self.active_rid = rid
        return payload.encode('ascii') + newline

    def parse_line(self, line):
        parts = line.strip().split()
        if not parts or parts[0] != 'FPGAUI1':
            return ParsedLine('raw', text=line)
        rid = None
        try:
            if len(parts) < 3:
                raise ValueError('字段缺失')
            rid = int(parts[2])
            if not 0 <= rid <= 0xffffffff:
                raise ValueError('请求编号越界')
            tag = parts[1]
            if tag == 'READY' and len(parts) == 10:
                model = parts[3]
                context, vocab, clock, abi, availability, boot = map(int, parts[4:])
                if min(context,vocab,clock,abi,availability,boot) < 0 or availability not in (0,1,2):
                    raise ValueError('READY 范围错误')
                return ParsedLine('capability', data=dict(rid=rid,model=model,context=context,vocab=vocab,
                    clock=clock,abi=abi,availability=availability,boot=boot))
            if tag == 'BEGIN' and len(parts) == 5:
                n, maximum = map(int,parts[3:])
                if not rid or not 1 <= n <= self.model.context or not 1 <= maximum <= self.model.max_new:
                    raise ValueError('BEGIN 范围错误')
                return ParsedLine('begin',data=dict(rid=rid,n=n,max_new=maximum))
            if tag == 'TOKEN' and len(parts) == 7:
                index, token, cycles, position = map(int,parts[3:])
                if not rid or not 0 <= index < self.model.max_new or not 0 <= token < self.model.vocab or not 0 <= cycles < 2**64 or not 0 <= position < self.model.context:
                    raise ValueError('TOKEN 范围错误')
                return ParsedLine('token',index=index,token_id=token,core_cycles=cycles,data=dict(rid=rid,position=position))
            if tag == 'DONE' and len(parts) == 10:
                names = ('generated','failures','consumed','core_cycles','quant_warning_flags','quant_warning_events','reset_required')
                values = list(map(int,parts[3:]))
                if not rid or any(x < 0 for x in values) or values[0] > self.model.max_new or values[3] >= 2**64 or values[-1] not in (0,1):
                    raise ValueError('DONE 范围错误')
                return ParsedLine('done',data=dict(rid=rid,**dict(zip(names,values))))
            if tag == 'PROGRESS' and len(parts) == 5:
                position,layer = map(int,parts[3:])
                if not rid or not 0 <= position < self.model.context or not 0 <= layer < 32:
                    raise ValueError('PROGRESS 范围错误')
                return ParsedLine('progress',data=dict(rid=rid,position=position,layer=layer))
            if tag == 'ERROR' and len(parts) == 4:
                return ParsedLine('error',text='板端错误：'+parts[3],data=dict(rid=rid,code=parts[3]))
            raise ValueError('未知帧或字段数错误')
        except (ValueError,OverflowError) as exc:
            return ParsedLine('error',text='协议错误：'+str(exc),data={'rid':rid})
