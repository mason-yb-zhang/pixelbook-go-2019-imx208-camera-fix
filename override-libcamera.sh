#!/bin/bash
set -e

# 覆盖系统 libcamera 为新编译的 IMX208 补丁版本。
#
# 重要：备份文件必须移出库目录（/lib64、/usr/lib64），否则 ldconfig 会把
# 它们也当成候选库（.bak 文件同样带有合法 SONAME，且文件名被当作更高版本），
# 从而把 libcamera.so.0.7 符号链接错误地指回备份的原版库——这正是历史上
# "补丁明明编译进去了，运行时却找不到 imx208" 的根因。

BACKUP_DIR="$HOME/libcamera-backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "备份旧版本到 $BACKUP_DIR ..."
sudo cp -a /usr/lib64/libcamera/ipa/ipa_ipu3.so "$BACKUP_DIR/ipa_ipu3.so"
sudo cp -a /lib64/libcamera.so.0.7.2 "$BACKUP_DIR/libcamera.so.0.7.2"
sudo cp -a /lib64/libcamera-base.so.0.7.2 "$BACKUP_DIR/libcamera-base.so.0.7.2"

echo "覆盖为新编译版本（直接替换实际 .so 文件，保持符号链接不动）..."
sudo cp -a /usr/local/lib64/libcamera/ipa/ipa_ipu3.so /usr/lib64/libcamera/ipa/ipa_ipu3.so
sudo cp -a /usr/local/lib64/libcamera.so.0.7.2 /lib64/libcamera.so.0.7.2
sudo cp -a /usr/local/lib64/libcamera-base.so.0.7.2 /lib64/libcamera-base.so.0.7.2

echo "修正符号链接（防止 ldconfig 指错）..."
sudo ln -sfn libcamera.so.0.7.2 /lib64/libcamera.so.0.7
sudo ln -sfn libcamera.so.0.7 /lib64/libcamera.so
sudo ln -sfn libcamera-base.so.0.7.2 /lib64/libcamera-base.so.0.7
sudo ln -sfn libcamera-base.so.0.7 /lib64/libcamera-base.so

echo "更新动态链接器缓存..."
sudo ldconfig

echo "重启 PipeWire..."
systemctl --user restart pipewire wireplumber

echo ""
echo "完成！请检查摄像头："
echo "  pw-cli ls Node | grep -i camera"
echo "  cam --list"
