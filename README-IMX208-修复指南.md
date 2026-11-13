# IMX208 摄像头修复指南（v2.0.0）

## 问题概述

你的设备使用 **Intel IPU3 + Sony IMX208** 方案，摄像头无法被系统识别。

根因有三个：
1. **libcamera 缺少 IMX208 的 sensor helper** → IPU3 IPA 初始化失败
2. **libcamera 缺少 IMX208 的传感器属性** → 属性里的 `testPatternModes` 缺失会让 IPU3 管线在 `start()` 阶段 `setTestPatternMode()` 失败，**导致无法出图**
3. **内核 imx208 驱动缺少 `get_selection` pad op** → libcamera 无法获取 sensor crop 信息

## 版本对应

| 版本 | 内核 | libcamera |
|------|------|-----------|
| v2.0.0（本文档） | 7.3.x | 0.7.2 |
| v1.0.0 | 7.0.10 | 0.7.1 |

**v2.0.0 相对 v1.0.0 的内核接口变化**（补丁适配点）：
- `imx208_get_fmt` → `imx208_get_pad_format`
- `imx208_set_fmt` → `imx208_set_pad_format`
- `imx208->mode->format` → `imx208->cur_mode`（直接 `->width` / `->height`）

---

## 第一部分：编译安装 libcamera（0.7.2）

### 1. 安装编译依赖

```bash
sudo dnf install -y meson ninja-build gcc-c++ gnutls-devel openssl-devel \
    libtiff-devel libyaml-devel python3-yaml python3-jinja2 python3-ply \
    glib2-devel gstreamer1-plugins-base-devel \
    qt5-qtbase-devel libepoxy-devel boost-devel python3-pybind11 \
    libevent-devel git
```

### 2. 获取 0.7.2 源码

```bash
cd /tmp
dnf download --source libcamera      # 若 updates-source 源 404，改从 Koji 下载
# Koji 备选：
# curl -L -o libcamera.src.rpm "https://kojipkgs.fedoraproject.org/packages/libcamera/0.7.2/2.fc44/src/libcamera-0.7.2-2.fc44.src.rpm"
rpm2cpio libcamera-0.7.2-*.src.rpm | cpio -idmv
tar -xjf libcamera-v0.7.2.tar.bz2
```

### 3. 应用 Patch

```bash
cd /tmp/libcamera-v0.7.2
patch -p1 < ~/imx208-camera-fix/libcamera-add-imx208-helper.patch
```

若 patch 提示行号不对，按补丁内容手动编辑两个文件：
- `src/ipa/libipa/camera_sensor_helper.cpp` — 在 imx219 后加 `CameraSensorHelperImx208` 类并注册
- `src/libcamera/sensor/camera_sensor_properties.cpp` — 在 imx258 前加 `{ "imx208", {...} }` 条目（**含 `testPatternModes`，缺了会无法出图**）

### 4. 编译并安装

```bash
cd /tmp/libcamera-v0.7.2
# 禁用 ccache，避免 mtime 未更新导致返回缓存旧对象
CCACHE_DISABLE=1 CXXFLAGS="-Wno-error=array-bounds -Wno-error" \
    meson setup build --buildtype=release \
    -Dgstreamer=enabled -Dpipelines=ipu3 -Dipas=ipu3 \
    -Dv4l2=enabled -Dcam=enabled -Dqcam=disabled \
    -Ddocumentation=disabled -Dlc-compliance=disabled \
    -Dpycamera=disabled -Dtracing=disabled -Dtest=false

CCACHE_DISABLE=1 ninja -C build
sudo ninja -C build install
sudo ldconfig
```

### 5. 覆盖系统库

```bash
bash ~/imx208-camera-fix/override-libcamera.sh
```

**关键坑**：备份文件必须移出 `/lib64`，否则 `ldconfig` 会把 `.bak` 当更高版本、把
`libcamera.so.0.7` 符号链接指回原版库（症状：补丁编译进去了，运行时仍找不到 imx208）。
`override-libcamera.sh` 已把备份放到 `~/libcamera-backups/` 并显式修正符号链接。

---

## 第二部分：编译内核模块（get_selection）

### 1. 安装内核开发包

```bash
sudo dnf install -y kernel-devel-$(uname -r) kernel-headers-$(uname -r)
```

### 2. 获取 imx208.c 源码

```bash
mkdir -p /tmp/imx208 && cd /tmp/imx208
curl -L -o imx208.c \
  "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/media/i2c/imx208.c?h=v7.3"
```

> 内核 7.3.x 的 imx208.c 已原生实现 `V4L2_CID_TEST_PATTERN` 控制（0x0600 寄存器），
> 无需额外补丁；只需补 `get_selection`。

### 3. 应用 Patch

```bash
patch -p1 < ~/imx208-camera-fix/kernel-imx208-add-get_selection.patch
```

若 patch 不适用，手动改两处：

**A. 在 `imx208_enum_frame_size` 函数之后添加 `imx208_get_selection`：**

```c
static int imx208_get_selection(struct v4l2_subdev *sd,
				struct v4l2_subdev_state *sd_state,
				struct v4l2_subdev_selection *sel)
{
	struct imx208 *imx208 = to_imx208(sd);

	switch (sel->target) {
	case V4L2_SEL_TGT_CROP:
	case V4L2_SEL_TGT_CROP_DEFAULT:
	case V4L2_SEL_TGT_CROP_BOUNDS:
		sel->r.left = 0;
		sel->r.top = 0;
		sel->r.width = imx208->cur_mode->width;
		sel->r.height = imx208->cur_mode->height;
		return 0;
	case V4L2_SEL_TGT_NATIVE_SIZE:
		/* Native pixel array size: 1936 x 1096 */
		sel->r.left = 0;
		sel->r.top = 0;
		sel->r.width = 1936;
		sel->r.height = 1096;
		return 0;
	default:
		return -EINVAL;
	}
}
```

**B. 在 `imx208_pad_ops` 结构体中加一行：**

```c
static const struct v4l2_subdev_pad_ops imx208_pad_ops = {
	.enum_mbus_code = imx208_enum_mbus_code,
	.get_fmt = imx208_get_pad_format,
	.set_fmt = imx208_set_pad_format,
	.enum_frame_size = imx208_enum_frame_size,
	.get_selection = imx208_get_selection,   /* <-- 添加 */
};
```

### 4. 编译模块

```bash
cat > /tmp/imx208/Makefile << 'EOF'
KVER := $(shell uname -r)
KDIR := /lib/modules/$(KVER)/build
obj-m += imx208.o
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules
clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
EOF

cd /tmp/imx208 && make
```

### 5. 安装模块

```bash
# 关键：必须用 --check=crc32，xz 默认 CRC64 会被内核拒绝
sudo xz --check=crc32 -f imx208.ko
sudo install -m 644 imx208.ko.xz \
    /lib/modules/$(uname -r)/kernel/drivers/media/i2c/imx208.ko.xz
sudo depmod -a
```

> 内核会报 `decompression failed with status 6` 若用默认 xz 压缩（CRC64）。

### 6. 重新加载模块

```bash
# 解绑 i2c 设备（设备名可能是 i2c-INT3478:00 或 2-0010）
echo i2c-INT3478:00 | sudo tee /sys/bus/i2c/drivers/imx208/unbind
sudo modprobe -r imx208
sudo modprobe imx208
```

---

## 第三部分：验证

```bash
# 摄像头识别
pw-cli ls Node | grep -i camera
cam --list                       # 应列出 'imx208'，且无 "No static properties" 警告

# 实际抓帧
cam -c 1 --capture=1 --file=/tmp/frame
```

`cam --list` 中若出现 `No static properties available for 'imx208'`，说明 libcamera
属性补丁没生效（通常是 ldconfig 符号链接指错或 ccache 缓存，见"已知坑"）。

---

## 已知坑汇总

1. **xz 压缩**：`.ko` 必须 `xz --check=crc32`，否则内核报 `decompression failed status 6`。
2. **ldconfig 符号链接**：`.bak` 备份不能留在 `/lib64`，否则 `libcamera.so.0.7` 会被指回原版。
3. **ccache 缓存**：源码 mtime 未更新时 ccache 返回旧对象，编译前 `export CCACHE_DISABLE=1`。
4. **Secure Boot**：本机已关闭 Secure Boot。若开启，自编译内核模块需用 MOK 签名（见 v1.0.0 指南）。

## 注意事项

- IMX208 增益模型 `AnalogueGainLinear{ 0, 256, -1, 256 }` 基于与 IMX219 相似性推断；画面亮度异常时需按数据手册调整。
- 修复后摄像头仍可能报"Camera location / Rotation not available"等无害警告（驱动未实现对应控制）。

## 参考

- [libcamera 源码](https://git.libcamera.org/libcamera/libcamera.git/)
- [Linux 内核 imx208.c](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/media/i2c/imx208.c)
