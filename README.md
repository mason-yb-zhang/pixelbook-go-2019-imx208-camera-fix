# IMX208 + Intel IPU3 摄像头修复

Pixelbook Go 2019（Atlas）内置摄像头（Intel IPU3 + Sony IMX208）在 Fedora Linux 下无法被识别的修复。

> **当前版本 2.0.0**：支持 **内核 7.3.x + libcamera 0.7.2**（Fedora 44）。
> 如需旧版（内核 7.0.10 + libcamera 0.7.1），见 git tag `v1.0.0`。

## 问题描述

系统日志核心错误：

```
ERROR IPAIPU3 ipu3.cpp:306 ipu3: Failed to create camera sensor helper for imx208
ERROR IPU3 ipu3.cpp:1194 Failed to initialise the IPU3 IPA
```

## 根因

1. **libcamera 缺少 IMX208 的 `CameraSensorHelper`** — IPU3 IPA 需要为每个传感器注册 helper 类做增益计算，IMX208 未注册导致 IPA 初始化失败。
2. **libcamera 缺少 IMX208 的传感器属性** — `camera_sensor_properties.cpp` 中没有 IMX208 条目；且属性里的 `testPatternModes` 缺失会让 IPU3 管线在 `start()` 阶段调用 `setTestPatternMode()` 失败，导致**无法出图**（不只是警告）。
3. **内核 imx208 驱动缺少 `get_selection` pad op** — libcamera 需要通过 V4L2 subdevice 查询 crop/bounds/native size。

## 版本对应关系

| 版本 | 内核 | libcamera | 说明 |
|------|------|-----------|------|
| v2.0.0（当前） | 7.3.x | 0.7.2 | 驱动接口重构：`imx208_get_fmt`→`imx208_get_pad_format`、`mode->format`→`cur_mode` |
| v1.0.0 | 7.0.10 | 0.7.1 | 初始版本 |

## 文件

| 文件 | 说明 |
|------|------|
| `kernel-imx208-add-get_selection.patch` | 内核驱动补丁（7.3.x） |
| `libcamera-add-imx208-helper.patch` | libcamera 补丁（0.7.2）：helper + 属性 |
| `build-and-install-libcamera.sh` | libcamera 一键编译脚本 |
| `override-libcamera.sh` | 用新编译库覆盖系统库 |
| `README-IMX208-修复指南.md` | 详细中文编译指南 |
| `VERSION` | 版本号 |

## 快速使用

```bash
# 1. 编译安装 libcamera（见详细指南获取 0.7.2 源码）
bash build-and-install-libcamera.sh

# 2. 覆盖系统库
bash override-libcamera.sh

# 3. 编译并加载内核模块（见详细指南第二部分）

# 4. 验证
cam --list                # 应列出 'imx208'
cam -c 1 --capture=1 --file=/tmp/frame   # 应能抓帧
```

## 环境信息

- **硬件**: Intel IPU3 + Sony IMX208
- **系统**: Fedora 44
- **内核**: 7.3.3-200.fc44（v2.0.0 目标）
- **libcamera**: 0.7.2

## 已知坑（务必阅读）

1. **内核模块压缩**：编译出的 `.ko` 必须用 `xz --check=crc32` 压缩（`xz` 默认 CRC64 会被内核精简解压器拒绝，报 `decompression failed with status 6`）。
2. **ldconfig 与备份文件**：手动覆盖 libcamera 后，若把 `.bak` 备份留在 `/lib64`，`ldconfig` 会把它们当作更高版本，把 `libcamera.so.0.7` 符号链接指回原版库。症状是"补丁编译进去了、运行时却找不到 imx208"。务必把备份移出库目录（`override-libcamera.sh` 已处理）。
3. **ccache 缓存**：若源码 mtime 未更新，`ccache`（`compiler_check=mtime`）会返回缓存旧对象。编译脚本已设 `CCACHE_DISABLE=1`。

## 备注

- IMX208 的增益模型参数基于与 IMX219 的相似性推断（同索尼系列，寄存器地址 0x0204）。若画面亮度异常，需按真实数据手册调整 `AnalogueGainLinear`。
