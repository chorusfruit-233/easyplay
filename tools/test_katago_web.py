#!/usr/bin/env python3
"""Run a real b6 GTP search against the static WebAssembly worker in Firefox."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
from selenium import webdriver
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.support.ui import WebDriverWait

root = Path(__file__).resolve().parents[1] / "build" / "web"
if not (root / "katago_smoke.html").is_file():
    raise SystemExit("Run `flutter build web --release` before this smoke test.")


class StaticHeaders(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        super().end_headers()


server = ThreadingHTTPServer(
    ("127.0.0.1", 0), partial(StaticHeaders, directory=str(root))
)
Thread(target=server.serve_forever, daemon=True).start()
options = Options()
options.add_argument("-headless")
driver = webdriver.Firefox(options=options)
try:
    driver.get(f"http://127.0.0.1:{server.server_port}/katago_smoke.html")
    result = WebDriverWait(driver, 120).until(
        lambda current: (
            value
            if (value := current.find_element("tag name", "body").text)
            and value != "waiting"
            else False
        )
    )
    if result.startswith("ERROR:"):
        raise RuntimeError(result)
    if not result or result.lower() == "pass":
        raise RuntimeError(f"Unexpected KataGo move: {result!r}")
    print(f"KataGo b6 returned {result} from static Worker/WASM.")
    final = driver.execute_async_script(
        "const payload = arguments[0]; const done = arguments[arguments.length - 1]; "
        "globalThis.easyPlayKataGoAdjudicate(JSON.stringify(payload)).then(done).catch(e => done('ERROR: ' + e));",
        {
            "id": 90,
            "boardSize": 9,
            "rules": "chinese",
            "komi": 7.5,
            "setup": [],
            "moves": ["play B pass", "play W pass"],
        },
    )
    if str(final).startswith("ERROR:"):
        raise RuntimeError(final)
    print(f"KataGo b6 returned final adjudication: {final}.")
    for board_size, setup, moves, rules in [
        (13, ["play B D10", "play B K10"], ["play W G7"], "japanese"),
        (19, ["play B D16", "play B Q4"], ["play W Q16"], "korean"),
    ]:
        payload = {
            "id": board_size,
            "boardSize": board_size,
            "rules": rules,
            "komi": 6.5,
            "setup": setup,
            "moves": moves,
            "side": "W",
        }
        move = driver.execute_async_script(
            "const payload = arguments[0]; const done = arguments[arguments.length - 1]; "
            "globalThis.easyPlayKataGoGenmove(JSON.stringify(payload)).then(done).catch(e => done('ERROR: ' + e));",
            payload,
        )
        if str(move).startswith("ERROR:"):
            raise RuntimeError(move)
        print(f"KataGo b6 returned {move} on {board_size}x{board_size} ({rules}).")
finally:
    driver.quit()
    server.shutdown()
