#!/bin/bash
set -e

# 自动检测本地网络
get_local_network() {
    # 方法1：通过路由表获取
    local network=$(ip route | grep -E "192\.168|10\.|172\." | grep -v default | head -1 | awk '{print $1}')
    
    # 如果没找到，尝试其他方法
    if [ -z "$network" ]; then
        network=$(ip route | grep "kernel" | head -1 | awk '{print $1}')
    fi
    
    echo $network
}

# 获取网络段
LOCAL_NETWORK=$(get_local_network)

# 用户确认
if [ -n "$LOCAL_NETWORK" ]; then
    echo "检测到的网络段: $LOCAL_NETWORK"
    read -p "这个网络段是否正确？(Y/n): " REPLY
    echo ""
    
    # 默认是Y，只有输入n或N才需要手动输入
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        read -p "请输入正确的网络段 (例如 192.168.1.0/24): " LOCAL_NETWORK
        # 验证输入不为空
        while [ -z "$LOCAL_NETWORK" ]; do
            echo "网络段不能为空"
            read -p "请输入正确的网络段 (例如 192.168.1.0/24): " LOCAL_NETWORK
        done
    fi
else
    read -p "未检测到网络段，请手动输入(例如 192.168.1.0/24): " LOCAL_NETWORK
    # 验证输入不为空
    while [ -z "$LOCAL_NETWORK" ]; do
        echo "网络段不能为空"
        read -p "请输入网络段: " LOCAL_NETWORK
    done
fi

echo "最终使用的网络段: $LOCAL_NETWORK"

# 设置策略路由
ip rule add fwmark 1 table 100 
ip route add local 0.0.0.0/0 dev lo table 100

# 代理局域网设备
iptables -t mangle -N V2RAY
iptables -t mangle -A V2RAY -d 127.0.0.1/32 -j RETURN
iptables -t mangle -A V2RAY -d 224.0.0.0/4 -j RETURN 
iptables -t mangle -A V2RAY -d 255.255.255.255/32 -j RETURN 
iptables -t mangle -A V2RAY -d $LOCAL_NETWORK -p tcp -j RETURN # 直连局域网，避免 V2Ray 无法启动时无法连网关的 SSH，如果你配置的是其他网段（如 10.x.x.x 等），则修改成自己的
iptables -t mangle -A V2RAY -d $LOCAL_NETWORK -p udp ! --dport 53 -j RETURN # 直连局域网，53 端口除外（因为要使用 V2Ray 的 DNS)
iptables -t mangle -A V2RAY -j RETURN -m mark --mark 0xff    # 直连 SO_MARK 为 0xff 的流量(0xff 是 16 进制数，数值上等同与上面V2Ray 配置的 255)，此规则目的是解决v2ray占用大量CPU（https://github.com/v2ray/v2ray-core/issues/2621）
iptables -t mangle -A V2RAY -p udp -j TPROXY --on-ip 127.0.0.1 --on-port 12345 --tproxy-mark 1 # 给 UDP 打标记 1，转发至 12345 端口
iptables -t mangle -A V2RAY -p tcp -j TPROXY --on-ip 127.0.0.1 --on-port 12345 --tproxy-mark 1 # 给 TCP 打标记 1，转发至 12345 端口
iptables -t mangle -A PREROUTING -j V2RAY # 应用规则

# 代理网关本机
iptables -t mangle -N V2RAY_MASK 
iptables -t mangle -A V2RAY_MASK -d 224.0.0.0/4 -j RETURN 
iptables -t mangle -A V2RAY_MASK -d 255.255.255.255/32 -j RETURN 
iptables -t mangle -A V2RAY_MASK -d $LOCAL_NETWORK -p tcp -j RETURN # 直连局域网
iptables -t mangle -A V2RAY_MASK -d $LOCAL_NETWORK -p udp ! --dport 53 -j RETURN # 直连局域网，53 端口除外（因为要使用 V2Ray 的 DNS）
iptables -t mangle -A V2RAY_MASK -j RETURN -m mark --mark 0xff    # 直连 SO_MARK 为 0xff 的流量(0xff 是 16 进制数，数值上等同与上面V2Ray 配置的 255)，此规则目的是避免代理本机(网关)流量出现回环问题
iptables -t mangle -A V2RAY_MASK -p udp -j MARK --set-mark 1   # 给 UDP 打标记，重路由，由前面设置的策略路由接管，重新进入 PREROUTING 链处理
iptables -t mangle -A V2RAY_MASK -p tcp -j MARK --set-mark 1   # 给 TCP 打标记，重路由，由前面设置的策略路由接管，重新进入 PREROUTING 链处理
iptables -t mangle -A OUTPUT -j V2RAY_MASK # 应用规则

# 新建 DIVERT 规则，避免已有连接的包二次通过 TPROXY，理论上有一定的性能提升
iptables -t mangle -N DIVERT
iptables -t mangle -A DIVERT -j MARK --set-mark 1
iptables -t mangle -A DIVERT -j ACCEPT
iptables -t mangle -I PREROUTING -p tcp -m socket -j DIVERT