#!/bin/bash

echo "开始清理 V2Ray TPROXY 相关配置..."

# 删除 iptables 规则引用
echo "删除 iptables 规则引用..."
iptables -t mangle -D PREROUTING -j V2RAY 2>/dev/null
iptables -t mangle -D OUTPUT -j V2RAY_MASK 2>/dev/null
iptables -t mangle -D PREROUTING -p tcp -m socket -j DIVERT 2>/dev/null

# 清空并删除 V2RAY 链
echo "清理 V2RAY 链..."
iptables -t mangle -F V2RAY 2>/dev/null
iptables -t mangle -X V2RAY 2>/dev/null

# 清空并删除 V2RAY_MASK 链
echo "清理 V2RAY_MASK 链..."
iptables -t mangle -F V2RAY_MASK 2>/dev/null
iptables -t mangle -X V2RAY_MASK 2>/dev/null

# 清空并删除 DIVERT 链
echo "清理 DIVERT 链..."
iptables -t mangle -F DIVERT 2>/dev/null
iptables -t mangle -X DIVERT 2>/dev/null

# 删除 ip route 规则
echo "删除自定义路由规则..."
ip route del local 0.0.0.0/0 dev lo table 100 2>/dev/null

# 删除 ip rule 规则
echo "删除自定义路由规则..."
ip rule del fwmark 1 table 100 2>/dev/null

echo "清理完成！"

# 可选：显示当前状态
echo ""
echo "=== 当前 iptables mangle 表 ==="
iptables -t mangle -L -n -v

echo ""
echo "=== 当前 ip rules ==="
ip rule show

echo ""
echo "=== table 100 路由 ==="
ip route show table 100