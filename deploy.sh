# 检查是否以 root 身份运行
if [ "$EUID" -ne 0 ]; then
    echo "错误：此脚本必须以 root 权限运行"
    echo "请使用 sudo 或以 root 用户身份执行此脚本"
    echo "示例：sudo $0"
    exit 1
fi

apt-get update
apt-get install -y iproute2 iptables curl


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
    read -p "未检测到网络段，请手动输入: " LOCAL_NETWORK
    # 验证输入不为空
    while [ -z "$LOCAL_NETWORK" ]; do
        echo "网络段不能为空"
        read -p "请输入网络段: " LOCAL_NETWORK
    done
fi

echo "最终使用的网络段: $LOCAL_NETWORK"


echo net.ipv4.ip_forward=1 >> /etc/sysctl.conf && sysctl -p


./install-release.sh -l v2ray-linux-64.zip

ip rule add fwmark 1 table 100
ip route add local 0.0.0.0/0 dev lo table 100

iptables -t mangle -N V2RAY
iptables -t mangle -A V2RAY -d 127.0.0.1/32 -j RETURN
iptables -t mangle -A V2RAY -d 224.0.0.0/4 -j RETURN 
iptables -t mangle -A V2RAY -d 255.255.255.255/32 -j RETURN 
iptables -t mangle -A V2RAY -d $LOCAL_NETWORK -p tcp -j RETURN 
iptables -t mangle -A V2RAY -d $LOCAL_NETWORK -p udp ! --dport 53 -j RETURN 
iptables -t mangle -A V2RAY -j RETURN -m mark --mark 0xff    
iptables -t mangle -A V2RAY -p udp -j TPROXY --on-ip 127.0.0.1 --on-port 12345 --tproxy-mark 1 
iptables -t mangle -A V2RAY -p tcp -j TPROXY --on-ip 127.0.0.1 --on-port 12345 --tproxy-mark 1 
iptables -t mangle -A PREROUTING -j V2RAY 

iptables -t mangle -N V2RAY_MASK 
iptables -t mangle -A V2RAY_MASK -d 224.0.0.0/4 -j RETURN 
iptables -t mangle -A V2RAY_MASK -d 255.255.255.255/32 -j RETURN 
iptables -t mangle -A V2RAY_MASK -d $LOCAL_NETWORK -p tcp -j RETURN 
iptables -t mangle -A V2RAY_MASK -d $LOCAL_NETWORK -p udp ! --dport 53 -j RETURN 
iptables -t mangle -A V2RAY_MASK -j RETURN -m mark --mark 0xff    
iptables -t mangle -A V2RAY_MASK -p udp -j MARK --set-mark 1   
iptables -t mangle -A V2RAY_MASK -p tcp -j MARK --set-mark 1   
iptables -t mangle -A OUTPUT -j V2RAY_MASK 

iptables -t mangle -N DIVERT
iptables -t mangle -A DIVERT -j MARK --set-mark 1
iptables -t mangle -A DIVERT -j ACCEPT
iptables -t mangle -I PREROUTING -p tcp -m socket -j DIVERT

cp ./config.json /usr/local/etc/v2ray/config.json
systemctl enable v2ray
systemctl start v2ray