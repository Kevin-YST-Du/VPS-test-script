#!/bin/bash

# 检查是否安装了 jq
if ! command -v jq &> /dev/null; then
    echo "错误: 未安装 jq，请先运行: sudo apt install jq -y"
    exit 1
fi

echo "============================================="
echo "   Tor 出口节点批量指纹查找工具"
echo "============================================="
echo "请输入查询内容，支持以下格式："
echo "1. 国家代码 (例如: de, us, fr)"
echo "2. IP段/CIDR (例如: 185.220.101.0/24)"
echo "3. IPv6段 (例如: 2a03:e600:100::/48)"
echo "---------------------------------------------"
read -p "请输入查询关键词: " INPUT

# 判断输入是国家代码还是 IP 段
if [[ $INPUT =~ ^[a-zA-Z]{2}$ ]]; then
    echo "检测到国家代码: $INPUT，正在查询该国出口节点..."
    SEARCH_QUERY="country:$INPUT%20flag:exit"
else
    echo "检测到 IP 段/关键词: $INPUT，正在查询匹配的出口节点..."
    # 对 IP 段搜索增加 flag:exit 过滤（通过 jq 过滤更准确）
    SEARCH_QUERY="$INPUT"
fi

echo "正在从 Onionoo API 获取数据，请稍候..."

# 核心查询与处理逻辑
# 1. 获取详情
# 2. 使用 jq 过滤出具有 Exit 标签的节点
# 3. 提取指纹并添加 $ 符号，用逗号连接
RESULT=$(curl -s "https://onionoo.torproject.org/details?search=$SEARCH_QUERY" | \
jq -r '.relays[] | select(.flags | contains(["Exit"])) | .fingerprint' | \
sed 's/^/$/' | tr '\n' ',' | sed 's/,$//')

if [ -z "$RESULT" ] || [ "$RESULT" == "$" ]; then
    echo "---------------------------------------------"
    echo "结果: 未找到匹配且带有 Exit 标签的活跃节点。"
else
    echo "---------------------------------------------"
    echo "查询成功！共找到 $(echo $RESULT | tr ',' '\n' | wc -l) 个出口节点。"
    echo ""
    echo "请将以下内容复制到你的 torrc 配置文件中："
    echo "---------------------------------------------"
    echo "ExitNodes $RESULT"
    echo "StrictNodes 1"
    echo "---------------------------------------------"
    
    # 询问是否自动应用到某个实例 (可选)
    read -p "是否要将此配置应用到某个 Tor 实例? (y/n): " APPLY
    if [ "$APPLY" == "y" ]; then
        read -p "请输入实例名称 (例如 de, us): " INSTANCE
        CONF_PATH="/etc/tor/instances/$INSTANCE/torrc"
        if [ -f "$CONF_PATH" ]; then
            # 使用 sed 替换或追加 ExitNodes 行
            sudo sed -i '/^ExitNodes/d' "$CONF_PATH"
            sudo sed -i '/^StrictNodes/d' "$CONF_PATH"
            sudo bash -c "echo 'ExitNodes $RESULT' >> $CONF_PATH"
            sudo bash -c "echo 'StrictNodes 1' >> $CONF_PATH"
            sudo systemctl restart tor@$INSTANCE
            echo "已成功更新 /etc/tor/instances/$INSTANCE/torrc 并重启服务。"
        else
            echo "错误: 配置文件 $CONF_PATH 不存在。"
        fi
    fi
fi