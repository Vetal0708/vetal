#!/bin/bash
#==============================================================================
# ФИНАЛЬНЫЙ СКРИПТ ЗАЩИТЫ СЕРВЕРОВ 3X-UI
# Версия: 5.0 PRO (2025-11-01)
# ✅ ПРОФЕССИОНАЛЬНАЯ ВЕРСИЯ: УСИЛЕННАЯ БЕЗОПАСНОСТЬ И НАДЕЖНОСТЬ
#==============================================================================

# Немедленно выходить, если команда завершается с ошибкой
set -e
# Фиксируем время начала
START_TIME=$(date +%s)

#==============================================================================
# КОНФИГУРАЦИЯ
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

# Внутренние порты xray, которые не нужно открывать в UFW
INTERNAL_XRAY_PORTS=(11111 62789 27698)

#==============================================================================
# ЦВЕТА И УТИЛИТЫ
#==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() { echo -e "\n==============================================\n${CYAN}$1${NC}\n=============================================="; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_info() { echo -e "ℹ️  $1"; }

# Функция для установки пакетов, если они отсутствуют
install_if_needed() {
    if ! command -v "$1" &> /dev/null; then
        print_info "Устанавливаю $2..."
        sudo apt-get install -y -qq "$2" > /dev/null 2>&1
        print_success "$2 установлен"
    else
        print_success "$2 уже установлен"
    fi
}

#==============================================================================
# НАЧАЛО
#==============================================================================
clear
print_header "🛡️  СКРИПТ ЗАЩИТЫ 3X-UI v5.0 PRO"
print_info "Сервер: $(hostname)"
print_info "Время: $(date '+%Y-%m-%d %H:%M:%S')"

#==============================================================================
# ШАГ 0: АВТООПРЕДЕЛЕНИЕ КОНФИГУРАЦИИ
#==============================================================================
print_header "[0/8] 🔍 АВТООПРЕДЕЛЕНИЕ КОНФИГУРАЦИИ"

# ОПРЕДЕЛЯЕМ IP
print_info "Определяю внешний IP этого сервера..."
MY_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || curl -s --max-time 4 ifconfig.me 2>/dev/null || curl -s --max-time 4 icanhazip.com 2>/dev/null)
if [ -z "$MY_IP" ]; then
    print_error "Не удалось определить внешний IP! Скрипт не может продолжить."
    exit 1
fi
print_success "Мой IP: $MY_IP"

# ИСКЛЮЧАЕМ СОБСТВЕННЫЙ IP ИЗ СПИСКА
SERVER_IPS=()
for ip in "${ALL_SERVER_IPS[@]}"; do
    [[ "$ip" != "$MY_IP" ]] && SERVER_IPS+=("$ip")
done

# SSH ПОРТ (САМАЯ НАДЕЖНАЯ ВЕРСИЯ)
print_info "Определяю SSH порт..."
SSH_PORT=$(sudo ss -tlnp 2>/dev/null | grep -E 'sshd|opensshd|dropbear' | grep -E '(\*|0\.0\.0\.0):' | grep -oP ':\K[0-9]+' | head -1 || echo "22")
print_success "SSH порт: $SSH_PORT"

# X-UI ПОРТЫ
print_info "Определяю порты x-ui панели..."
XUI_PORTS=($(sudo ss -tulpn 2>/dev/null | grep "x-ui" | grep LISTEN | grep -oP ':\K[0-9]+(?=\s)' | sort -u))
if [ ${#XUI_PORTS[@]} -gt 0 ]; then
    print_success "Порты x-ui: ${XUI_PORTS[*]}"
else
    print_warning "Порты x-ui не обнаружены (это нормально)"
fi

# XRAY ПОРТЫ
print_info "Определяю клиентские порты xray..."
XRAY_PORTS_ALL=($(sudo ss -tulpn 2>/dev/null | grep "xray" | grep "LISTEN" | grep -E "\s+\*:|0\.0\.0\.0:" | grep -oP ':\K[0-9]+(?=\s)' | sort -u))
XRAY_PORTS=()
for port in "${XRAY_PORTS_ALL[@]}"; do
    is_internal=0
    for internal_port in "${INTERNAL_XRAY_PORTS[@]}"; do
        [[ "$port" == "$internal_port" ]] && is_internal=1 && break
    done
    [[ $is_internal -eq 0 ]] && XRAY_PORTS+=("$port")
done

if [ ${#XRAY_PORTS[@]} -eq 0 ]; then
    XRAY_PORTS=("443")
    print_warning "Клиентские порты не обнаружены, использую стандартный: 443"
else
    print_success "Клиентские порты xray: ${XRAY_PORTS[*]}"
fi

# ZABBIX
print_info "Проверяю Zabbix..."
if systemctl is-active --quiet zabbix-agent 2>/dev/null; then
    ZABBIX_FOUND=true
    print_warning "Zabbix обнаружен (будет остановлен и отключен)"
else
    ZABBIX_FOUND=false
    print_success "Zabbix не обнаружен"
fi

#==============================================================================
# ШАГ 1: ПОДТВЕРЖДЕНИЕ ПЕРЕД ПРИМЕНЕНИЕМ
#==============================================================================
print_header "[1/8] 🛡️ ПРОВЕРКА И ПОДТВЕРЖДЕНИЕ"
echo "Скрипт определил следующие параметры:"
echo "------------------------------------------------"
echo -e "  • Мой IP для исключения : ${CYAN}$MY_IP${NC}"
echo -e "  • ${YELLOW}SSH порт для доступа    : $SSH_PORT${NC}"
echo -e "  • Клиентские порты Xray : ${XRAY_PORTS[*]}"
echo "------------------------------------------------"
print_warning "ВАЖНО: Убедитесь, что SSH порт определен правильно!"
print_warning "Неправильная настройка ЗАБЛОКИРУЕТ ваш доступ к серверу."
echo ""
read -p "Продолжить и применить эти настройки? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[YyДд]$ ]]; then
    print_error "Операция отменена пользователем."
    exit 1
fi
print_success "Подтверждение получено. Начинаю настройку..."

#==============================================================================
# ШАГ 2: УСТАНОВКА ПАКЕТОВ
#==============================================================================
print_header "[2/8] 📦 УСТАНОВКА ПАКЕТОВ"
print_info "Обновляю список пакетов..."
sudo apt-get update -qq > /dev/null 2>&1 || print_warning "apt update вернул ошибку (игнорируем)"
install_if_needed "ufw" "ufw"
install_if_needed "curl" "curl"
install_if_needed "ss" "iproute2"

#==============================================================================
# ШАГ 3: КОНФИГУРАЦИЯ SYSCTL
#==============================================================================
print_header "[3/8] ⚙️  КОНФИГУРАЦИЯ SYSCTL"
print_info "Очищаю старые параметры и добавляю новые..."
# Безопасный способ: фильтруем старые строки и дописываем новые
CONFIG_BLOCK=$(cat <<'EOF'
# ===== АВТОМАТИЧЕСКАЯ ЗАЩИТА 3X-UI v5.0 =====
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
)
# Фильтруем все строки, которые есть в нашем блоке
grep -vE "disable_ipv6|icmp_echo_ignore_all|ip_forward|rmem_max|wmem_max|udp_rmem_min|udp_wmem_min|tcp_congestion_control|default_qdisc" /etc/sysctl.conf | sudo tee /etc/sysctl.conf.tmp > /dev/null
# Добавляем наш блок в конец
echo "$CONFIG_BLOCK" | sudo tee -a /etc/sysctl.conf.tmp > /dev/null
# Атомарно заменяем старый файл новым
sudo mv /etc/sysctl.conf.tmp /etc/sysctl.conf

print_info "Применяю sysctl..."
timeout 10 sudo sysctl -p > /dev/null 2>&1 || print_warning "sysctl -p таймаут (продолжаю)"
print_success "sysctl.conf применен"

#==============================================================================
# ШАГ 4: SYSTEMD СЕРВИС ДЛЯ PING ЗАЩИТЫ
#==============================================================================
print_header "[4/8] 🛡️  SYSTEMD ЗАЩИТА PING"
print_info "Создаю/обновляю systemd сервис..."
sudo tee /etc/systemd/system/enable-ping-protection.service > /dev/null << 'EOF'
[Unit]
Description=Enable ICMP Echo Protection (Disable Ping)
After=network.target network-online.target
[Service]
Type=oneshot
ExecStart=/sbin/sysctl -w net.ipv4.icmp_echo_ignore_all=1
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now enable-ping-protection.service > /dev/null 2>&1 || true
if sudo systemctl is-active --quiet enable-ping-protection.service; then
    print_success "Systemd сервис для защиты от ping: АКТИВЕН"
else
    print_warning "Systemd сервис НЕ активен (может потребоваться перезагрузка)"
fi

#==============================================================================
# ШАГ 5: КОНФИГУРАЦИЯ UFW
#==============================================================================
print_header "[5/8] 🔥 UFW FIREWALL"
print_info "Сброс UFW до настроек по умолчанию..."
echo "y" | sudo ufw reset > /dev/null

print_info "Добавляю ключевые правила..."
# КРИТИЧЕСКИ ВАЖНЫЙ ШАГ: если не удалось открыть SSH порт - ВЫХОДИМ!
sudo ufw allow "${SSH_PORT}/tcp" comment "SSH port" > /dev/null || { print_error "КРИТИЧЕСКАЯ ОШИБКА: Не удалось добавить правило для SSH порта! Прерываю выполнение."; exit 1; }
print_success "Правило для SSH порта $SSH_PORT добавлено"

if [ ${#XRAY_PORTS[@]} -gt 0 ]; then
    for port in "${XRAY_PORTS[@]}"; do
        sudo ufw allow "${port}/tcp" comment "Xray client port" > /dev/null
    done
    print_success "Правила для клиентских портов Xray добавлены"
fi

for ip in "${ADMIN_IPS[@]}"; do sudo ufw allow from "$ip" comment "Admin IP" > /dev/null; done
print_success "Правила для IP администраторов добавлены"

if [ ${#SERVER_IPS[@]} -gt 0 ]; then
    for ip in "${SERVER_IPS[@]}"; do sudo ufw allow from "$ip" comment "Server IP" > /dev/null; done
    print_success "Правила для межсерверного обмена добавлены"
fi

if [ "$ZABBIX_FOUND" = true ]; then
    sudo ufw deny 10050/tcp comment "Zabbix blocked" > /dev/null
    print_success "Правило для блокировки Zabbix добавлено"
fi

print_info "Устанавливаю политики по умолчанию (DENY IN, ALLOW OUT)..."
sudo ufw default deny incoming > /dev/null
sudo ufw default allow outgoing > /dev/null

print_info "Активирую UFW..."
echo "y" | sudo ufw enable > /dev/null
print_success "UFW сконфигурирован и активен"

#==============================================================================
# ШАГ 6: ОТКЛЮЧЕНИЕ НЕНУЖНЫХ СЕРВИСОВ
#==============================================================================
print_header "[6/8] 🗑️  ОТКЛЮЧЕНИЕ НЕНУЖНЫХ СЕРВИСОВ"
if [ "$ZABBIX_FOUND" = true ]; then
    print_info "Останавливаю и отключаю Zabbix Agent..."
    sudo systemctl disable --now zabbix-agent > /dev/null 2>&1 || true
    print_success "Zabbix Agent остановлен и отключен"
fi

#==============================================================================
# ШАГ 7: ПРОВЕРКА КОНФЛИКТОВ
#==============================================================================
print_header "[7/8] 🔍 ПРОВЕРКА КОНФЛИКТОВ"
if grep -q "icmp_echo_ignore_all" /etc/ufw/sysctl.conf 2>/dev/null; then
    print_warning "Конфликт найден в /etc/ufw/sysctl.conf. Устраняю..."
    sudo sed -i '/icmp_echo_ignore_all/d' /etc/ufw/sysctl.conf
    print_success "Конфликт устранен"
else
    print_success "Конфликтов не найдено"
fi

#==============================================================================
# ШАГ 8: ФИНАЛЬНАЯ ПРОВЕРКА
#==============================================================================
print_header "[8/8] ✅ ФИНАЛЬНАЯ ПРОВЕРКА"
print_header "📊 ИТОГОВЫЙ СТАТУС СЕРВЕРА"
sudo ufw status verbose
echo "---"
print_info "Ключевые параметры sysctl:"
printf "  %-30s %s\n" "IPv6 отключен:" "$(sysctl -n net.ipv6.conf.all.disable_ipv6)"
printf "  %-30s %s\n" "ICMP ping заблокирован:" "$(sysctl -n net.ipv4.icmp_echo_ignore_all)"
printf "  %-30s %s\n" "TCP congestion control:" "$(sysctl -n net.ipv4.tcp_congestion_control)"
echo "---"

if [ "$(sysctl -n net.ipv4.icmp_echo_ignore_all)" = "1" ] && lsmod | grep -q 'bbr'; then
    print_success "════════════════════════════════════════════"
    print_success "  ✅ ВСЕ ЗАЩИТЫ АКТИВНЫ! СЕРВЕР ЗАЩИЩЕН."
    print_success "════════════════════════════════════════════"
else
    print_error "════════════════════════════════════════════"
    print_error "  ⚠️  НЕ ВСЕ ПАРАМЕТРЫ ПРИМЕНИЛИСЬ!"
    print_error "  РЕКОМЕНДУЕТСЯ ПЕРЕЗАГРУЗКА: sudo reboot"
    print_error "════════════════════════════════════════════"
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo -e "\n${GREEN}Завершено за $DURATION сек.${NC}\n"