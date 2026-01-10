#!/bin/bash
#
# PHP HTML 注入启动器
# 一键启动带有 HTML 注入功能的 PHP 服务器
#

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
DEFAULT_PORT=8080
DEFAULT_OWNER="XXX"
DEFAULT_DOCROOT="."

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INJECTOR_FILE="$SCRIPT_DIR/injector.php"

# 帮助信息
show_help() {
    echo -e "${BLUE}PHP HTML 注入启动器${NC}"
    echo ""
    echo "用法: $0 [选项] [网站目录]"
    echo ""
    echo "选项:"
    echo "  -p, --port PORT      监听端口 (默认: $DEFAULT_PORT)"
    echo "  -o, --owner NAME     所有者名称 (默认: $DEFAULT_OWNER)"
    echo "  -P, --path PATH      只注入指定路径 (逗号分隔，如: /news/,/blog/)"
    echo "  -d, --debug          启用调试模式"
    echo "  -h, --help           显示此帮助"
    echo ""
    echo "示例:"
    echo "  $0                                    # 在当前目录启动，端口 8080"
    echo "  $0 -p 80 /var/www/html               # 指定端口和目录"
    echo "  $0 -o '我的公司' -P '/news/'          # 指定所有者和路径"
    echo "  $0 --debug /var/www/html             # 调试模式"
    echo ""
}

# 解析参数
PORT=$DEFAULT_PORT
OWNER=$DEFAULT_OWNER
INJECT_PATH=""
DEBUG=""
DOCROOT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -o|--owner)
            OWNER="$2"
            shift 2
            ;;
        -P|--path)
            INJECT_PATH="$2"
            shift 2
            ;;
        -d|--debug)
            DEBUG="1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo -e "${RED}错误: 未知选项 $1${NC}"
            show_help
            exit 1
            ;;
        *)
            DOCROOT="$1"
            shift
            ;;
    esac
done

# 默认网站目录
if [ -z "$DOCROOT" ]; then
    DOCROOT="$DEFAULT_DOCROOT"
fi

# 检查目录是否存在
if [ ! -d "$DOCROOT" ]; then
    echo -e "${RED}错误: 目录不存在: $DOCROOT${NC}"
    exit 1
fi

# 获取绝对路径
DOCROOT="$(cd "$DOCROOT" && pwd)"

# 检查 PHP
if ! command -v php &> /dev/null; then
    echo -e "${RED}错误: 未找到 PHP，请先安装 PHP${NC}"
    echo "Ubuntu/Debian: sudo apt install php"
    echo "CentOS/RHEL:   sudo yum install php"
    exit 1
fi

PHP_VERSION=$(php -v | head -n 1 | cut -d ' ' -f 2)

# 检查注入器文件
if [ ! -f "$INJECTOR_FILE" ]; then
    echo -e "${RED}错误: 未找到 injector.php${NC}"
    echo "请确保 injector.php 与此脚本在同一目录"
    exit 1
fi

# 显示配置
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  PHP HTML 注入服务器${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  PHP 版本:    ${YELLOW}$PHP_VERSION${NC}"
echo -e "  监听端口:    ${YELLOW}$PORT${NC}"
echo -e "  网站目录:    ${YELLOW}$DOCROOT${NC}"
echo -e "  所有者:      ${YELLOW}$OWNER${NC}"
if [ -n "$INJECT_PATH" ]; then
echo -e "  注入路径:    ${YELLOW}$INJECT_PATH${NC}"
else
echo -e "  注入路径:    ${YELLOW}所有 HTML 页面${NC}"
fi
if [ -n "$DEBUG" ]; then
echo -e "  调试模式:    ${YELLOW}已启用${NC}"
fi
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  访问地址: ${GREEN}http://localhost:$PORT${NC}"
echo ""
echo -e "  按 ${YELLOW}Ctrl+C${NC} 停止服务器"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 启动 PHP 服务器
export INJECT_OWNER="$OWNER"
export INJECT_PATH="$INJECT_PATH"
export INJECT_DEBUG="$DEBUG"

exec php \
    -d "auto_prepend_file=$INJECTOR_FILE" \
    -d "display_errors=On" \
    -d "error_reporting=E_ALL" \
    -S "0.0.0.0:$PORT" \
    -t "$DOCROOT"
