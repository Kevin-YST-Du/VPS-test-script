#!/bin/bash

# ---------------------------------------------------------
# Linux 服务器管理脚本（增强版 v2.0）
# 优化重点：
# - 深度修复 Root 登录权限（解决 permitrootlogin without-password 问题）
# - 智能处理 sshd_config.d 覆盖文件
# - 保持原有的日志、防火墙、安全确认系统
# ---------------------------------------------------------

# =========================================================
# 日志系统
# =========================================================
LOG_FILE="/root/root.log"

log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$LOG_FILE"
}

log "脚本启动..."

# =========================================================
#  安全确认系统
# =========================================================
confirm_action() {
    echo
    read -p "⚠️  此操作具有风险，是否继续？[y/N]： " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "操作已取消。"
        log "用户取消了敏感操作"
        return 1
    fi
    return 0
}

# =========================================================
#  ANSI 颜色代码
# =========================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =========================================================
#  主菜单显示函数
# =========================================================
display_menu() {
    clear
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${YELLOW}       服务器系统管理工具 (Pro)       ${NC}"
    echo -e "${BLUE}=====================================${NC}"

    echo -e "${GREEN}1. 修改 root 用户密码 (优化版 - 强制开启登录)${NC}"
    echo -e "${GREEN}2. 修改 SSH 端口号${NC}"
    echo -e "${GREEN}3. 配置 root SSH 密钥认证${NC}"
    echo -e "${GREEN}4. 配置普通用户 SSH 密钥认证${NC}"
    echo -e "${GREEN}5. 安装防火墙（UFW 或 Firewalld 自动识别）${NC}"
    echo -e "${GREEN}6. 配置防火墙端口（单个/批量 + FROM + 自动协议）${NC}"
    echo -e "${GREEN}7. 安装 Fail2ban${NC}"
    echo -e "${GREEN}8. 管理 Swap${NC}"
    echo -e "${GREEN}9. 注册 RHEL 系统${NC}"
    echo -e "${GREEN}10. 重启所有网卡连接（自动识别系统）${NC}"
    echo -e "${GREEN}11. 退出${NC}"

    echo -e "${BLUE}=====================================${NC}"
    echo -e "${GREEN}日志文件位置：${NC} ${YELLOW}/root/root.log${NC}"
    echo -e "${BLUE}=====================================${NC}"
    read -p "请选择功能 [1-11]: " mu
}

# =========================================================
#  SSH 服务重启函数（自动识别系统）
# =========================================================
restart_ssh_service() {
    log "尝试重启 SSH 服务"
    if command -v systemctl >/dev/null 2>&1; then
        echo -e "${GREEN}使用 systemctl 重启 SSH 服务…${NC}"
        sudo systemctl restart sshd 2>/dev/null || sudo systemctl restart ssh 2>/dev/null
        return 0

    elif command -v service >/dev/null 2>&1; then
        echo -e "${GREEN}使用 service 重启 SSH 服务…${NC}"
        sudo service ssh restart 2>/dev/null || sudo service sshd restart 2>/dev/null
        return 0

    elif [ -x /etc/init.d/ssh ]; then
        echo -e "${GREEN}使用 /etc/init.d/ssh 重启 SSH 服务…${NC}"
        sudo /etc/init.d/ssh restart 2>/dev/null
        return 0

    elif command -v initctl >/dev/null 2>&1; then
        echo -e "${GREEN}使用 initctl 重启 SSH 服务…${NC}"
        sudo initctl restart ssh 2>/dev/null
        return 0

    else
        echo -e "${RED}无法识别 SSH 服务管理方式，请手动重启 SSH。${NC}"
        log "SSH 重启失败，无法识别服务管理方式"
        return 1
    fi
}

# =========================================================
#  智能重启所有网卡连接
# =========================================================
restart_all_interfaces() {
    log "执行网卡重启功能"
    echo -e "${BLUE}==============================${NC}"
    echo -e "${YELLOW}        智能重启所有网卡        ${NC}"
    echo -e "${BLUE}==============================${NC}"

    if command -v netplan >/dev/null 2>&1; then
        echo -e "${GREEN}✔ 检测到 Ubuntu / Netplan${NC}"
        confirm_action || return 1

        sudo netplan apply
        echo -e "${GREEN}Netplan 配置已应用${NC}"
        log "Netplan applied"

    elif command -v systemctl >/dev/null 2>&1 && systemctl status networking >/dev/null 2>&1; then
        echo -e "${GREEN}✔ 检测到 Debian / ifupdown${NC}"
        confirm_action || return 1

        sudo systemctl restart networking
        echo -e "${GREEN}Networking 服务已重启${NC}"
        log "systemctl restarted networking"

    elif command -v nmcli >/dev/null 2>&1; then
        echo -e "${GREEN}✔ 检测到 NetworkManager 系统${NC}"
        confirm_action || return 1

        DEVICES=$(nmcli -t -f DEVICE,TYPE device status | grep -E 'ethernet|wifi' | awk -F: '{print $1}')

        for DEV in $DEVICES; do
            echo "重启接口 $DEV …"
            sudo nmcli dev disconnect "$DEV" 2>/dev/null || true
            sudo nmcli dev connect "$DEV"
        done
        log "NetworkManager 接口均已重启"

    else
        echo -e "${RED}❌ 无法检测网络管理方式${NC}"
        log "无法识别网络管理方式"
    fi

    echo -e "${YELLOW}当前网络接口信息：${NC}"
    ip addr
    echo -e "${BLUE}==============================${NC}"
}

# =========================================================
# 1. 修改 root 密码 (深度优化版)
# =========================================================
root_pwd() {
    echo -e "${BLUE}===== 设置 root 密码并强制开启登录 =====${NC}"

    confirm_action || return 1
    su=''
    [[ $EUID -ne 0 ]] && su='sudo'

    # --- 1. 密码设置逻辑 ---
    echo -e "${GREEN}1. 生成随机密码${NC}"
    echo -e "${GREEN}2. 输入自定义密码${NC}"
    read -p "请选择 [1-2]: " pwd_choice

    if [[ "$pwd_choice" = "1" ]]; then
        mima=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9!@#$%^&*()' | head -c16)
        echo -e "${GREEN}随机密码已生成：${mima}${NC}"
        log "生成随机 root 密码"

    elif [[ "$pwd_choice" = "2" ]]; then
        read -p "请输入新密码: " mima
        read -p "再次确认密码: " mima2

        [[ "$mima" != "$mima2" ]] && { echo -e "${RED}两次密码不一致！${NC}"; return 1; }
        log "用户设置自定义 root 密码"

    else
        echo -e "${RED}无效选择${NC}"
        return 1
    fi

    echo "root:$mima" | $su chpasswd
    log "root 密码已修改"

    # --- 2. 深度 SSH 配置修复逻辑 ---
    echo -e "${YELLOW}正在深度检查 SSH 配置...${NC}"

    local ssh_config="/etc/ssh/sshd_config"
    local ssh_config_d="/etc/ssh/sshd_config.d"

    # 内部函数：修改或追加配置
    # 参数 1: 文件路径
    # 参数 2: 配置项名称
    # 参数 3: 目标值
    update_ssh_param() {
        local file="$1"
        local param="$2"
        local value="$3"
        
        if [[ -f "$file" ]]; then
            # 使用 grep 检查是否存在该配置项（无论是否被注释）
            if grep -qE "^#?${param}" "$file"; then
                # 替换：处理被注释(#)的情况，也处理已有值的情况
                $su sed -i -E "s/^#?${param}.*/${param} ${value}/" "$file"
            else
                # 如果不存在，追加到文件末尾
                echo "${param} ${value}" | $su tee -a "$file" >/dev/null
            fi
        fi
    }

    # A. 修复主配置文件
    update_ssh_param "$ssh_config" "PermitRootLogin" "yes"
    update_ssh_param "$ssh_config" "PasswordAuthentication" "yes"

    # B. 扫描并修复 include 目录下的覆盖文件 (关键步骤)
    # 很多云厂商会在 50-cloud-init.conf 里强制禁止 root 登录
    if [[ -d "$ssh_config_d" ]]; then
        # 查找所有包含 PermitRootLogin 的 .conf 文件
        grep -l "PermitRootLogin" "$ssh_config_d"/*.conf 2>/dev/null | while read -r conf_file; do
            echo -e "${YELLOW}发现覆盖配置，正在修正：${conf_file}${NC}"
            $su sed -i -E "s/^#?PermitRootLogin.*/PermitRootLogin yes/" "$conf_file"
        done

        # 查找所有包含 PasswordAuthentication 的 .conf 文件
        grep -l "PasswordAuthentication" "$ssh_config_d"/*.conf 2>/dev/null | while read -r conf_file; do
             echo -e "${YELLOW}发现覆盖配置，正在修正：${conf_file}${NC}"
            $su sed -i -E "s/^#?PasswordAuthentication.*/PasswordAuthentication yes/" "$conf_file"
        done
    fi

    restart_ssh_service
    
    echo -e "${GREEN}root 密码已更新：${mima}${NC}"
    
    # --- 3. 最终生效验证 ---
    echo -e "${BLUE}===== SSH 最终生效策略验证 =====${NC}"
    echo "正在运行 sshd -T 检查最终加载的配置..."
    # 检查 sshd 是否存在
    if command -v sshd >/dev/null 2>&1; then
        # 使用 sshd -T 获取实际生效的配置
        local effective_config
        effective_config=$($su sshd -T 2>/dev/null | grep -E "^(permitrootlogin|passwordauthentication)")
        
        echo -e "${YELLOW}${effective_config}${NC}"
        
        if echo "$effective_config" | grep -q "permitrootlogin yes"; then
             echo -e "${GREEN}✅ 检测通过：Root 登录已开启 (permitrootlogin yes)${NC}"
        else
             echo -e "${RED}❌ 警告：Root 登录似乎仍未开启，请检查是否有只读文件或特殊限制！${NC}"
        fi
    else
        echo -e "${YELLOW}未找到 sshd 命令，跳过验证。${NC}"
    fi
}

# =========================================================
# 2. 修改 SSH 端口
# =========================================================
ssh_port() {
    echo -e "${BLUE}===== 修改 SSH 端口 =====${NC}"
    confirm_action || return 1

    read -p "请输入新的 SSH 端口号： " por

    if ! [[ "$por" =~ ^[0-9]+$ ]] || [[ "$por" -lt 1 || "$por" -gt 65535 ]]; then
        echo -e "${RED}端口号必须是 1-65535 数字${NC}"
        return 1
    fi

    su=''
    [[ $EUID -ne 0 ]] && su='sudo'

    $su cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    # 修改端口，同样使用 -E 增强兼容性
    $su sed -i -E "s/^#?Port .*/Port $por/" /etc/ssh/sshd_config
    
    # 确保没有其他 Port 行干扰（删除除第一行外的其他 Port 配置? 比较复杂，这里简单处理）
    # 如果原文件没有 Port 配置，追加
    if ! grep -q "^Port" /etc/ssh/sshd_config; then
         echo "Port $por" | $su tee -a /etc/ssh/sshd_config >/dev/null
    fi

    log "SSH 端口修改为 $por"
    restart_ssh_service

    echo -e "${GREEN}SSH 端口已修改为：$por${NC}"
}

# =========================================================
# 3. 配置 root SSH 公钥认证
# =========================================================
ssh_key() {
    echo -e "${BLUE}===== 配置 root SSH 公钥 =====${NC}"
    confirm_action || return 1

    [[ $EUID -ne 0 ]] && { echo -e "${RED}必须以 root 身份运行！${NC}"; return 1; }

    read -p "请输入 root 公钥内容： " ssh_key
    [[ -z "$ssh_key" ]] && { echo -e "${RED}公钥不能为空${NC}"; return 1; }

    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    # 公钥认证开启
    sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^PubkeyAuthentication no/PubkeyAuthentication yes/' /etc/ssh/sshd_config

    # 选择是否保留密码登录
    read -p "是否保留密码登录？[y/N]：" enable_password
    if [[ "$enable_password" =~ ^[Yy]$ ]]; then
        sed -i -E 's/^#?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
        sed -i -E 's/^#?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
        MSG="root 支持密码 + 密钥登录"
    else
        sed -i -E 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
        sed -i -E 's/^#?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
        MSG="root 仅支持密钥登录"
    fi

    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo "$ssh_key" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    log "root SSH 公钥已配置（保留密码：$enable_password）"

    restart_ssh_service
    echo -e "${GREEN}${MSG}${NC}"
}

# =========================================================
# 4. 配置普通用户 SSH 公钥认证
# =========================================================
user_ssh_key() {
    current_user=$(whoami)

    echo -e "${BLUE}===== 配置普通用户 SSH 公钥 =====${NC}"
    confirm_action || return 1

    read -p "请输入 $current_user 的 SSH 公钥： " ssh_key
    [[ -z "$ssh_key" ]] && { echo -e "${RED}公钥不能为空${NC}"; return 1; }

    read -p "是否保留密码登录？[y/N]：" enable_password

    su=''
    [[ $EUID -ne 0 ]] && su='sudo'

    $su cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    # 启用公钥认证
    $su sed -i -E 's/^#?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

    if [[ "$enable_password" =~ ^[Yy]$ ]]; then
        $su sed -i -E 's/^#?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
        MSG="$current_user 支持密码 + 密钥登录"
    else
        $su sed -i -E 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
        MSG="$current_user 仅支持密钥登录"
    fi

    $su mkdir -p /home/$current_user/.ssh
    echo "$ssh_key" | $su tee -a /home/$current_user/.ssh/authorized_keys >/dev/null
    $su chmod 700 /home/$current_user/.ssh
    $su chmod 600 /home/$current_user/.ssh/authorized_keys
    $su chown $current_user:$current_user /home/$current_user/.ssh -R

    log "用户 $current_user 公钥已配置"

    restart_ssh_service
    echo -e "${GREEN}${MSG}${NC}"
}

# =========================================================
# 5. 自动识别并安装防火墙
# =========================================================
fire_install() {
    echo -e "${BLUE}===== 安装防火墙 =====${NC}"
    confirm_action || return 1

    su=''
    [[ $EUID -ne 0 ]] && su='sudo'

    if command -v apt >/dev/null 2>&1; then
        echo -e "${GREEN}检测到 Debian/Ubuntu 系统，将安装 UFW${NC}"
        log "选择安装 UFW"

        $su apt update
        $su apt install ufw -y
        $su ufw --force enable

        echo -e "${GREEN}UFW 安装完成并已启用${NC}"

    elif command -v yum >/dev/null 2>&1; then
        echo -e "${GREEN}检测到 RHEL/CentOS，将安装 firewalld${NC}"
        log "选择安装 Firewalld"

        $su yum install -y firewalld
        $su systemctl enable firewalld
        $su systemctl start firewalld

        echo -e "${GREEN}Firewalld 安装完成并已启动${NC}"

    else
        echo -e "${RED}无法识别系统类型，无法自动安装防火墙${NC}"
        log "防火墙安装失败：系统类型未知"
        return 1
    fi
}

# =========================================================
# 6. 批量或单个方式选择
# =========================================================
choose_port_mode() {
    echo -e "${BLUE}请选择端口输入方式${NC}"
    echo -e "${GREEN}1. 单个端口模式${NC}"
    echo -e "${GREEN}2. 批量端口模式（空格或逗号分隔）${NC}"
    read -p "请选择 [1-2]: " mode

    case "$mode" in
        1)
            read -p "请输入端口号（如 80 或 443/tcp）： " PORT_INPUT
            ;;
        2)
            read -p "请输入多个端口号（空格/逗号分隔）： " PORT_INPUT
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return 1
            ;;
    esac
}

# =========================================================
# 解析端口：自动判断协议与格式
# =========================================================
parse_ports() {
    local raw_list="$1"
    local cleaned=$(echo "$raw_list" | tr ',' ' ' | tr -s ' ')

    PORTS_AND_PROTOS=()

    for item in $cleaned; do
        if [[ "$item" =~ ^([0-9]+)(/(tcp|udp))?$ ]]; then
            port=${BASH_REMATCH[1]}
            proto=${BASH_REMATCH[3]}

            if [[ -n "$proto" ]]; then
                PORTS_AND_PROTOS+=("${port}/${proto}")
            else
                echo -e "${YELLOW}端口 $port 未指定协议，请选择：${NC}"
                echo -e "  ${GREEN}1. TCP${NC}"
                echo -e "  ${GREEN}2. UDP${NC}"
                echo -e "  ${GREEN}3. TCP + UDP${NC}"
                read -p "请选择协议 [1-3]: " opt

                case "$opt" in
                    1) PORTS_AND_PROTOS+=("${port}/tcp") ;;
                    2) PORTS_AND_PROTOS+=("${port}/udp") ;;
                    3) PORTS_AND_PROTOS+=("${port}/tcp" "${port}/udp") ;;
                    *) echo -e "${RED}无效选择，跳过 ${port}${NC}" ;;
                esac
            fi

        else
            echo -e "${RED}格式无效：$item，已跳过${NC}"
        fi
    done
}

# =========================================================
# FROM 来源 IP 选择
# =========================================================
choose_from_source() {
    echo
    read -p "是否设置来源 IP (FROM)？[y/N]：" enable_from

    if [[ "$enable_from" =~ ^[Yy]$ ]]; then
        read -p "请输入来源 IP 或网段 (如 192.168.1.0/24)： " FROM_IP
        [[ -z "$FROM_IP" ]] && FROM_IP="Anywhere"
    else
        FROM_IP="Anywhere"
    fi
}

# =========================================================
# 自动识别 UFW 或 Firewalld
# =========================================================
detect_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        FIREWALL_CMD="ufw"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        FIREWALL_CMD="firewalld"
    else
        FIREWALL_CMD=""
    fi
}

# =========================================================
# 批量操作（开放 / 关闭）
# =========================================================
fire_batch_operation() {
    local operation=$1
    local op_zh=$([[ "$operation" == "open" ]] && echo "开放" || echo "关闭")

    detect_firewall

    # 如果是关闭端口操作，并且系统使用 UFW，则先展示当前防火墙状态
    if [[ "$operation" == "close" && "$FIREWALL_CMD" == "ufw" ]]; then
        echo -e "${YELLOW}关闭端口前，当前 UFW 状态如下：${NC}"
        sudo ufw status
        echo
    fi

    [[ -z "$FIREWALL_CMD" ]] && { echo -e "${RED}未检测到已安装的防火墙！${NC}"; return 1; }

    choose_port_mode || return 1
    choose_from_source
    parse_ports "$PORT_INPUT"

    echo -e "${BLUE}开始 ${op_zh} 端口：${PORTS_AND_PROTOS[*]}，FROM=${FROM_IP}${NC}"
    confirm_action || return 1

    su=''
    [[ $EUID -ne 0 ]] && su='sudo'

    for pp in "${PORTS_AND_PROTOS[@]}"; do
        port=$(echo "$pp" | cut -d/ -f1)
        proto=$(echo "$pp" | cut -d/ -f2)

        echo -n "处理 $pp..."

        # =====================================================
        # firewalld
        # =====================================================
        if [[ "$FIREWALL_CMD" == "firewalld" ]]; then

            if [[ "$operation" == "open" ]]; then
                if [[ "$FROM_IP" == "Anywhere" ]]; then
                    $su firewall-cmd --permanent --add-port="${pp}" >/dev/null
                else
                    $su firewall-cmd --permanent \
                        --add-rich-rule="rule family='ipv4' source address='${FROM_IP}' port port='${port}' protocol='${proto}' accept"
                fi
            else
                $su firewall-cmd --permanent --remove-port="${pp}" >/dev/null 2>&1
            fi

        # =====================================================
        # UFW
        # =====================================================
        elif [[ "$FIREWALL_CMD" == "ufw" ]]; then

            if [[ "$operation" == "open" ]]; then
                if [[ "$FROM_IP" == "Anywhere" ]]; then
                    $su ufw allow "${pp}" >/dev/null
                else
                    $su ufw allow proto "${proto}" from "${FROM_IP}" to any port "${port}" >/dev/null
                fi
            else
                $su ufw delete allow "${pp}" >/dev/null 2>&1
            fi
        fi

        echo -e "${GREEN}完成${NC}"
        log "端口操作: $pp, FROM=$FROM_IP, op=$operation"
    done

    # reload firewall
    [[ "$FIREWALL_CMD" == "firewalld" ]] && $su firewall-cmd --reload
    [[ "$FIREWALL_CMD" == "ufw" ]] && $su ufw reload

    echo -e "${GREEN}防火墙规则已更新${NC}"

    if [[ "$FIREWALL_CMD" == "ufw" ]]; then
        echo -e "${YELLOW}当前 UFW 防火墙规则：${NC}"
        $su ufw status
    fi
}

# =========================================================
# 防火墙菜单入口
# =========================================================
fire_set() {
    echo -e "${BLUE}===== 防火墙端口设置 =====${NC}"
    echo -e "${GREEN}1. 开放端口${NC}"
    echo -e "${GREEN}2. 关闭端口${NC}"
    read -p "请选择 [1-2]：" choice

    case "$choice" in
        1) fire_batch_operation "open" ;;
        2) fire_batch_operation "close" ;;
        *) echo -e "${RED}无效选择${NC}" ;;
    esac
}

# =========================================================
# 7. Fail2ban 安装与配置
# =========================================================
F2b_install() {
    echo -e "${BLUE}===== 安装 Fail2ban =====${NC}"
    confirm_action || return 1
    su=''
    [[ $EUID -ne 0 ]] && su='sudo'

    read -p "请输入 SSH 端口号（默认 22）: " fshp
    [[ -z "$fshp" ]] && fshp=22

    read -p "请输入 IP 封禁时间 (秒，-1 为永久封禁): " ban_time
    [[ -z "$ban_time" ]] && ban_time=600

    echo -e "${BLUE}选择 Fail2ban 封禁方式：${NC}"
    echo -e "${GREEN}1. iptables-allports${NC}"
    echo -e "${GREEN}2. iptables-multiport${NC}"
    echo -e "${GREEN}3. firewallcmd-ipset${NC}"
    echo -e "${GREEN}4. ufw${NC}"
    read -p "请选择 [1-4]：" manner_opt

    case "$manner_opt" in
        1) manner="iptables-allports" ;;
        2) manner="iptables-multiport" ;;
        3) manner="firewallcmd-ipset" ;;
        4) manner="ufw" ;;
        *) echo -e "${RED}无效选择${NC}"; return 1 ;;
    esac

    log "安装 Fail2ban，封禁方式：$manner, ban_time=$ban_time, ssh_port=$fshp"

    if command -v apt >/dev/null 2>&1; then
        $su apt update
        $su apt install -y fail2ban rsyslog
    else
        $su yum install -y epel-release fail2ban
    fi

    $su mkdir -p /etc/fail2ban

    $su tee /etc/fail2ban/jail.local > /dev/null <<EOF
[DEFAULT]
bantime = $ban_time
findtime = 300
maxretry = 5
banaction = $manner
action = %(action_mwl)s

[sshd]
enabled = true
port = $fshp
logpath = %(sshd_log)s
EOF

    $su systemctl restart fail2ban
    $su systemctl enable fail2ban

    echo -e "${GREEN}Fail2ban 已启动${NC}"
    log "Fail2ban 已成功安装并运行"
}

# =========================================================
# 8. Swap 管理模块
# =========================================================
set_swap() {
    echo -e "${BLUE}===== Swap 管理 =====${NC}"

    echo -e "${GREEN}1. 创建或修改 Swap${NC}"
    echo -e "${GREEN}2. 删除 Swap${NC}"
    read -p "请选择操作 [1-2]: " swap_choice

    [[ $EUID -ne 0 ]] && { echo -e "${RED}请使用 root 权限运行${NC}"; return 1; }

    DEFAULT_SWAP_FILE="/swapfile"

    if [[ "$swap_choice" == "1" ]]; then
        confirm_action || return 1

        read -p "请输入 Swap 大小 (GB，默认 2)： " SWAP_SIZE
        [[ -z "$SWAP_SIZE" ]] && SWAP_SIZE=2

        read -p "Swap 文件路径（默认 $DEFAULT_SWAP_FILE）： " SWAP_FILE
        [[ -z "$SWAP_FILE" ]] && SWAP_FILE=$DEFAULT_SWAP_FILE

        read -p "优先级 (默认 0)： " SWAP_PRIORITY
        [[ -z "$SWAP_PRIORITY" ]] && SWAP_PRIORITY=0

        read -p "是否开机自动挂载？[Y/n]：" auto_mount
        [[ "$auto_mount" =~ ^[Nn]$ ]] && AUTO=false || AUTO=true

        log "创建/修改 Swap: size=${SWAP_SIZE}G, file=$SWAP_FILE, pri=$SWAP_PRIORITY"

        if swapon --show | grep -q "$SWAP_FILE"; then
            swapoff "$SWAP_FILE"
        fi

        fallocate -l "${SWAP_SIZE}G" "$SWAP_FILE" 2>/dev/null ||
            dd if=/dev/zero of="$SWAP_FILE" bs=1G count="${SWAP_SIZE}" oflag=append conv=notrunc

        chmod 600 "$SWAP_FILE"
        mkswap "$SWAP_FILE"
        swapon --priority "$SWAP_PRIORITY" "$SWAP_FILE"

        if $AUTO; then
            if ! grep -q "^$SWAP_FILE" /etc/fstab; then
                echo "$SWAP_FILE none swap sw,pri=$SWAP_PRIORITY 0 0" >> /etc/fstab
            fi
        else
            sed -i "\|$SWAP_FILE|d" /etc/fstab
        fi

        echo -e "${GREEN}Swap 已成功创建或修改${NC}"
        log "Swap 创建/修改成功"
        free -h
        swapon --show

    elif [[ "$swap_choice" == "2" ]]; then
        confirm_action || return 1

        read -p "请输入 Swap 路径（默认 $DEFAULT_SWAP_FILE）： " SWAP_PATH
        [[ -z "$SWAP_PATH" ]] && SWAP_PATH=$DEFAULT_SWAP_FILE

        if swapon --show | grep -q "$SWAP_PATH"; then
            swapoff "$SWAP_PATH"
        fi

        sed -i "\|$SWAP_PATH|d" /etc/fstab
        [[ -f "$SWAP_PATH" ]] && rm -f "$SWAP_PATH"

        echo -e "${GREEN}Swap 已删除${NC}"
        log "Swap 删除成功"
        free -h
        swapon --show
    else
        echo -e "${RED}无效选择${NC}"
    fi
}

# =========================================================
# 9. 注册 RHEL 系统
# =========================================================
register_rhel_system() {
    echo -e "${BLUE}===== RHEL 系统注册 =====${NC}"
    confirm_action || return 1

    if [[ ! -f /etc/redhat-release ]]; then
        echo -e "${RED}此系统不是 RHEL/CentOS 系列${NC}"
        return 1
    fi

    read -p "请输入 RedHat 用户名: " RHEL_USER
    read -p "请输入 RedHat 密码: " RHEL_PASS

    [[ -z "$RHEL_USER" || -z "$RHEL_PASS" ]] && { echo -e "${RED}不能为空${NC}"; return 1; }

    log "开始注册 RHEL 系统，用户：$RHEL_USER"

    if command -v subscription-manager >/dev/null 2>&1; then
        sudo subscription-manager register --username "$RHEL_USER" --password "$RHEL_PASS"
        echo -e "${GREEN}注册成功（subscription-manager）${NC}"
    elif command -v rhc >/dev/null 2>&1; then
        sudo rhc connect -u "$RHEL_USER" -p "$RHEL_PASS"
        echo -e "${GREEN}注册成功（rhc connect）${NC}"
    else
        echo -e "${RED}系统不支持 RHEL 注册工具${NC}"
        return 1
    fi

    log "RHEL 注册完成"
}

# =========================================================
# 主循环
# =========================================================
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
        10) restart_all_interfaces ;;
        11)
            echo -e "${GREEN}已退出脚本，再见！${NC}"
            log "用户退出脚本"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择，请输入 1-11${NC}"
            ;;
    esac

    echo
    read -n 1 -s -r -p "按任意键返回菜单…"
    echo
done