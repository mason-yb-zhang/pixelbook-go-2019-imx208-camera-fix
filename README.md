# IMX208 + Intel IPU3 摄像头修复

## 问题描述

Intel IPU3 + Sony IMX208 方案的笔记本内置摄像头在 Linux（Fedora 44 + libcamera 0.7.1）下无法被识别。

系统日志核心错误：
```
ERROR IPAIPU3 ipu3.cpp:306 ipu3: Failed to create camera sensor helper for imx208
ERROR IPU3 ipu3.cpp:1194 Failed to initialise the IPU3 IPA
```

## 根因分析

1. **libcamera 缺少 IMX208 的 `CameraSensorHelper`**
   - IPU3 IPA 需要为每个传感器注册一个 helper 类来处理增益计算
   - IMX208 没有注册，导致 IPA 初始化直接失败

2. **libcamera 缺少 IMX208 的传感器属性数据库**
   - `camera_sensor_properties.cpp` 中没有 IMX208 的条目

3. **内核 imx208 驱动缺少 `get_selection` pad op**
   - libcamera 需要通过 V4L2 subdevice 查询 crop rectangle、bounds 和 native size
   - 内核驱动未实现，导致大量 WARNING

## 修复内容

| 文件 | 说明 |
|------|------|
| `libcamera-add-imx208-helper.patch` | 为 libcamera 添加 IMX208 sensor helper 和属性 |
| `kernel-imx208-add-get_selection.patch` | 为内核驱动添加 V4L2 selection 支持 |
| `build-and-install-libcamera.sh` | 一键编译安装脚本 |
| `override-libcamera.sh` | 用新编译库覆盖系统旧库 |
| `README-IMX208-修复指南.md` | 详细的中文编译安装指南 |

## 快速使用

```bash
# 1. 编译安装 libcamera
bash build-and-install-libcamera.sh

# 2. 覆盖系统旧库
bash override-libcamera.sh

# 3. 验证摄像头
pw-cli ls Node | grep -i camera
```

## 环境信息

- **硬件**: Intel IPU3 + Sony IMX208
- **系统**: Fedora 44
- **内核**: 7.0.10-201.fc44.x86_64
- **libcamera**: 0.7.1

## 备注

- IMX208 的增益模型参数是基于与 IMX219 的相似性推断的（同索尼系列，寄存器地址相同 0x0204）
- 如果画面亮度异常，可能需要根据真实数据手册调整 `AnalogueGainLinear` 参数
