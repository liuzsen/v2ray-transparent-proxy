#!/bin/bash
set -e

# 检查是否以 root 身份运行
if [ "$EUID" -ne 0 ]; then
    echo "错误：此脚本必须以 root 权限运行"
    echo "请使用 sudo 或以 root 用户身份执行此脚本"
    echo "示例：sudo $0"
    exit 1
fi

apt-get update
apt-get install -y iproute2 iptables curl

# 开启 IP 转发
echo net.ipv4.ip_forward=1 >> /etc/sysctl.conf && sysctl -p

# 安装 v2ray
./install-release.sh -l v2ray-linux-64.zip

# 启动 v2ray
cp ./config.json /usr/local/etc/v2ray/config.json
systemctl enable v2ray
systemctl restart v2ray

# 设置 iptables 规则
./set-ip-tables.sh