# 开发用 Mock 服务器：同时模拟 LLM(OpenAI兼容) 与 ComfyUI。
# 用途：模拟器/真机端到端联调，不需要真实 LLM key 与 ComfyUI。
# 启动：python tool/mock_server.py [port]   （默认 8188）
# 模拟器访问地址：http://10.0.2.2:8188
import base64
import json
import os
import struct
import sys
import threading
import time
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8188
SUBMIT_DIR = os.path.join(os.path.dirname(__file__), '..', 'build', 'mock')
os.makedirs(SUBMIT_DIR, exist_ok=True)

# 1x1 红色 PNG
PNG_1PX = base64.b64decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')


def make_png(rgb, size=16):
    """纯 Python 生成 size x size 纯色 PNG（无第三方依赖），供不同任务返回不同颜色。"""
    r, g, b = rgb
    row = b'\x00' + bytes([r, g, b] * size)
    raw = row * size

    def chunk(typ, data):
        return (struct.pack('>I', len(data)) + typ + data
                + struct.pack('>I', zlib.crc32(typ + data) & 0xffffffff))

    ihdr = struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def color_for_pid(n):
    """由任务编号推导稳定且互不相同的颜色。"""
    return ((n * 61 + 40) % 256, (n * 97 + 80) % 256, (n * 157 + 120) % 256)

STATE = {'prompt_id': 0, 'done_at': {}}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print('[mock] %s' % (fmt % args))

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split('?')[0]
        if path == '/system_stats':
            self._json({'system': {'comfyui_version': 'mock-0.3'}, 'devices': []})
        elif path.startswith('/history/'):
            pid = path.rsplit('/', 1)[-1]
            done = STATE['done_at'].get(pid)
            if done and time.time() - done > 2:
                self._json({pid: {
                    'status': {'status_str': 'success', 'completed': True},
                    'outputs': {'18': {'images': [
                        {'filename': 'mock_%s_.png' % pid[-6:], 'subfolder': '', 'type': 'output'}]}},
                }})
            else:
                self._json({})
        elif path.startswith('/view'):
            # 按文件名里的任务编号返回不同颜色的图：不同任务颜色不同，便于实测区分历史版本
            fname = ''
            if 'filename=' in self.path:
                fname = self.path.split('filename=', 1)[1].split('&', 1)[0]
            digits = ''.join(ch for ch in fname if ch.isdigit())
            if digits:
                body = make_png(color_for_pid(int(digits)))
            else:
                body = PNG_1PX
            self.send_response(200)
            self.send_header('Content-Type', 'image/png')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif path == '/ws':
            # 故意不支持 WS → 客户端自动降级轮询
            self.close_connection = True
            self.send_response(400)
            self.end_headers()
        else:
            self._json({'error': 'not found'}, 404)

    def do_POST(self):
        path = self.path.split('?')[0]
        length = int(self.headers.get('Content-Length', 0))
        raw = self.rfile.read(length) if length else b'{}'
        if path == '/prompt':
            try:
                wf = json.loads(raw.decode('utf-8'))
                # 保存提交的工作流供断言（%变量% 是否被替换等）
                STATE['prompt_id'] += 1
                pid = 'mock-%06d' % STATE['prompt_id']
                out = os.path.join(SUBMIT_DIR, 'submitted_%s.json' % pid)
                with open(out, 'w', encoding='utf-8') as f:
                    json.dump(wf.get('prompt', wf), f, ensure_ascii=False, indent=1)
                threading.Timer(1.0, lambda: STATE.__setitem__('done_at', {
                    **STATE['done_at'], pid: time.time()})).start()
                self._json({'prompt_id': pid, 'number': 1, 'node_errors': None})
            except Exception as e:
                self._json({'error': str(e)}, 500)
        elif path == '/v1/chat/completions':
            content = ('分析：测试\n```json\n{"insertions": [{"after_paragraph": 1, "prompt": "masterpiece, best quality, 1girl, long hair, standing, outdoor"}]}\n```')
            self._json({'id': 'mock', 'choices': [
                {'index': 0, 'message': {'role': 'assistant', 'content': content}}]})
        elif path == '/interrupt':
            self._json({'ok': True})
        else:
            self._json({'error': 'not found'}, 404)


if __name__ == '__main__':
    print('Mock LLM+ComfyUI listening on 0.0.0.0:%d' % PORT)
    print('  LLM base  : http://<host>:%d  （客户端自动拼 /v1/chat/completions）' % PORT)
    print('  ComfyUI   : http://<host>:%d' % PORT)
    print('  提交的工作流会存到 build/mock/submitted_*.json 供断言')
    ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
