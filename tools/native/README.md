# Android KataGo host

`tools/build_katago_android.sh [cpu|opencl|all]` builds pinned KataGo v1.16.5.
The default is `all`. OpenCL-Headers v2025.07.22 is pinned at
`8a97ebc88daa3495d6f57ec10bb515224400186f` (Khronos Group, Apache-2.0;
the license is already bundled as `assets/katago/COPYING.APACHE`). The generated
loader uses these header declarations; it dynamically loads the device's driver
inside the KataGo child process. No private APK ABI is called.

The `easyplay/katago` MethodChannel uses these methods:

| Method | Arguments | Result |
| --- | --- | --- |
| `backendPreflight` | `backend`: cpu/opencl/tflite; optional `openclLibraryName`, `openclGpuIdx`, and full model/config arguments below | Map: backend, available, runnable, library, reason, devices (index/name/vendor/version); with model: tuningId, tuned |
| `start` | `model`: Uint8List, `config`: String; optional `modelFileName`, `backend` (cpu), `boardSize` (19), `openclGpuIdx` (-1 auto), `openclLibraryName`, `humanModel`: Uint8List, `humanModelFileName`, `humanSLProfile` | `ready` |
| `command` | `line`: single GTP command | String GTP response without leading `=` |
| `stop` | none | `stopped`; invalidates queued work and immediately detaches the old process |
| `openclTuningStart` | Same model/config/board/GPU/library fields as `start`; optional `force`: bool | Tuning snapshot |
| `openclTuningRead` | `id`: tuning job ID (omit for latest) | Tuning snapshot |
| `openclTuningCancel` | `id`: tuning job ID (omit for latest) | Tuning snapshot |
| `openclTuningReset` | `tuningId`: cache ID or full model/config arguments | Map: tuningId, reset |
| `diagnostics` | none | Map: backend, running, logs, tuning |

Tuning snapshots contain `id` (task UUID), `tuningId` (cache SHA-256), `status`
(`queued`, `running`, `completed`, `cancelled`, `failed`), `stage`, `error`,
and `logs` (latest 160 lines). Polling does not block on tuning or GTP search.
Preflight is isolated in its own process with an eight second timeout.

The same neural-network/OpenCL configuration, model bytes, optional human model bytes, board size,
GPU and driver library must be used for tuning and startup. Search strength, komi and human rank do not invalidate the tuning cache. The cache also
includes the Android build fingerprint and engine version. A successful tuning
marker contains checksums for the generated cache files; changed or missing
cache files require tuning again. Both main and human networks are tuned.

OpenCL startup raises `KATAGO_TUNING_REQUIRED` until a verified cache exists.
TFLite raises `KATAGO_UNSUPPORTED`: the pinned upstream KataGo release has no
LiteRT backend, and the reference APK's shared-library ABI is not published.
All native failures stay in child processes. Generic channel failures use
`KATAGO`, and calls after host disposal use `KATAGO_CLOSED`.

Device verification: Adreno 830 on Android API 36 enumerated successfully,
completed b6 9x9 tuning and a GTP `genmove B` returned `F5` (exit code 0).
Adreno's rejection of a union of valid device-type flags is handled by retrying
device enumeration with `CL_DEVICE_TYPE_ALL`; KataGo filters the resulting types.

The official `b18c384nbt-humanv0.bin.gz` human model was also tested on the same
device with the CPU backend, b6 main model, a 9x9 board,
`humanSLProfile=rank_5k`, `humanSLChosenMoveProp=1.0`, `maxVisits=1` and
`maxTime=1`. KataGo loaded the human SL net, generated `F6`, and exited with
code 0. The downloaded model was 99,066,230 bytes, SHA-256
`637746e44f0efe00ad1245a50aa9bbf0716efe364c43965ead97bd6835d84ab5`.
This verifies the native CPU human-model path; OpenCL plus the human model
still requires its own tuning run on the selected device.
