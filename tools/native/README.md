# Android KataGo CPU bridge

The APK embeds upstream KataGo's arm64 Eigen GTP executable as `libkatago.so`.
It executes from `nativeLibraryDir`; models stay in app-private storage.

The `easyplay/katago` MethodChannel supports:

| Method | Purpose |
| --- | --- |
| `backendPreflight` | Check the CPU executable; return availability and reason. |
| `start` | Start GTP with model ID or bundled bytes, config, board size, optional human model. |
| `validateModel` | Stream a stored model's SHA-256 and compare it with its ID. |
| `command` | Send one GTP command and return its response. |
| `analyze`, `analyzeCancel` | Collect streaming reports and interrupt analysis. |
| `stop` | Invalidate queued work and detach the process. |
| `diagnostics` | Return running state and recent logs. |
| `storeModel`, `loadModel`, `deleteModel` | Manage models; whole-file reads are limited to 8 MB. |

Imported models use SHA-256 IDs. Files are validated and copied by streaming;
large models never return through Flutter's codec during setup or play. The
small bundled b6 may be supplied directly. Filenames retain their format.

`kata-analyze` has no final response until further input. The controller drains
reports, sends a blank line to stop analysis, and consumes the trailing blank
line before the next command.

Native failures occur in the child process. Bridge errors use `KATAGO`; calls
after disposal use `KATAGO_CLOSED`. CPU human-style inference has been verified
with b6 plus the official b18 human network on Android API 36.
