#!/usr/bin/env python3
"""Generate typed OpenCL forwarding functions from pinned Khronos headers.

Only functions called by pinned KataGo sources are emitted. No driver library is
linked into the APK: the child process loads the device's OpenCL implementation.
"""
import pathlib
import re
import sys

katago, headers, output = map(pathlib.Path, sys.argv[1:])
used = set()
for source in (katago / "cpp/neuralnet").glob("opencl*.cpp"):
    used.update(re.findall(r"\b(cl[A-Z]\w*)\s*\(", source.read_text()))
header = (headers / "CL/cl.h").read_text()
prefix = r'''
#define CL_TARGET_OPENCL_VERSION 120
#define CL_USE_DEPRECATED_OPENCL_1_2_APIS
#include <CL/cl.h>
#include <dlfcn.h>
#include <cstdio>
#include <cstdlib>
#include <mutex>

static void* driver() {
  static std::once_flag once;
  static void* handle = nullptr;
  std::call_once(once, [] {
    const char* explicitLibrary = std::getenv("EASYPLAY_OPENCL_LIBRARY");
    if(explicitLibrary && explicitLibrary[0]) {
      handle = dlopen(explicitLibrary, RTLD_NOW | RTLD_LOCAL);
      if(!handle) std::fprintf(stderr, "OpenCL loader: %s\n", dlerror());
      return;
    }
    const char* candidates[] = {
      "libOpenCL.so", "/vendor/lib64/libOpenCL.so",
      "/system/vendor/lib64/libOpenCL.so", "libGLES_mali.so",
      "/vendor/lib64/egl/libGLES_mali.so", "/vendor/lib64/libPVROCL.so"
    };
    for(const char* candidate : candidates) {
      handle = dlopen(candidate, RTLD_NOW | RTLD_LOCAL);
      if(handle) { std::fprintf(stderr, "OpenCL loader: %s\n", candidate); return; }
    }
    std::fprintf(stderr, "OpenCL loader: no accessible device driver\n");
  });
  return handle;
}
template<class T> static T symbol(const char* name) {
  void* handle = driver();
  return handle ? reinterpret_cast<T>(dlsym(handle, name)) : nullptr;
}
'''
wrappers = []
for name in sorted(used):
    match = re.search(r"extern CL_API_ENTRY (?:CL_API_PREFIX__\w+ )?(\w+) CL_API_CALL\s+" + name + r"\((.*?)\) CL_API_SUFFIX", header, re.S)
    if not match:
        raise SystemExit(f"Missing Khronos declaration for {name}")
    result_type, declaration = match.groups()
    # Split parameters at top-level commas, preserving typed callbacks.
    params, start, depth = [], 0, 0
    for i, char in enumerate(declaration):
        depth += (char == "(") - (char == ")")
        if char == "," and depth == 0:
            params.append(declaration[start:i].strip())
            start = i + 1
    params.append(declaration[start:].strip())
    names = []
    for parameter in params:
        callback = re.search(r"CL_CALLBACK\s*\*\s*(\w+)", parameter)
        names.append(callback.group(1) if callback else re.search(r"(\w+)\s*$", parameter).group(1))
    fallback = 'std::fprintf(stderr, "OpenCL symbol unavailable: ' + name + '\\n"); std::abort();'
    if name == "clGetPlatformIDs":
        fallback = "if(num_platforms) *num_platforms = 0; return -1001;"
    call = f'return function({", ".join(names)});'
    if name == "clGetDeviceIDs":
        # Some Android Adreno drivers reject a legal union of type bits.
        # KataGo filters device types again after enumeration.
        call = '''cl_int result = function(platform, device_type, num_entries, devices, num_devices);
  if(result == CL_INVALID_DEVICE_TYPE && device_type == (CL_DEVICE_TYPE_CPU | CL_DEVICE_TYPE_GPU | CL_DEVICE_TYPE_ACCELERATOR))
    return function(platform, CL_DEVICE_TYPE_ALL, num_entries, devices, num_devices);
  return result;'''
    wrappers.append(f'''extern "C" CL_API_ENTRY {result_type} CL_API_CALL {name}({declaration}) {{
  static auto function = symbol<decltype(&{name})>("{name}");
  if(!function) {{ {fallback} }}
  {call}
}}
''')
output.write_text(prefix + "\n".join(wrappers))
