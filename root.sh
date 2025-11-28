#!/bin/bash

# 严格模式：遇到错误立即退出
set -e

# ANSI 颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# 显示菜单
# ============================================
display_menu() {
    clear
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${YELLOW}           系统设置脚本菜单            ${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${GREEN}1. 修改 root 用户密码${NC}"
    echo -e "${GREEN}2. 修改 SSH 端口号${NC}"
    echo -e "${GREEN}3. 配置 root 用户 SSH 密钥认证${NC}"
    echo -e "${GREEN}4. 配置普通用户 SSH 密钥认证${NC}"
    echo -e "${GREEN}5. 安装防火墙${NC}"
    echo -e "${GREEN}6. 配置防火墙端口 (已优化，支持空格分隔)${NC}"
    echo -e "${GREEN}7. 安装 Fail2ban 保护 SSH${NC}"
    echo -e "${GREEN}8. 管理 Swap${NC}"
    echo -e "${GREEN}9. 注册 RHEL 系统（subscription-manager / rhc）${NC}"
    echo -e "${GREEN}10. 自动配置 IPv6（智能检测）${NC}"
    echo -e "${GREEN}11. 退出${NC}"
    echo -e "${BLUE}=====================================${NC}"
    read -p "请选择功能 [1-11]: " mu
}

# 函数：检查并重启 SSH 服务
restart_ssh_service() {
    if command -v systemctl >/dev/null 2>&1; then
        echo -e "${GREEN}使用 systemctl 重启 SSH 服务...${NC}"
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
        return 0
    elif command -v service >/dev/null 2>&1; then
        echo -e "${GREEN}使用 service 重启 SSH 服务...${NC}"
        service ssh restart 2>/dev/null || service sshd restart 2>/dev/null
        return 0
    elif [ -x /etc/init.d/ssh ]; then
        echo -e "${GREEN}使用 /etc/init.d/ssh 重启 SSH 服务...${NC}"
        /etc/init.d/ssh restart 2>/dev/null
        return 0
    elif command -v initctl >/dev/null 2>&1; then
        echo -e "${GREEN}使用 initctl 重启 SSH 服务...${NC}"
        initctl restart ssh 2>/dev/null
        return 0
    else
        echo -e "${RED}无法识别的服务管理工具，请手动重启 SSH 服务。${NC}"
        return 1
    fi
}

# 函数：配置 root 用户 SSH 密钥认证 (已修改)
ssh_key() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}请以 root 用户运行此脚本，或先执行 'sudo -i' 进入 root 账户。${NC}"
        exit 1
    fi
    read -p "请输入 root 用户的公钥内容: " ssh_key
    if [ -z "$ssh_key" ]; then
        echo -e "${RED}公钥内容不能为空！${NC}"
        exit 1
    fi

    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    # **新增：询问是否启用密码登录**
    read -p "是否同时保留密码登录（启用：密码+密钥；禁用：仅密钥）？[y/N]: " enable_password

    # 开启公钥认证 (必须)
    sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^PubkeyAuthentication no/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    grep -q '^PubkeyAuthentication' /etc/ssh/sshd_config || echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config

    if [[ "$enable_password" =~ ^[Yy]$ ]]; then
        # 开启密码认证
        sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
        grep -q '^PasswordAuthentication' /etc/ssh/sshd_config || echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config

        # 允许 root 登录（密码+密钥）
        sed -i 's/^PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
        grep -q '^PermitRootLogin' /etc/ssh/sshd_config || echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
        
        MSG="root 用户现在支持 密码登录 + 密钥登录"
    else
        # 默认：关闭密码认证
        sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
        grep -q '^PasswordAuthentication' /etc/ssh/sshd_config || echo "PasswordAuthentication no" >> /etc/ssh/sshd_config

        # 允许 root 登录（仅密钥）
        # PermitRootLogin without-password/prohibit-password 确保禁用密码后也能登录
        sed -i 's/^PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
        grep -q '^PermitRootLogin' /etc/ssh/sshd_config || echo "PermitRootLogin prohibit-password" >> /etc/ssh/sshd_config

        MSG="root 用户现在仅支持 密钥登录 (密码登录已禁用)"
    fi


    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    touch /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo "$ssh_key" >> /root/.ssh/authorized_keys

    if restart_ssh_service; then
        echo -e "${GREEN}SSH 服务已成功重启。${NC}"
    else
        echo -e "${RED}重启 SSH 服务失败，请检查配置。${NC}"
        exit 1
    fi
    echo -e "${GREEN}${MSG}${NC}"
}

# 函数：配置普通用户 SSH 密钥认证 (已修改)
user_ssh_key() {
    current_user=$(whoami)
    if [[ "$current_user" == "root" ]]; then
        echo -e "${YELLOW}当前为 root 用户，建议使用选项 3 配置 root 密钥。${NC}"
        read -p "是否继续为 root 配置？[y/N]: " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
    fi

    read -p "请输入 $current_user 用户的公钥内容: " ssh_key
    if [ -z "$ssh_key" ]; then
        echo -e "${RED}公钥内容不能为空！${NC}"
        exit 1
    fi

    # **新增：询问是否启用密码登录**
    read -p "是否同时保留密码登录（启用：密码+密钥；禁用：仅密钥）？[y/N]: " enable_password

    if [[ $EUID -ne 0 ]]; then
        su='sudo'
    fi

    $su cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    # 开启公钥认证 (必须)
    $su sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    $su sed -i 's/^PubkeyAuthentication no/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    $su grep -q '^PubkeyAuthentication' /etc/ssh/sshd_config || $su sh -c "echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config"

    if [[ "$enable_password" =~ ^[Yy]$ ]]; then
        # 开启密码认证
        $su sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
        $su grep -q '^PasswordAuthentication' /etc/ssh/sshd_config || $su sh -c "echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"

        # 允许 root 登录（全局设置） - 保留原脚本逻辑
        $su sed -i 's/^PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
        $su grep -q '^PermitRootLogin' /etc/ssh/sshd_config || $su sh -c "echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config"

        MSG="用户 $current_user 现在支持 密码登录 + 密钥登录"
    else
        # 默认：关闭密码认证
        $su sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
        $su grep -q '^PasswordAuthentication' /etc/ssh/sshd_config || $su sh -c "echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config"
        
        # 允许 root 登录（全局设置）- 保留原脚本逻辑
        $su sed -i 's/^PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
        $su grep -q '^PermitRootLogin' /etc/ssh/sshd_config || $su sh -c "echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config"

        MSG="用户 $current_user 现在仅支持 密钥登录 (密码登录已禁用)"
    fi

    $su mkdir -p /home/$current_user/.ssh
    $su chown $current_user:$current_user /home/$current_user/.ssh
    $su chmod 700 /home/$current_user/.ssh
    $su touch /home/$current_user/.ssh/authorized_keys
    $su chown $current_user:$current_user /home/$current_user/.ssh/authorized_keys
    $su chmod 600 /home/$current_user/.ssh/authorized_keys
    echo "$ssh_key" | $su tee -a /home/$current_user/.ssh/authorized_keys >/dev/null

    if restart_ssh_service; then
        echo -e "${GREEN}SSH 服务已成功重启。${NC}"
    else
        echo -e "${RED}重启 SSH 服务失败。${NC}"
        exit 1
    fi
    echo -e "${GREEN}${MSG}${NC}"
}

# 函数：修改 SSH 端口（保持密码登录）
ssh_port() {
    read -p "请输入新的 SSH 端口号: " por
    if ! [[ "$por" =~ ^[0-9]+$ ]] || [ "$por" -lt 1 ] || [ "$por" -gt 65535 ]; then
        echo -e "${RED}无效的端口号，必须为 1-65535 之间的数字。${NC}"
        exit 1
    fi
    if [[ $EUID -ne 0 ]]; then
        su='sudo'
    fi

    $su cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    $su sed -i "s/^#Port .*$/Port $por/" /etc/ssh/sshd_config
    $su sed -i "s/^Port .*$/Port $por/" /etc/ssh/sshd_config

    # 确保密码登录开启
    $su sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    $su grep -q '^PasswordAuthentication' /etc/ssh/sshd_config || $su sh -c "echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"

    if restart_ssh_service; then
        echo -e "${GREEN}SSH 端口已修改为 $por 并重启服务成功。${NC}"
        echo -e "${YELLOW}请在防火墙中开放端口 $por。${NC}"
    else
        echo -e "${RED}重启 SSH 服务失败。${NC}"
        exit 1
    fi
}

# 函数：安装防火墙
fire_install() {
    echo -e "${BLUE}防火墙安装选项${NC}"
    echo -e "${GREEN}1. 安装 UFW（推荐用于 Debian/Ubuntu）${NC}"
    echo -e "${GREEN}2. 安装 firewalld（推荐用于 RedHat/CentOS）${NC}"
    read -p "请选择防火墙类型 [1-2]: " num1
    read -p "请输入 SSH 端口号: " shp8
    read -p "是否需要开放 1Panel 端口号？[y/n]: " YN
    if [ "$YN" = "y" ] || [ "$YN" = "Y" ]; then
        read -p "请输入 1Panel 端口号: " shp1
    fi
    if [[ $EUID -ne 0 ]]; then
        su='sudo'
    fi
    if [ "$num1" = "1" ]; then
        $su apt update
        $su apt install ufw -y
        $su ufw allow $shp8/tcp
        [ -n "$shp1" ] && $su ufw allow $shp1/tcp
        $su ufw --force enable
        echo -e "${GREEN}UFW 安装完成，已开放端口 $shp8${shp1:+, $shp1}。${NC}"
    elif [ "$num1" = "2" ]; then
        $su yum update -y
        $su yum install firewalld -y
        $su systemctl start firewalld
        $su systemctl enable firewalld
        $su firewall-cmd --zone=public --add-port=$shp8/tcp --permanent
        [ -n "$shp1" ] && $su firewall-cmd --zone=public --add-port=$shp1/tcp --permanent
        $su firewall-cmd --reload
        echo -e "${GREEN}firewalld 安装完成，已开放端口 $shp8${shp1:+, $shp1}。${NC}"
    else
        echo -e "${RED}无效选择，请输入 1 或 2。${NC}"
        exit 1
    fi
}


# ============================================
# 函数：配置防火墙端口 (优化版 - 增强端口/协议识别, 增加选择菜单)
# ============================================
fire_batch_operation() {
    local operation=$1 # "open" or "close"
    local action_zh=$([[ "$operation" == "open" ]] && echo "开放" || echo "关闭")

    # 提示已修改为使用空格分隔
    read -p "请输入要${action_zh}的端口号（单个或用空格分隔，可带协议，例如: 80 443/tcp 2222/udp）: " port_list
    
    # 检查 root 权限
    if [[ $EUID -ne 0 ]]; then
        su='sudo'
    else
        su=''
    fi
    
    # 检查防火墙类型
    local FIREWALL_CMD
    if command -v ufw >/dev/null 2>&1; then
        FIREWALL_CMD="ufw"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        FIREWALL_CMD="firewall-cmd"
    else
        echo -e "${RED}未安装 UFW 或 firewalld。${NC}"
        return 1
    fi

    # 解析端口列表 - 核心修改：支持端口/协议格式
    local PORTS_AND_PROTOS=()
    # 将所有逗号替换为空格，然后使用 tr -s ' ' 压缩多余空格，并用 xargs 清理首尾空白
    local clean_list=$(echo "$port_list" | tr ',' ' ' | tr -s ' ' | xargs)
    
    if [ -z "$clean_list" ]; then
        echo -e "${RED}端口列表不能为空。${NC}"
        return 1
    fi

    # 遍历清理后的列表，解析每个端口和协议
    for item in $clean_list; do
        if [[ "$item" =~ ^([0-9]+)(\/(tcp|udp))?$ ]]; then
            # 匹配到 [端口][/协议] 格式
            local port=${BASH_REMATCH[1]}
            local proto_specified=${BASH_REMATCH[3]} # 明确指定的协议 (tcp/udp)

            if [[ -n "$proto_specified" ]]; then
                # 用户明确指定了协议，直接添加到列表
                PORTS_AND_PROTOS+=("$port/$proto_specified")
            else
                # ----------------------------------------------
                # 核心改动：未指定协议时弹出子菜单
                # ----------------------------------------------
                echo -e "\n${YELLOW}检测到端口 $port 未指定协议。请选择操作类型:${NC}"
                echo -e "  ${GREEN}1. 仅 TCP${NC}"
                echo -e "  ${GREEN}2. 仅 UDP${NC}"
                echo -e "  ${GREEN}3. TCP 和 UDP (同时)${NC}"
                read -p "请选择协议类型 [1-3]: " protocol_choice

                case "$protocol_choice" in
                    1) PORTS_AND_PROTOS+=("$port/tcp") ;;
                    2) PORTS_AND_PROTOS+=("$port/udp") ;;
                    3) PORTS_AND_PROTOS+=("$port/tcp" "$port/udp") ;;
                    *) 
                        echo -e "${RED}无效选择，跳过端口 $port。${NC}" 
                        continue 
                        ;;
                esac
                echo -e "${YELLOW}端口 $port 处理完成，继续下一个...${NC}"
                # ----------------------------------------------
            fi
        else
            echo -e "${RED} - 端口/协议 '$item' 格式无效，跳过。请使用 PORT 或 PORT/PROTO 格式。${NC}"
            continue
        fi
    done
    
    if [ ${#PORTS_AND_PROTOS[@]} -eq 0 ]; then
        echo -e "${RED}没有有效的端口可以操作。${NC}"
        return 1
    fi

    echo -e "${BLUE}开始批量${action_zh}以下端口/协议: ${PORTS_AND_PROTOS[*]}${NC}"

    # 应用规则
    for port_proto in "${PORTS_AND_PROTOS[@]}"; do
        # port_proto 现在是 "PORT/PROTO" 格式
        echo -n " - 尝试${action_zh} $port_proto..."
        
        local port=$(echo $port_proto | awk -F'/' '{print $1}')
        local proto=$(echo $port_proto | awk -F'/' '{print $2}')

        if [ "$FIREWALL_CMD" == "ufw" ]; then
            if [ "$operation" == "open" ]; then
                $su ufw allow "$port/$proto" >/dev/null 2>&1
            else
                # UFW remove rule
                $su ufw delete allow "$port/$proto" 2>/dev/null
                if [ $? -ne 0 ]; then
                    echo -e "\n${YELLOW}UFW 规则 $port_proto 不存在，跳过删除。${NC}"
                fi
            fi
        elif [ "$FIREWALL_CMD" == "firewall-cmd" ]; then
            if [ "$operation" == "open" ]; then
                $su firewall-cmd --zone=public --add-port="$port_proto" --permanent >/dev/null 2>&1
            else
                $su firewall-cmd --zone=public --remove-port="$port_proto" --permanent >/dev/null 2>&1
                if [ $? -ne 0 ]; then
                    echo -e "\n${YELLOW}Firewalld 规则 $port_proto 不存在，跳过删除。${NC}"
                fi
            fi
        fi
        echo -e "${GREEN}完成${NC}"
    done
    
    # 重载和显示状态
    if [ "$FIREWALL_CMD" == "firewall-cmd" ]; then
        $su firewall-cmd --reload
        echo -e "${GREEN}Firewalld 配置已重载。${NC}"
        $su firewall-cmd --list-all --no-pager
    elif [ "$FIREWALL_CMD" == "ufw" ]; then
        $su ufw reload
        echo -e "${GREEN}UFW 配置已重载。${NC}"
        $su ufw status numbered
    fi
}


fire_set() {
    echo -e "${BLUE}防火墙端口设置 (支持批量/协议自动选择，空格或逗号分隔)${NC}"
    echo -e "${GREEN}1. 开放端口 (allow)${NC}"
    echo -e "${GREEN}2. 关闭端口 (deny/remove)${NC}"
    read -p "请选择操作 [1-2]: " port2

    if [ "$port2" = "1" ]; then
        fire_batch_operation "open"
    elif [ "$port2" = "2" ]; then
        fire_batch_operation "close"
    else
        echo -e "${RED}无效选择，请输入 1 或 2。${NC}"
        return 1
    fi
}
# ============================================


# 函数：安装 Fail2ban
F2b_install() {
    read -p "请输入 SSH 端口号: " fshp
    read -p "请输入 IP 封禁时间（单位秒，-1 为永久封禁）: " time1
    echo -e "${BLUE}选择 Fail2ban 封禁方式${NC}"
    echo -e "${GREEN}1. iptables-allports${NC}"
    echo -e "${GREEN}2. iptables-multiport${NC}"
    echo -e "${GREEN}3. firewallcmd-ipset${NC}"
    echo -e "${GREEN}4. ufw${NC}"
    read -p "请选择封禁方式 [1-4]: " manner1
    case "$manner1" in
        1) manner="iptables-allports" ;;
        2) manner="iptables-multiport" ;;
        3) manner="firewallcmd-ipset" ;;
        4) manner="ufw" ;;
        *) echo -e "${RED}无效选择，请输入 1-4。${NC}"; exit 1 ;;
    esac
    echo -e "${GREEN}您选择的封禁方式是：$manner${NC}"
    if [[ $EUID -ne 0 ]]; then
        su='sudo'
    fi
    if command -v apt >/dev/null 2>&1; then
        $su apt update
        $su apt-get install fail2ban rsyslog -y
    else
        $su yum update -y
        $su yum install -y epel-release fail2ban
    fi
    $su mkdir -p /etc/fail2ban
    $su rm -f /etc/fail2ban/jail.local
    $su tee /etc/fail2ban/jail.local > /dev/null << EOF
[DEFAULT]
bantime = 600
findtime = 300
maxretry = 5
banaction = $manner
action = %(action_mwl)s

[sshd]
ignoreip = 127.0.0.1/8 ::1
enabled = true
filter = sshd
port = $fshp
maxretry = 5
findtime = 300
bantime = $time1
banaction = $manner
action = %(action_mwl)s
logpath = %(sshd_log)s
EOF
    $su systemctl restart fail2ban 2>/dev/null || true
    $su systemctl enable fail2ban 2>/dev/null || true
    $su systemctl start fail2ban 2>/dev/null || true
    echo -e "${GREEN}Fail2ban 已安装，配置文件位于 /etc/fail2ban/jail.local${NC}"
    $su systemctl status fail2ban --no-pager -l | head -20
}

# 函数：修改 root 密码 (修复：使用 read 明文显示输入)
root_pwd() {
    echo -e "${BLUE}选择 root 密码设置方式${NC}"
    echo -e "${GREEN}1. 生成随机密码${NC}"
    echo -e "${GREEN}2. 输入自定义密码${NC}"
    read -p "请输入选择 [1-2]: " pwd_choice
    if [[ $EUID -ne 0 ]]; then
        su='sudo'
    fi
    if [ "$pwd_choice" = "1" ]; then
        mima=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9!@#$%^&*()' | head -c16)
        echo -e "${GREEN}生成的随机密码为：$mima${NC}"
    elif [ "$pwd_choice" = "2" ]; then
        # 核心修改：使用 read -p 明文显示密码输入
        read -p "请输入自定义 root 密码: " mima
        read -p "请再次输入密码确认: " mima2
        
        [[ "$mima" == "$mima2" ]] || { echo -e "${RED}两次输入不一致！${NC}"; exit 1; }
    else
        echo -e "${RED}无效选择，请输入 1 或 2。${NC}"
        exit 1
    fi
    if [ -z "$mima" ]; then
        echo -e "${RED}密码不能为空！${NC}"
        exit 1
    fi

    echo "root:$mima" | $su chpasswd

    # 确保 root 可登录
    $su sed -i 's/^PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
    $su grep -q '^PermitRootLogin' /etc/ssh/sshd_config || $su sh -c "echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config"
    $su sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    $su grep -q '^PasswordAuthentication' /etc/ssh/sshd_config || $su sh -c "echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"

    if restart_ssh_service; then
        echo -e "${GREEN}root 密码已设置并启用密码登录。${NC}"
        echo -e "${GREEN}当前 root 密码：$mima${NC}"
    else
        echo -e "${RED}SSH 服务重启失败，但密码已修改。${NC}"
    fi
}

# 函数：管理 Swap
set_swap() {
    echo -e "${BLUE}Swap 管理选项${NC}"
    echo -e "${GREEN}1. 创建或修改 Swap${NC}"
    echo -e "${GREEN}2. 删除 Swap${NC}"
    read -p "请选择操作 [1-2]: " swap_choice
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}请以 root 权限运行此脚本。${NC}"
        exit 1
    fi

    DEFAULT_SWAP_FILE="/swapfile"

    create_swapfile() {
        SWAP_SIZE_GB=2
        SWAP_PRIORITY=0
        read -p "请输入 Swap 大小（单位 GB，默认 2）: " input_size
        [[ "$input_size" =~ ^[0-9]+$ ]] && SWAP_SIZE_GB=$input_size
        read -p "请输入 Swap 文件路径（默认 $DEFAULT_SWAP_FILE，回车使用默认）: " input_file
        SWAP_FILE=${input_file:-$DEFAULT_SWAP_FILE}
        read -p "请输入 Swap 利用优先级（默认 0）: " input_priority
        [[ "$input_priority" =~ ^[0-9]+$ ]] && SWAP_PRIORITY=$input_priority
        read -p "是否设置 Swap 开机自启动？[y/n，默认 y]: " input_autostart
        [[ "$input_autostart" =~ ^[nN]$ ]] && ENABLE_AUTOSTART=false || ENABLE_AUTOSTART=true

        SWAP_DIR=$(dirname "$SWAP_FILE")
        [ ! -d "$SWAP_DIR" ] && mkdir -p "$SWAP_DIR"

        if swapon --show | grep -q "$SWAP_FILE"; then
            echo -e "${YELLOW}调整现有 Swap 大小为 ${SWAP_SIZE_GB}GB...${NC}"
            swapoff "$SWAP_FILE"
        else
            echo -e "${GREEN}创建 ${SWAP_SIZE_GB}GB Swap 文件：$SWAP_FILE${NC}"
        fi

        fallocate -l ${SWAP_SIZE_GB}G "$SWAP_FILE" 2>/dev/null || dd if=/dev/zero of="$SWAP_FILE" bs=1G count=$SWAP_SIZE_GB oflag=append conv=notrunc
        chmod 600 "$SWAP_FILE"
        mkswap "$SWAP_FILE"
        swapon --priority $SWAP_PRIORITY "$SWAP_FILE"

        if [ "$ENABLE_AUTOSTART" = true ]; then
            if ! grep -q "^$SWAP_FILE " /etc/fstab; then
                echo "$SWAP_FILE none swap sw,pri=$SWAP_PRIORITY 0 0" >> /etc/fstab
            fi
        fi
        echo -e "${GREEN}Swap 操作完成。${NC}"
        free -h
        swapon --show
    }

    delete_swap() {
        echo -e "${YELLOW}当前 Swap 状态：${NC}"
        swapon --show
        read -p "请输入要删除的 Swap 路径（默认 $DEFAULT_SWAP_FILE）: " input_path
        SWAP_PATH=${input_path:-$DEFAULT_SWAP_FILE}
        if swapon --show | grep -q "$SWAP_PATH"; then
            swapoff "$SWAP_PATH"
            [ -f "$SWAP_PATH" ] && rm -f "$SWAP_PATH"
            sed -i "\|^$SWAP_PATH |d" /etc/fstab
            echo -e "${GREEN}Swap $SWAP_PATH 已删除。${NC}"
        else
            echo -e "${YELLOW}未找到活跃 Swap，清理残留...${NC}"
            sed -i "\|^$SWAP_PATH |d" /etc/fstab
            [ -f "$SWAP_PATH" ] && rm -f "$SWAP_PATH"
        fi
        free -h
        swapon --show
    }

    if [ "$swap_choice" = "1" ]; then
        create_swapfile
    elif [ "$swap_choice" = "2" ]; then
        delete_swap
    else
        echo -e "${RED}无效选择。${NC}"
        exit 1
    fi
}


# ============================================
# 新功能：注册 RHEL 系统 (修复：使用 read 明文显示输入)
# ============================================
register_rhel_system() {
    echo -e "${BLUE}===== RHEL 系统注册 =====${NC}"

    if [[ ! -f /etc/redhat-release ]]; then
        echo -e "${RED}此系统不是 RHEL/CentOS/Alma/Rocky，无法使用红帽注册功能。${NC}"
        return 1
    fi

    echo -e "${GREEN}检测到 RHEL 系列系统，准备执行系统注册...${NC}"
    
    read -p "请输入 RedHat 用户名（例如 kevin-x-du）: " RHEL_USER
    # 核心修改：使用 read -p 明文显示密码输入
    read -p "请输入 RedHat 密码: " RHEL_PASS

    if [[ -z "$RHEL_USER" || -z "$RHEL_PASS" ]]; then
        echo -e "${RED}用户名或密码不能为空。${NC}"
        return 1
    fi

    # 使用 subscription-manager 注册（旧式 RHEL）
    if command -v subscription-manager >/dev/null 2>&1; then
        echo -e "${GREEN}使用 subscription-manager 注册系统...${NC}"
        sudo subscription-manager register --username "${RHEL_USER}" --password "${RHEL_PASS}"
        return
    fi

    # 使用 rhc connect（RHEL 8.5+ 推荐方式）
    if command -v rhc >/dev/null 2>&1; then
        echo -e "${GREEN}使用 rhc connect 注册系统...${NC}"
        sudo rhc connect -u "${RHEL_USER}" -p "${RHEL_PASS}"
        return
    fi

    echo -e "${RED}未找到 subscription-manager 或 rhc，无法注册系统。${NC}"
}

# 第 10 项：自动配置 IPv6（智能识别 + 任意前缀支持）
ipv6_auto_config() {

    echo -e "${BLUE}=============================="
    echo -e "      自动配置 IPv6（强化识别）"
    echo -e "==============================${NC}"

    # 暂时关闭 set -e，避免 grep 没匹配导致整个脚本退出
    set +e

    # 1. 自动识别网卡
    INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n 1)
    if [[ -z "$INTERFACE" ]]; then
        echo -e "${RED}❌ 未找到网卡${NC}"
        set -e
        return 1
    fi 
    echo -e "${GREEN}✔ 检测到网卡：$INTERFACE${NC}"

    IPV4=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+/\d+' || true)
    GATEWAY4=$(ip route | awk '/default/ {print $3}' || true)

    echo -e "${GREEN}✔ IPv4：$IPV4${NC}"
    echo -e "${GREEN}✔ IPv4 网关：$GATEWAY4${NC}"

    # 2. 从 /etc/network/interfaces.d 读取 IPv6（只看当前网卡）
    AUTO_WAN_IPV6=""
    AUTO_GATEWAY6=""

    for FILE in /etc/network/interfaces.d/*; do
        [[ ! -f "$FILE" ]] && continue
        if grep -q "iface $INTERFACE inet6" "$FILE" 2>/dev/null; then
            echo -e "${YELLOW}📄 读取 IPv6 配置文件：$FILE${NC}"

            FILE_WAN_126=$(grep -oP "address\s+\K([0-9a-fA-F:]+/126)" "$FILE" 2>/dev/null || true)
            FILE_WAN_ANY=$(grep -oP "address\s+\K([0-9a-fA-F:]+/\d+)" "$FILE" 2>/dev/null || true)

            [[ -n "$FILE_WAN_126" ]] && AUTO_WAN_IPV6="$FILE_WAN_126"
            [[ -n "$FILE_WAN_ANY" && -z "$AUTO_WAN_IPV6" ]] && AUTO_WAN_IPV6="$FILE_WAN_ANY"

            FILE_GATEWAY=$(grep -oP "gateway\s+\K([0-9a-fA-F:]+:[0-9a-fA-F:]+)" "$FILE" 2>/dev/null || true)
            [[ -n "$FILE_GATEWAY" ]] && AUTO_GATEWAY6="$FILE_GATEWAY"
        fi
    done

    echo -e "${YELLOW}📌 IPv6 配置自动检测结果：${NC}"
    echo -e "   WAN IPv6：${AUTO_WAN_IPV6:-未找到}"
    echo -e "   Gateway6：${AUTO_GATEWAY6:-未找到}"

    # 3. 尝试从当前系统路由中再兜底一次
    [[ -z "$AUTO_WAN_IPV6" ]] && AUTO_WAN_IPV6=$(ip -6 addr show $INTERFACE | grep "/126" | awk '{print $2}' | head -n1 || true)
    [[ -z "$AUTO_GATEWAY6" ]] && AUTO_GATEWAY6=$(ip -6 route | awk '/default via/ {print $3}' | head -n1 || true)

    # 4. 如果还是没有，就使用固定默认 WAN IPv6
    DEFAULT_WAN_IPV6="2a0a:8dc0:0:bb::2/126"
    DEFAULT_GATEWAY6="2a0a:8dc0:0:bb::1"

    WAN_IPV6="${AUTO_WAN_IPV6:-$DEFAULT_WAN_IPV6}"
    WAN_GATEWAY="${AUTO_GATEWAY6:-$DEFAULT_GATEWAY6}"

    echo -e "${GREEN}✔ 最终使用 WAN IPv6：$WAN_IPV6${NC}"
    echo -e "${GREEN}✔ 最终使用 IPv6 网关：$WAN_GATEWAY${NC}"

    # 5. 让你输入任意前缀的自定义 IPv6
    echo -e "${GREEN}请输入要添加的自定义 IPv6，例如：${NC}"
    echo -e "   2a0a:8dc0:bc::10"
    echo -e "   2a0a:8dc0:bc::10/64"
    echo -e "   2a0a:8dc0:bc::10/128"
    read -p "IPv6: " USER_IPV6

    if [[ "$USER_IPV6" =~ "/" ]]; then
        FINAL_USER_IPV6="$USER_IPV6"
    else
        DEFAULT_PREFIX=48
        FINAL_USER_IPV6="$USER_IPV6/$DEFAULT_PREFIX"
    fi
    USER_IPV6="$FINAL_USER_IPV6"

    echo -e "${GREEN}✔ 使用自定义 IPv6：$USER_IPV6${NC}"
    echo -e "${YELLOW}按回车写入配置，Ctrl+C 取消...${NC}"
    read

    # 6. 写入 /etc/network/interfaces
    CFG="/etc/network/interfaces"
    cp $CFG ${CFG}.bak-$(date +%s)

cat > $CFG << EOF
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

allow-hotplug $INTERFACE
iface $INTERFACE inet static
    address $IPV4
    gateway $GATEWAY4
    dns-nameservers 1.1.1.1 8.8.8.8

iface $INTERFACE inet6 static
    address $WAN_IPV6
    gateway $WAN_GATEWAY
    dns-nameserver 2606:4700:4700::1111
    dns-nameserver 2001:4860:4860::8888

    post-up ip -6 addr add $USER_IPV6 dev $INTERFACE
    pre-down ip -6 addr del $USER_IPV6 dev $INTERFACE
EOF

    echo -e "${GREEN}✔ IPv6 配置已写入 ${CFG}${NC}"

    ip addr flush dev $INTERFACE
    systemctl restart networking

    echo -e "${GREEN}=== 当前 IPv6 地址 ===${NC}"
    ip -6 addr show dev $INTERFACE

    # 恢复 set -e
    set -e
}

# 主循环
while true; do
    display_menu

    case "$mu" in
        1) root_pwd ;;
        2) ssh_port ;;
        3) ssh_key ;;
        4) user_ssh_key ;;
        5) fire_install ;;
        6) fire_set ;;
        7) F2b_install ;;
        8) set_swap ;;
        9) register_rhel_system ;;
        10) ipv6_auto_config ;;
        11) echo -e "${GREEN}退出脚本${NC}"; exit 0 ;;
        *) echo -e "${RED}无效选择${NC}" ;;
    esac

    # 任意键返回菜单
    echo
    read -n 1 -s -r -p "按任意键返回菜单..."
    echo
done