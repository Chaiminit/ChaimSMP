#!/bin/bash

# Minecraft Server 启动脚本
# 功能：启动Docker容器、自动解除端口占用、显示IPv6地址、设置每日0点自动备份推送

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_highlight() {
    echo -e "${CYAN}$1${NC}"
}

# 检查Docker是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装，请先安装Docker"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose未安装，请先安装Docker Compose"
        exit 1
    fi

    log_info "Docker检查通过"
}

# 获取并显示IP地址
show_ip_addresses() {
    log_info "服务器网络地址信息："
    echo ""
    
    # IPv4 地址
    log_highlight "=== IPv4 地址 ==="
    local ipv4_addrs=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1')
    if [ -n "$ipv4_addrs" ]; then
        while IFS= read -r addr; do
            echo "  ${GREEN}➜${NC} $addr:25565"
        done <<< "$ipv4_addrs"
    else
        echo "  ${YELLOW}未找到IPv4地址${NC}"
    fi
    echo ""
    
    # IPv6 地址
    log_highlight "=== IPv6 地址 ==="
    local ipv6_addrs=$(ip -6 addr show | grep -oP '(?<=inet6\s)[0-9a-fA-F:]+' | grep -v '^::1$' | grep -v '^fe80')
    if [ -n "$ipv6_addrs" ]; then
        while IFS= read -r addr; do
            echo "  ${GREEN}➜${NC} [$addr]:25565"
        done <<< "$ipv6_addrs"
    else
        echo "  ${YELLOW}未找到公网IPv6地址${NC}"
    fi
    echo ""
    
    # 本地地址
    log_highlight "=== 本地连接 ==="
    echo "  ${GREEN}➜${NC} localhost:25565"
    echo "  ${GREEN}➜${NC} 127.0.0.1:25565"
    echo "  ${GREEN}➜${NC} [::1]:25565"
    echo ""
}

# 解除25565端口占用
release_port() {
    log_info "检查25565端口占用情况..."
    
    # 查找占用25565端口的进程
    local pids=$(lsof -ti:25565 2>/dev/null || netstat -tlnp 2>/dev/null | grep ':25565' | awk '{print $7}' | cut -d'/' -f1 | grep -o '[0-9]*')
    
    if [ -n "$pids" ]; then
        log_warn "发现25565端口被占用，进程ID: $pids"
        
        # 检查是否是Docker容器
        local docker_containers=$(docker ps -q --filter "publish=25565" 2>/dev/null)
        if [ -n "$docker_containers" ]; then
            log_info "发现Docker容器占用端口，正在停止容器..."
            docker stop $docker_containers 2>/dev/null
            docker rm $docker_containers 2>/dev/null
            log_info "Docker容器已停止并移除"
        fi
        
        # 杀死其他进程
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                log_warn "终止进程 $pid..."
                kill -9 "$pid" 2>/dev/null
            fi
        done
        
        # 等待端口释放
        sleep 2
        
        # 再次检查
        if lsof -ti:25565 &>/dev/null; then
            log_error "无法释放25565端口，请手动检查"
            exit 1
        else
            log_info "25565端口已释放"
        fi
    else
        log_info "25565端口未被占用"
    fi
}

# 创建数据目录并下载PaperMC
prepare_directories() {
    if [ ! -d "./data" ]; then
        mkdir -p ./data
        log_info "创建数据目录: ./data"
    fi
    
    # 下载PaperMC服务端
    if [ ! -f "./data/paper.jar" ]; then
        log_info "正在下载PaperMC服务端..."
        wget -O ./data/paper.jar https://fill-data.papermc.io/v1/objects/da497e12b43e5b61c5df150e4bfd0de0f53043e57d2ac98dd59289ee9da4ad68/paper-1.21.11-127.jar
        if [ $? -eq 0 ]; then
            log_info "PaperMC下载成功"
        else
            log_error "PaperMC下载失败"
            exit 1
        fi
    else
        log_info "PaperMC服务端已存在"
    fi
    
    # 创建eula.txt
    if [ ! -f "./data/eula.txt" ]; then
        echo "eula=true" > ./data/eula.txt
        log_info "已创建eula.txt"
    fi
}

# 启动Minecraft服务器
start_server() {
    log_info "正在启动Minecraft服务器..."

    # 检查是否使用 docker compose (新语法) 或 docker-compose (旧语法)
    if docker compose version &> /dev/null; then
        docker compose up -d --build
    else
        docker-compose up -d --build
    fi

    if [ $? -eq 0 ]; then
        log_info "Minecraft服务器启动成功！"
        echo ""
        log_highlight "╔════════════════════════════════════════════════════════╗"
        log_highlight "║         Minecraft服务器已成功启动！                    ║"
        log_highlight "╚════════════════════════════════════════════════════════╝"
        echo ""
        show_ip_addresses
    else
        log_error "Minecraft服务器启动失败"
        exit 1
    fi
}

# 备份函数
backup_and_push() {
    local BACKUP_DIR="$SCRIPT_DIR"
    local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    local DATE=$(date '+%Y-%m-%d')

    log_info "[$TIMESTAMP] 开始执行每日备份..."

    cd "$BACKUP_DIR"

    # 检查是否有变更
    if [ -z "$(git status --porcelain)" ]; then
        log_info "[$TIMESTAMP] 没有文件变更，跳过备份"
        return 0
    fi

    # 添加所有变更
    git add -A

    # 提交变更
    git commit -m "自动备份: $DATE - Minecraft服务器数据"

    if [ $? -eq 0 ]; then
        # 推送到远程仓库
        git push origin master
        if [ $? -eq 0 ]; then
            log_info "[$TIMESTAMP] 备份成功推送到远程仓库"
        else
            log_error "[$TIMESTAMP] 推送到远程仓库失败"
        fi
    else
        log_warn "[$TIMESTAMP] 没有需要提交的变更"
    fi
}

# 设置定时任务（每日0点执行备份）
setup_cron() {
    log_info "设置每日0点自动备份..."

    # 获取当前脚本的绝对路径
    local SCRIPT_PATH="$(realpath "$0")"

    # 创建cron任务
    local CRON_JOB="0 0 * * * cd $SCRIPT_DIR && bash $SCRIPT_PATH backup"

    # 检查是否已存在相同的cron任务
    if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH backup"; then
        log_info "自动备份任务已存在"
    else
        # 添加新的cron任务
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        log_info "自动备份任务已设置: 每日0:00执行"
    fi
}

# 显示状态
show_status() {
    log_info "检查服务器状态..."

    if docker ps | grep -q "chaimsmp"; then
        log_info "Minecraft服务器运行中"
        docker ps | grep chaimsmp
    else
        log_warn "Minecraft服务器未运行"
    fi
}

# 停止服务器
stop_server() {
    log_info "正在停止Minecraft服务器..."

    if docker ps | grep -q "chaimsmp"; then
        if docker compose version &> /dev/null; then
            docker compose down
        else
            docker-compose down
        fi
        log_info "Minecraft服务器已停止"
    else
        log_warn "Minecraft服务器未运行"
    fi
}

# 查看日志
show_logs() {
    log_info "显示Minecraft服务器日志 (按 Ctrl+C 退出)..."
    if docker compose version &> /dev/null; then
        docker compose logs -f
    else
        docker-compose logs -f
    fi
}

# 主函数
main() {
    case "${1:-start}" in
        start)
            check_docker
            release_port
            prepare_directories
            start_server
            setup_cron
            show_status
            echo ""
            log_info "使用 './start.sh logs' 查看服务器日志"
            log_info "使用 './start.sh stop' 停止服务器"
            ;;
        stop)
            stop_server
            ;;
        restart)
            stop_server
            sleep 2
            release_port
            check_docker
            prepare_directories
            start_server
            show_status
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        backup)
            backup_and_push
            ;;
        ip)
            show_ip_addresses
            ;;
        *)
            echo "用法: $0 {start|stop|restart|status|logs|backup|ip}"
            echo ""
            echo "命令说明:"
            echo "  start   - 启动服务器并设置自动备份 (默认)"
            echo "  stop    - 停止服务器"
            echo "  restart - 重启服务器"
            echo "  status  - 查看服务器状态"
            echo "  logs    - 查看服务器日志"
            echo "  backup  - 立即执行备份"
            echo "  ip      - 显示服务器IP地址"
            exit 1
            ;;
    esac
}

main "$@"
