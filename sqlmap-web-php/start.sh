#!/bin/bash
#
# SQLMap 自动化扫描平台 - 一键启动脚本
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PORT=${1:-8080}

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  SQLMap 自动化扫描平台 (PHP 版本)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 检查 PHP
if ! command -v php &> /dev/null; then
    echo "错误: 未找到 PHP"
    exit 1
fi

PHP_VERSION=$(php -v | head -n 1 | cut -d ' ' -f 2)
echo -e "  PHP 版本:    ${YELLOW}$PHP_VERSION${NC}"
echo -e "  监听端口:    ${YELLOW}$PORT${NC}"
echo ""

# 创建必要目录
mkdir -p data output

# 启动 Worker (后台)
echo -e "  启动 Worker..."
php worker.php &
WORKER_PID=$!
echo -e "  Worker PID:  ${YELLOW}$WORKER_PID${NC}"
echo ""

# 清理函数
cleanup() {
    echo ""
    echo "停止服务..."
    kill $WORKER_PID 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  访问地址: ${GREEN}http://localhost:$PORT${NC}"
echo ""
echo -e "  按 ${YELLOW}Ctrl+C${NC} 停止服务"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 启动 PHP 内置服务器
php -S 0.0.0.0:$PORT
