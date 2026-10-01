#!/usr/bin/env python3
"""Optional real Firefox RTC matrix (requires Selenium and Firefox)."""
import json
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
from selenium import webdriver
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.support.ui import WebDriverWait

root = Path(__file__).resolve().parents[1] / 'build/rtc-smoke'
class Handler(SimpleHTTPRequestHandler):
    def translate_path(self, path):
        return super().translate_path(path.removeprefix('/easyplay'))
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()
    def log_message(self, *args): pass
server = ThreadingHTTPServer(('127.0.0.1', 0), partial(Handler, directory=str(root)))
Thread(target=server.serve_forever, daemon=True).start()
options=Options(); options.add_argument('-headless')
driver=None
try:
    driver=webdriver.Firefox(options=options)
    driver.set_script_timeout(60)
    url=f'http://127.0.0.1:{server.server_port}/easyplay/'
    driver.get(url)
    WebDriverWait(driver,60).until(lambda d:d.execute_script('return !!globalThis.easyplayRtcSmoke'))
    host=driver.current_window_handle
    driver.switch_to.new_window('tab'); guest=driver.current_window_handle
    driver.get(url)
    WebDriverWait(driver,60).until(lambda d:d.execute_script('return !!globalThis.easyplayRtcSmoke'))
    def call(tab,method,arg=None):
        driver.switch_to.window(tab)
        result=driver.execute_async_script('const [method,arg,done]=arguments; Promise.resolve(arg===null?easyplayRtcSmoke[method]():easyplayRtcSmoke[method](arg)).then(v=>done({value:v})).catch(e=>done({error:String(e)}));',method,arg)
        if 'error' in result: raise RuntimeError(result['error'])
        return result.get('value')
    def waitseq(tab,n):
        driver.switch_to.window(tab)
        WebDriverWait(driver,15).until(lambda d:json.loads(d.execute_script('return easyplayRtcSmoke.state()'))['seq']==n)
    for game in ['go','chess','english','international','brazilian','russian','pool','italian','spanish','turkish']:
        invite=call(host,'offer',game); response=call(guest,'answer',invite); call(host,'accept',response)
        call(host,'action','start'); call(host,'action','move'); waitseq(guest,1)
        assert json.loads(call(host,'state'))['signature']==json.loads(call(guest,'state'))['signature']
        invite=call(host,'resume'); response=call(guest,'answer',invite); call(host,'accept',response); waitseq(guest,1)
        call(host,'action','large')
        driver.switch_to.window(guest)
        WebDriverWait(driver,15).until(lambda d:json.loads(d.execute_script('return easyplayRtcSmoke.state()'))['padding']==120000)
        print(f'{game}: Firefox real RTC, sync and reconnect passed',flush=True)
finally:
    if driver: driver.quit()
    server.shutdown()
