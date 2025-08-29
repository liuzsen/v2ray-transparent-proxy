#!/bin/bash
set -e

echo "[*] 删除路由规则..."
ip rule del fwmark 1 table 100 2>/dev/null || true
ip route flush table 100 2>/dev/null || true

echo "[*] 删除 iptables 规则..."

# 删除挂接到 PREROUTING 的 V2RAY 链
iptables -t mangle -D PREROUTING -j V2RAY 2>/dev/null || true
# 删除挂接到 OUTPUT 的 V2RAY_MASK 链
iptables -t mangle -D OUTPUT -j V2RAY_MASK 2>/dev/null || true
# 删除插入到 PREROUTING 的 DIVERT 链规则
iptables -t mangle -D PREROUTING -p tcp -m socket -j DIVERT 2>/dev/null || true

# 清空并删除自定义链
for chain in V2RAY V2RAY_MASK DIVERT; do
    iptables -t mangle -F $chain 2>/dev/null || true
    iptables -t mangle -X $chain 2>/dev/null || true
done

echo "[*] 完成，路由表与 iptables 已恢复。"