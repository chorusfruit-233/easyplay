#define CL_TARGET_OPENCL_VERSION 120
#include <CL/cl.h>
#include <cstdio>
#include <string>
#include <vector>

static std::string quoted(const std::string& value) {
  std::string result = "\"";
  for(unsigned char c : value) {
    if(c == '\\' || c == '"') result += '\\';
    if(c >= 32) result += c;
  }
  return result + "\"";
}
static std::string info(cl_device_id device, cl_device_info key) {
  size_t bytes = 0;
  if(clGetDeviceInfo(device, key, 0, nullptr, &bytes) != CL_SUCCESS || bytes == 0) return "";
  std::vector<char> text(bytes);
  if(clGetDeviceInfo(device, key, bytes, text.data(), nullptr) != CL_SUCCESS) return "";
  return std::string(text.data());
}
int main() {
  cl_uint count = 0;
  if(clGetPlatformIDs(0, nullptr, &count) != CL_SUCCESS || count == 0 || count > 32) {
    std::puts("{\"available\":false,\"devices\":[],\"reason\":\"No accessible OpenCL platform\"}");
    return 1;
  }
  std::vector<cl_platform_id> platforms(count);
  if(clGetPlatformIDs(count, platforms.data(), nullptr) != CL_SUCCESS) return 1;
  std::string devices;
  int index = 0;
  for(auto platform : platforms) {
    cl_uint deviceCount = 0;
    if(clGetDeviceIDs(platform, CL_DEVICE_TYPE_ALL, 0, nullptr, &deviceCount) != CL_SUCCESS || deviceCount > 512) continue;
    std::vector<cl_device_id> found(deviceCount);
    if(clGetDeviceIDs(platform, CL_DEVICE_TYPE_ALL, deviceCount, found.data(), nullptr) != CL_SUCCESS) continue;
    for(auto device : found) {
      cl_device_type type = 0;
      clGetDeviceInfo(device, CL_DEVICE_TYPE, sizeof(type), &type, nullptr);
      // Match the device indexing used by KataGo's OpenCL helper.
      if(!(type & (CL_DEVICE_TYPE_CPU | CL_DEVICE_TYPE_GPU | CL_DEVICE_TYPE_ACCELERATOR))) continue;
      if(!devices.empty()) devices += ",";
      devices += "{\"index\":" + std::to_string(index++) + ",\"name\":" + quoted(info(device, CL_DEVICE_NAME)) +
        ",\"vendor\":" + quoted(info(device, CL_DEVICE_VENDOR)) + ",\"version\":" + quoted(info(device, CL_DRIVER_VERSION)) + "}";
    }
  }
  std::printf("{\"available\":%s,\"devices\":[%s]}\n", index ? "true" : "false", devices.c_str());
  return index ? 0 : 1;
}
