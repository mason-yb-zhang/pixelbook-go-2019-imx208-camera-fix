#!/bin/bash
set -e

echo "=========================================="
echo "libcamera IMX208 修复编译脚本 (0.7.2)"
echo "=========================================="
echo ""
echo "注意：编译过程中会提示输入 sudo 密码"
echo ""
echo "本脚本针对 libcamera 0.7.2（Fedora 44 + 内核 7.3.x）。"
echo "如果系统 libcamera 已升级到其他版本，请同步修改 SRC_DIR。"
echo ""

# 1. 安装编译依赖
echo "[1/5] 安装编译依赖..."
sudo dnf install -y --skip-unavailable meson ninja-build gcc-c++ gnutls-devel openssl-devel \
    libtiff-devel libyaml-devel python3-yaml python3-jinja2 python3-ply \
    glib2-devel gstreamer1-plugins-base-devel \
    qt5-qtbase-devel libepoxy-devel boost-devel python3-pybind11 \
    libevent-devel git || {
    echo ""
    echo "=========================================="
    echo "警告：依赖安装失败"
    echo "=========================================="
    echo "如果你看到上面提示输入密码，请重新运行脚本并输入 sudo 密码。"
    echo ""
    exit 1
}

# 2. 确认源码目录
SRC_DIR="/tmp/libcamera-v0.7.2"
if [ ! -f "$SRC_DIR/meson.build" ]; then
    echo "错误：找不到 libcamera 源码目录 $SRC_DIR"
    echo "请先解压源码包到 /tmp/libcamera-v0.7.2/"
    echo "获取源码："
    echo "  dnf download --source libcamera   # 或从 Koji 下载 src.rpm"
    echo "  rpm2cpio libcamera-0.7.2-*.src.rpm | cpio -idmv"
    echo "  tar -xjf libcamera-v0.7.2.tar.bz2"
    exit 1
fi

cd "$SRC_DIR"

# 3. 编译
echo "[2/5] 配置编译..."
if [ -d build ]; then
    echo "删除旧的编译目录..."
    rm -rf build
fi

# 禁用 ccache，避免因文件 mtime 未更新导致返回缓存旧对象（曾导致补丁失效）
export CCACHE_DISABLE=1

CXXFLAGS="-Wno-error=array-bounds -Wno-error" meson setup build --buildtype=release \
    -Dgstreamer=enabled \
    -Dpipelines=ipu3 \
    -Dipas=ipu3 \
    -Dv4l2=enabled \
    -Dcam=enabled \
    -Dqcam=disabled \
    -Ddocumentation=disabled \
    -Dlc-compliance=disabled \
    -Dpycamera=disabled \
    -Dtracing=disabled \
    -Dtest=false

echo "[3/5] 开始编译（这可能需要几分钟）..."
ninja -C build

# 4. 安装
echo "[4/5] 安装到系统..."
sudo ninja -C build install
sudo ldconfig

# 5. 重启 PipeWire
echo "[5/5] 重启 PipeWire / WirePlumber..."
systemctl --user restart pipewire wireplumber

echo ""
echo "=========================================="
echo "安装完成！"
echo "=========================================="
echo ""
echo "请检查摄像头是否已识别："
echo "  pw-cli ls Node | grep -i camera"
echo ""
echo "如果没有任何输出，请查看日志："
echo "  journalctl --user -u wireplumber -n 30"
echo ""
