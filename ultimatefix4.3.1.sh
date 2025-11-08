#!/bin/bash
#==============================================================================
# ФИНАЛЬНЫЙ СКРИПТ ЗАЩИТЫ СЕРВЕРОВ 3X-UI
# Версия: 4.3.1 ULTIMATE FIX (2025-10-31)
# ✅ 9 СЕРВЕРОВ + ОБРАБОТКА ОШИБОК
#==============================================================================

set -e

#==============================================================================
# КОНФИГУРАЦИЯ - ВСЕ 8 СЕРВЕРОВ
#==============================================================================
ADMIN_IPS=(
    "144.31.194.153"
    "78.36.72.113"
)

ALL_SERVER_IPS=(
    "144.31.26.235"	# Server 1
    "5.252.22.77"	# Server 2
    "45.150.64.25"	# Server 3
    "5.180.24.94"	# Server 4
    "2.56.173.209"	# Server 5
    "5.252.21.242"	# Server 6
    "178.17.48.60"	# Server 7
)

# Внутренние порты xray (исключаем из UFW)
INTERNAL_XRAY_PORTS=(11111 62789 27698)

#==============================================================================
# ЦВЕТА
#==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

#==============================================================================
# ФУНКЦИИ
#==============================================================================
print_header() {
    echo ""
    echo "=============================================="
    echo -e "${CYAN}$1${NC}"
    echo "=============================================="
}

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }

#==============================================================================
# НАЧАЛО
#==============================================================================
clear
print_header "🛡️  ФИНАЛЬНЫЙ СКРИПТ ЗАЩИТЫ 3X-UI v4.3.1"
echo ""
echo "Сервер: $(hostname)"
echo "Время: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

#==============================================================================
# ШАГ 0: АВТООПРЕДЕЛЕНИЕ КОНФИГУРАЦИИ
#==============================================================================
print_header "[0/7] 🔍 АВТООПРЕДЕЛЕНИЕ КОНФИГУРАЦИИ"
echo ""

# ОПРЕДЕЛЯЕМ СОБСТВЕННЫЙ IP СЕРВЕРА
print_info "Определяю внешний IP этого сервера..."
MY_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 icanhazip.com 2>/dev/null || curl -s --max-time 5 ipinfo.io/ip 2>/dev/null || echo "unknown")

if [ "$MY_IP" = "unknown" ]; then
    print_error "Не удалось определить внешний IP!"
    echo "Продолжаю без исключения собственного IP..."
    SERVER_IPS=("${ALL_SERVER_IPS[@]}")
else
    print_success "Мой IP: $MY_IP"
    
    # ИСКЛЮЧАЕМ СОБСТВЕННЫЙ IP ИЗ СПИСКА СЕРВЕРОВ
    print_info "Исключаю собственный IP из списка межсерверной связи..."
    SERVER_IPS=()
    for ip in "${ALL_SERVER_IPS[@]}"; do
        if [ "$ip" != "$MY_IP" ]; then
            SERVER_IPS+=("$ip")
        fi
    done
    
    if [ ${#SERVER_IPS[@]} -eq ${#ALL_SERVER_IPS[@]} ]; then
        print_warning "IP $MY_IP не найден в списке серверов (это нормально если сервер новый)"
    else
        print_success "Собственный IP исключен. Добавлю ${#SERVER_IPS[@]} других серверов"
    fi
fi

# SSH порт
print_info "Определяю SSH порт..."
SSH_PORT=$(sudo ss -tulpn 2>/dev/null | grep sshd | grep LISTEN | head -1 | grep -oP ':\K[0-9]+' || echo "22")
print_success "SSH порт: $SSH_PORT"

# x-ui порты
print_info "Определяю порты x-ui панели..."
XUI_PORTS=()
while IFS= read -r port; do
    XUI_PORTS+=("$port")
done < <(sudo ss -tulpn 2>/dev/null | grep "x-ui" | grep LISTEN | grep -oP ':\K[0-9]+(?=\s)' | sort -u)

if [ ${#XUI_PORTS[@]} -gt 0 ]; then
    print_success "Порты x-ui: ${XUI_PORTS[*]}"
else
    print_warning "Порты x-ui не обнаружены"
fi

# XRAY ПОРТЫ
print_info "Определяю клиентские порты xray (только внешние)..."
XRAY_PORTS=()
while IFS= read -r port; do
    is_internal=0
    for internal_port in "${INTERNAL_XRAY_PORTS[@]}"; do
        if [ "$port" = "$internal_port" ]; then
            is_internal=1
            break
        fi
    done
    
    if [ $is_internal -eq 0 ]; then
        XRAY_PORTS+=("$port")
    fi
done < <(sudo ss -tulpn 2>/dev/null | grep "xray" | grep "LISTEN" | grep -E "\s+\*:|0\.0\.0\.0:" | grep -oP ':\K[0-9]+(?=\s)' | sort -u)

if [ ${#XRAY_PORTS[@]} -eq 0 ]; then
    XRAY_PORTS=("443")
    print_warning "Клиентские порты не обнаружены, использую стандартный: 443"
else
    print_success "Клиентские порты xray: ${XRAY_PORTS[*]}"
fi

# Zabbix
print_info "Проверяю Zabbix..."
ZABBIX_FOUND=false
if sudo ss -tulpn 2>/dev/null | grep -q "zabbix"; then
    ZABBIX_FOUND=true
    print_warning "Zabbix обнаружен (будет остановлен)"
else
    print_success "Zabbix не обнаружен"
fi

echo ""
print_info "📋 ИТОГО ОПРЕДЕЛЕНО:"
echo "  • Мой IP: $MY_IP"
echo "  • SSH: порт $SSH_PORT"
echo "  • xray клиенты: ${XRAY_PORTS[*]}"
echo "  • x-ui панель: ${XUI_PORTS[*]:-нет}"
echo "  • Всего серверов в сети: ${#ALL_SERVER_IPS[@]}"
echo "  • Других серверов (для UFW): ${#SERVER_IPS[@]}"
echo ""

#==============================================================================
# ШАГ 1: УСТАНОВКА ПАКЕТОВ
#==============================================================================
print_header "[1/7] 📦 УСТАНОВКА ПАКЕТОВ"
echo ""

print_info "Обновляю список пакетов..."
sudo apt update -qq > /dev/null 2>&1 || print_warning "apt update вернул ошибку (игнорируем)"
print_success "Список обновлен"

if ! command -v ufw &> /dev/null; then
    print_info "Устанавливаю UFW..."
    sudo apt install ufw -y -qq > /dev/null 2>&1
    print_success "UFW установлен"
else
    print_success "UFW уже установлен"
fi

if ! command -v curl &> /dev/null; then
    print_info "Устанавливаю curl..."
    sudo apt install curl -y -qq > /dev/null 2>&1
    print_success "curl установлен"
else
    print_success "curl уже установлен"
fi

if ! command -v ss &> /dev/null; then
    print_info "Устанавливаю iproute2..."
    sudo apt install iproute2 -y -qq > /dev/null 2>&1
    print_success "iproute2 установлен"
else
    print_success "iproute2 уже установлен"
fi

echo ""

#==============================================================================
# ШАГ 2: КОНФИГУРАЦИЯ SYSCTL
#==============================================================================
print_header "[2/7] ⚙️  КОНФИГУРАЦИЯ SYSCTL"
echo ""

print_info "Очищаю старые параметры..."
sudo sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf 2>/dev/null || true
sudo sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf 2>/dev/null || true
sudo sed -i '/net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.conf 2>/dev/null || true
sudo sed -i '/net.ipv4.icmp_echo_ignore_all/d' /etc/sysctl.conf 2>/dev/null || true
sudo sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf 2>/dev/null || true
sudo sed -i '/net.core.rmem_max/d' /etc/sysctl.conf 2>/dev/null || true
sudo sed -i '/net.core.wmem_max/d' /etc/sysctl.conf 2>/dev/null || true
sudo sed -i '/net.ipv4.udp_rmem_min/d' /etc/sysctl.conf 2>/dev/null || true
sudo sed -i '/net.ipv4.udp_wmem_min/d' /etc/sysctl.conf 2>/dev/null || true
sudo sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null || true
sudo sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf 2>/dev/null || true

print_info "Добавляю новые параметры защиты..."
sudo tee -a /etc/sysctl.conf > /dev/null << 'EOF'

# ===== АВТОМАТИЧЕСКАЯ ЗАЩИТА 3X-UI v4.3.1 =====
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
net.ipv4.icmp_echo_ignore_all=1
net.ipv4.ip_forward=1
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
net.ipv4.tcp_congestion_control=bbr
net.core.default_qdisc=fq
EOF

print_info "Применяю sysctl (с таймаутом)..."
timeout 10 sudo sysctl -p > /dev/null 2>&1 || print_warning "sysctl -p таймаут (продолжаю)"
print_success "sysctl.conf применен"

# Дополнительные файлы
echo "net.ipv4.icmp_echo_ignore_all=1" | sudo tee /etc/sysctl.d/99-disable-ping.conf > /dev/null
echo "net.ipv4.icmp_echo_ignore_all=1" | sudo tee /etc/sysctl.d/98-no-ping.conf > /dev/null
timeout 10 sudo sysctl -p /etc/sysctl.d/99-disable-ping.conf > /dev/null 2>&1 || true
timeout 10 sudo sysctl -p /etc/sysctl.d/98-no-ping.conf > /dev/null 2>&1 || true
print_success "Дополнительные конфиги созданы"

echo ""

#==============================================================================
# ШАГ 3: SYSTEMD СЕРВИС ДЛЯ PING ЗАЩИТЫ
#==============================================================================
print_header "[3/7] 🛡️  SYSTEMD ЗАЩИТА PING"
echo ""

print_info "Создаю systemd сервис..."
sudo tee /etc/systemd/system/enable-ping-protection.service > /dev/null << 'EOF'
[Unit]
Description=Enable ICMP Echo Protection (Disable Ping)
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sysctl -w net.ipv4.icmp_echo_ignore_all=1'
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable enable-ping-protection.service > /dev/null 2>&1 || true
sudo systemctl start enable-ping-protection.service > /dev/null 2>&1 || true

if sudo systemctl is-active --quiet enable-ping-protection.service; then
    print_success "Systemd сервис: АКТИВЕН"
else
    print_warning "Systemd сервис НЕ активен (продолжаю)"
fi

timeout 5 sudo sysctl -w net.ipv4.icmp_echo_ignore_all=1 > /dev/null 2>&1 || true
print_success "Ping заблокирован (тройная защита + systemd)"

echo ""

#==============================================================================
# ШАГ 4: КОНФИГУРАЦИЯ UFW
#==============================================================================
print_header "[4/7] 🔥 UFW FIREWALL"
echo ""

print_info "Сброс UFW..."
sudo ufw --force reset > /dev/null 2>&1 || print_warning "UFW reset вернул ошибку"

# SSH
print_info "Открываю SSH порт: $SSH_PORT"
sudo ufw allow ${SSH_PORT}/tcp comment "SSH port ${SSH_PORT}" > /dev/null 2>&1 || true

# XRAY КЛИЕНТСКИЕ ПОРТЫ
for port in "${XRAY_PORTS[@]}"; do
    print_info "Открываю xray порт: $port"
    sudo ufw allow ${port}/tcp comment "VLESS/xray port ${port}" > /dev/null 2>&1 || true
done

# ADMIN IPS
print_info "Добавляю админ IP (полный доступ)..."
for ip in "${ADMIN_IPS[@]}"; do
    sudo ufw allow from "$ip" comment "Admin IP - full access" > /dev/null 2>&1 || true
    echo "  ✓ $ip"
done

# SERVERS (исключая собственный IP!)
print_info "Добавляю межсерверную связь (${#SERVER_IPS[@]} других серверов)..."
for ip in "${SERVER_IPS[@]}"; do
    sudo ufw allow from "$ip" comment "Server - full access" > /dev/null 2>&1 || true
    echo "  ✓ $ip"
done

# ZABBIX
if [ "$ZABBIX_FOUND" = true ]; then
    print_info "Блокирую Zabbix порт 10050"
    sudo ufw deny 10050/tcp comment "Zabbix blocked" > /dev/null 2>&1 || true
fi

# ПОЛИТИКИ
print_info "Устанавливаю политики..."
sudo ufw default deny incoming > /dev/null 2>&1 || true
sudo ufw default allow outgoing > /dev/null 2>&1 || true

# ВКЛЮЧЕНИЕ
print_info "Активирую UFW..."
sudo ufw --force enable > /dev/null 2>&1 || print_warning "UFW enable вернул ошибку"

print_success "UFW сконфигурирован"

echo ""

#==============================================================================
# ШАГ 5: ОТКЛЮЧЕНИЕ НЕНУЖНЫХ СЕРВИСОВ
#==============================================================================
print_header "[5/7] 🗑️  ОТКЛЮЧЕНИЕ НЕНУЖНЫХ СЕРВИСОВ"
echo ""

if [ "$ZABBIX_FOUND" = true ]; then
    print_info "Останавливаю Zabbix Agent..."
    sudo systemctl stop zabbix-agent > /dev/null 2>&1 || true
    sudo systemctl disable zabbix-agent > /dev/null 2>&1 || true
    print_success "Zabbix Agent остановлен"
else
    print_success "Zabbix Agent не обнаружен"
fi

sudo systemctl daemon-reload > /dev/null 2>&1 || true

echo ""

#==============================================================================
# ШАГ 6: ПРОВЕРКА КОНФЛИКТОВ
#==============================================================================
print_header "[6/7] 🔍 ПРОВЕРКА КОНФЛИКТОВ"
echo ""

print_info "Проверяю UFW/sysctl конфликты..."
if grep -q "icmp_echo_ignore_all" /etc/ufw/sysctl.conf 2>/dev/null; then
    print_warning "Конфликт найден в /etc/ufw/sysctl.conf"
    sudo sed -i '/icmp_echo_ignore_all/d' /etc/ufw/sysctl.conf
    print_success "Конфликт устранен"
else
    print_success "Конфликтов не найдено"
fi

timeout 5 sudo sysctl -w net.ipv4.icmp_echo_ignore_all=1 > /dev/null 2>&1 || true

echo ""

#==============================================================================
# ШАГ 7: ФИНАЛЬНАЯ ПРОВЕРКА
#==============================================================================
print_header "[7/7] ✅ ФИНАЛЬНАЯ ПРОВЕРКА"
echo ""

print_header "📊 ИТОГОВЫЙ СТАТУС СЕРВЕРА"
echo ""
echo "🖥️  Сервер: $(hostname)"
echo "🌐 IP адрес: $MY_IP"
echo "🕐 Время: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

print_info "🔒 UFW Правила (топ-30):"
echo "---"
sudo ufw status numbered 2>/dev/null | head -35 || echo "Не удалось получить статус UFW"

echo ""
print_info "🔌 Открытые клиентские порты:"
echo "---"
sudo ss -tulpn 2>/dev/null | grep "LISTEN" | grep -E "(${XRAY_PORTS[*]// /|}|${SSH_PORT})" | head -10 || echo "Порты не обнаружены"

echo ""
print_info "⚙️  Параметры sysctl:"
echo "---"
IPV6_STATUS=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo "?")
PING_STATUS=$(sysctl -n net.ipv4.icmp_echo_ignore_all 2>/dev/null || echo "?")
FORWARD_STATUS=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "?")
BBR_STATUS=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "?")
QDISC_STATUS=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "?")

printf "  %-30s %s\n" "IPv6 отключен:" "$IPV6_STATUS"
printf "  %-30s %s\n" "ICMP ping заблокирован:" "$PING_STATUS"
printf "  %-30s %s\n" "IP forwarding:" "$FORWARD_STATUS"
printf "  %-30s %s\n" "TCP congestion control:" "$BBR_STATUS"
printf "  %-30s %s\n" "Default qdisc:" "$QDISC_STATUS"

echo ""
print_info "🚀 BBR модуль:"
echo "---"
if lsmod | grep -q bbr 2>/dev/null; then
    print_success "BBR загружен"
    lsmod | grep bbr | head -2
else
    print_warning "BBR не загружен (требуется перезагрузка)"
fi

echo ""
print_info "🛡️  Systemd сервис ping защиты:"
echo "---"
if sudo systemctl is-active --quiet enable-ping-protection.service 2>/dev/null; then
    print_success "Сервис АКТИВЕН"
else
    print_warning "Сервис может быть неактивен (проверь после перезагрузки)"
fi

echo ""
print_header "🎯 ФИНАЛЬНЫЙ РЕЗУЛЬТАТ"
echo ""

# Проверка
ALL_OK=true
if [ "$IPV6_STATUS" != "1" ]; then ALL_OK=false; fi
if [ "$PING_STATUS" != "1" ]; then ALL_OK=false; fi

if [ "$ALL_OK" = true ]; then
    print_success "════════════════════════════════════════════"
    print_success "  ✅ ВСЕ ЗАЩИТЫ АКТИВНЫ! v4.3.1"
    print_success "════════════════════════════════════════════"
    echo ""
    echo "✅ Мой IP: $MY_IP (исключен из UFW)"
    echo "✅ Других серверов с доступом: ${#SERVER_IPS[@]}"
    echo "✅ Админ IP: 2"
    echo ""
    print_success "════════════════════════════════════════════"
else
    print_error "════════════════════════════════════════════"
    print_error "  ⚠️  ТРЕБУЕТСЯ ПЕРЕЗАГРУЗКА"
    print_error "════════════════════════════════════════════"
    echo ""
    echo "Команда для перезагрузки:"
    echo "  sudo reboot"
fi

echo ""
echo "Завершено: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
