#!/usr/bin/env python3
"""Check legacy and resolved-config b6 requests against static WASM in Firefox."""
import json
import re
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
driver.set_script_timeout(120)


def request(function, payload):
    return driver.execute_async_script(
        "const [name, payload, done] = arguments; "
        "globalThis[name](JSON.stringify(payload))"
        ".then(value => done({value})).catch(error => done({error: String(error)}));",
        function,
        payload,
    )


def require_move(response, board_size):
    if "error" in response:
        raise RuntimeError(response["error"])
    move = str(response.get("value", ""))
    if not re.fullmatch(r"[A-HJ-T][1-9][0-9]?", move, re.IGNORECASE):
        raise RuntimeError(f"Unexpected KataGo move: {move!r}")
    column = "ABCDEFGHJKLMNOPQRST".index(move[0].upper()) + 1
    if column > board_size or int(move[1:]) > board_size:
        raise RuntimeError(f"KataGo move {move!r} is outside {board_size}x{board_size}")
    return move


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
    require_move({"value": result}, 9)
    print(f"KataGo b6 returned {result} from static Worker/WASM.")
    final_response = request(
        "easyPlayKataGoAdjudicate",
        {
            "id": 90,
            "boardSize": 9,
            "rules": "chinese",
            "komi": 7.5,
            "setup": [],
            "moves": ["play B pass", "play W pass"],
        },
    )
    if "error" in final_response:
        raise RuntimeError(final_response["error"])
    final = json.loads(final_response["value"])
    if not isinstance(final.get("dead"), str) or not re.fullmatch(
        r"(?:[BW]\+(?:[0-9]+(?:\.[0-9]+)?|R)|0)", final.get("score", "")
    ):
        raise RuntimeError(f"Unexpected final adjudication: {final!r}")
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
        move = require_move(
            request("easyPlayKataGoGenmove", payload), board_size
        )
        print(f"KataGo b6 returned {move} on {board_size}x{board_size} ({rules}).")

    # Flutter sends one fully resolved configText. Bad rules in this field must
    # fail even though all legacy request settings are valid, proving that the
    # worker actually passes the supplied cfg to KataGo.
    resolved_config = {
        "rules": "chinese",
        "maxVisits": "16",
        "maxTime": "5",
        "numSearchThreads": "1",
        "nnCacheSizePowerOfTwo": "18",
        "nnMutexPoolSizePowerOfTwo": "14",
        "allowResignation": "false",
        "resignThreshold": "-0.90",
        "resignConsecTurns": "3",
        "logToStderr": "true",
        "logAllGTPCommunication": "false",
        "logSearchInfo": "false",
        "chosenMoveTemperature": "0",
        "chosenMoveTemperatureEarly": "0",
    }
    config_text = "\n".join(f"{key} = {value}" for key, value in resolved_config.items())
    payload = {
        "id": 100,
        "boardSize": 9,
        "rules": "chinese",
        "komi": 7.5,
        "setup": [],
        "moves": [],
        "side": "B",
        "configText": config_text.replace("rules = chinese", "rules = smoke-invalid-rules"),
    }
    invalid = request("easyPlayKataGoGenmove", payload)
    if "error" not in invalid or "smoke-invalid-rules" not in invalid["error"]:
        raise RuntimeError(f"Invalid resolved cfg was not rejected by KataGo: {invalid!r}")
    print("KataGo rejected invalid rules from configText with native diagnostics.")

    # A subsequent valid cfg must recover after native startup fails. These
    # deliberately invalid legacy settings must not overwrite resolved cfg.
    payload.update({
        "id": 101,
        "rules": "smoke-invalid-legacy-rules",
        "configOverrides": "rules = smoke-invalid-legacy-override",
        "configText": config_text,
    })
    move = require_move(request("easyPlayKataGoGenmove", payload), 9)
    print(f"KataGo b6 recovered and returned {move} using only resolved configText.")

    # GTP failures must reach the UI rather than being mistaken for an engine
    # move from an earlier command in the request.
    payload.update({"id": 102, "setup": ["play B A10"]})
    invalid = request("easyPlayKataGoGenmove", payload)
    if "error" not in invalid or "KataGo GTP:" not in invalid["error"]:
        raise RuntimeError(f"Invalid GTP setup was not rejected: {invalid!r}")
    print("KataGo propagated an out-of-bounds GTP setup error.")
finally:
    driver.quit()
    server.shutdown()
