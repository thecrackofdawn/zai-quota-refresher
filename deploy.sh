#!/bin/bash
# 智谱 API 自动刷新工具 - 一键部署脚本
# 支持 cron 定时任务的创建、删除、查看
# 支持从 GitHub 仓库自动拉取代码
#
# 使用方法:
#   方式1: curl -fsSL https://raw.githubusercontent.com/thecrackofdawn/zai-quota-refresher/main/deploy.sh | bash -s install
#   方式2: wget -qO- https://raw.githubusercontent.com/thecrackofdawn/zai-quota-refresher/main/deploy.sh | bash -s install
#   方式3: 下载后执行: ./deploy.sh install
#   设置环境变量: ZHIPU_API_KEY="your_key" ./deploy.sh install

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的信息
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检测是否通过管道执行
if [ ! -t 0 ]; then
    # 通过管道执行，需要交互式输入
    print_warning "检测到通过管道执行模式"

    # 如果设置了环境变量，则继续执行
    if [ -n "$ZHIPU_API_KEY" ]; then
        print_info "检测到 ZHIPU_API_KEY 环境变量，将继续非交互式安装..."
    else
        print_error "管道执行模式不支持交互式输入！"
        echo ""
        print_info "请使用以下方式之一："
        echo ""
        print_info "方式1：设置环境变量后执行（推荐）"
        echo "  export ZHIPU_API_KEY=\"your_api_key_here\""
        echo "  curl -fsSL https://raw.githubusercontent.com/thecrackofdawn/zai-quota-refresher/main/deploy.sh | bash -s install"
        echo ""
        print_info "方式2：下载后执行（交互式）"
        echo "  curl -fsSL https://raw.githubusercontent.com/thecrackofdawn/zai-quota-refresher/main/deploy.sh -o deploy.sh"
        echo "  chmod +x deploy.sh"
        echo "  ./deploy.sh install"
        echo ""
        print_info "方式3：直接 git clone"
        echo "  git clone https://github.com/thecrackofdawn/zai-quota-refresher.git"
        echo "  cd zai-quota-refresher"
        echo "  ./deploy.sh install"
        echo ""
        exit 1
    fi
fi

# 项目配置
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目配置
REPO_URL="https://github.com/thecrackofdawn/zai-quota-refresher.git"
SCRIPT_NAME="quota_refresher.py"
PYTHON_PATH="/usr/bin/python3"

# 获取实际用户（解决 sudo 环境下的用户问题）
get_real_user() {
    if [ -n "$SUDO_USER" ]; then
        echo "$SUDO_USER"
    elif [ -n "$SUDO_UID" ]; then
        # 如果有 SUDO_UID，获取对应的用户名
        getent passwd "$SUDO_UID" | cut -d: -f1
    else
        # 回退到 logname 或当前用户
        logname 2>/dev/null || echo "$USER"
    fi
}

REAL_USER=$(get_real_user)
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
INSTALL_DIR="$REAL_HOME/.zai-quota-refresher"

# 检查必要的命令
check_commands() {
    local missing_commands=()

    for cmd in git curl python3; do
        if ! command -v $cmd &> /dev/null; then
            missing_commands+=($cmd)
        fi
    done

    if [ ${#missing_commands[@]} -ne 0 ]; then
        print_error "缺少必要的命令: ${missing_commands[*]}"
        print_info "请先安装缺少的命令："
        print_info "  Ubuntu/Debian: sudo apt-get install git curl python3"
        print_info "  CentOS/RHEL:   sudo yum install git curl python3"
        exit 1
    fi
}

# 从 GitHub 拉取代码
pull_from_github() {
    print_step "从 GitHub 拉取代码..."

    # 直接使用当前用户执行 git 操作（不需要 sudo）
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "安装目录已存在: $INSTALL_DIR"
        print_info "默认执行代码更新（30秒内可按 Ctrl+C 取消）..."

        # 直接执行更新，不询问
        print_info "更新代码..."
        git -C "$INSTALL_DIR" pull || {
            print_error "git pull 失败，但继续使用现有代码"
        }
        print_info "代码更新完成"
    else
        print_info "克隆仓库到: $INSTALL_DIR"
        git clone "$REPO_URL" "$INSTALL_DIR" || {
            print_error "git clone 失败"
            return 1
        }
        print_info "代码克隆完成"
    fi

    # 确保 Python 脚本有执行权限
    if [ -f "$INSTALL_DIR/${SCRIPT_NAME}" ]; then
        chmod +x "$INSTALL_DIR/${SCRIPT_NAME}"
        print_info "已设置脚本执行权限"
    fi
}

# 检查 Python 环境
check_python() {
    if ! command -v python3 &> /dev/null; then
        print_error "未找到 Python3，请先安装 Python3"
        exit 1
    fi
    print_info "Python3 已安装: $(python3 --version)"
}

# 检查 Python 版本
check_python_version() {
    print_step "检查 Python 环境..."

    if ! command -v python3 &> /dev/null; then
        print_error "未找到 Python3，请先安装 Python3"
        exit 1
    fi

    # 检查 Python 版本（需要 3.7+）
    python_version=$(python3 --version | awk '{print $2}')
    print_info "Python3 版本: $python_version"

    # 简单版本检查
    if ! python3 -c "import sys; exit(0 if sys.version_info >= (3, 7) else 1)" 2>/dev/null; then
        print_error "需要 Python 3.7 或更高版本"
        exit 1
    fi

    print_info "✅ Python 环境检查通过（无外部依赖）"
}

# 校验 cron 表达式：去首尾空格后恰好 5 段，每段仅含 0-9 * / - ,
# 返回 0=合法，1=非法
cron_expr_valid() {
    local expr="$1"
    local trimmed
    trimmed="$(printf '%s' "$expr" | sed 's/^ *//;s/ *$//')"
    [ -z "$trimmed" ] && return 1
    local field_count
    field_count=$(printf '%s\n' "$trimmed" | awk '{print NF}')
    [ "$field_count" -eq 5 ] || return 1
    local i seg
    for i in 1 2 3 4 5; do
        seg=$(printf '%s\n' "$trimmed" | awk -v n="$i" '{print $n}')
        printf '%s' "$seg" | grep -qE '^[0-9*/,-]+$' || return 1
    done
    return 0
}

# 菜单选择逻辑：从 stdin 读输入，设全局 SELECTED_CRON_EXPR
# 非法序号/非法表达式则循环重试。仅处理交互选择，不做 tty 检测。
_cron_menu_pick() {
    local presets_expr=(
        "*/10 0-23 * * *"
        "*/30 0-23 * * *"
        "*/10 0-23 * * 1-5"
        "*/30 9-18 * * 1-5"
    )
    local presets_desc=(
        "每天 0:00-23:59，每10分钟（默认）"
        "每天 0:00-23:59，每30分钟"
        "工作日 0:00-23:59，每10分钟"
        "工作日 9-18点，每30分钟"
    )

    while true; do
        echo ""
        echo "请选择 cron 执行周期："
        local idx
        for idx in 0 1 2 3; do
            printf "  %d) %s   %s\n" "$((idx+1))" "${presets_desc[$idx]}" "${presets_expr[$idx]}"
        done
        echo "  5) 自定义（手动输入 cron 表达式）"
        echo -n "请输入序号 [1]: "
        local choice
        read -r choice || true
        [ -z "$choice" ] && choice=1

        case "$choice" in
            1|2|3|4)
                SELECTED_CRON_EXPR="${presets_expr[$((choice-1))]}"
                return 0
                ;;
            5)
                while true; do
                    echo "请输入 cron 表达式（5 段：分 时 日 月 周），如 */10 0-23 * * *："
                    echo -n "cron: "
                    local custom
                    read -r custom || true
                    if cron_expr_valid "$custom"; then
                        SELECTED_CRON_EXPR="$custom"
                        return 0
                    fi
                    print_warning "格式不合法（需 5 段，仅含 0-9 * / - ,），请重新输入"
                done
                ;;
            *)
                print_warning "无效序号，请输入 1-5"
                ;;
        esac
    done
}

# 交互式选择 cron 执行周期，结果写入全局 SELECTED_CRON_EXPR
# 非交互/管道模式（stdin 非 tty）：直接用默认，不弹菜单
input_cron_schedule() {
    if [ ! -t 0 ]; then
        SELECTED_CRON_EXPR="*/10 0-23 * * *"
        return
    fi
    _cron_menu_pick
}

# 交互式输入 API Key（隐藏输入）
input_api_key() {
    while true; do
        echo ""
        echo "请输入你的智谱 API Key (按 Ctrl+C 退出):"

        # 先检查环境变量
        if [ -n "$ZHIPU_API_KEY" ]; then
            api_key_input="$ZHIPU_API_KEY"
            print_info "从环境变量读取 API Key"
        else
            # 隐藏输入（不回显），输入完成后会显示部分 Key 供确认
            echo -n "  API Key: "
            read -rs api_key_input
            echo
        fi

        if [ -z "$api_key_input" ]; then
            print_error "API Key 不能为空，请重新输入"
            continue
        fi

        # 简单验证 API Key 长度（至少10个字符）
        if [ ${#api_key_input} -lt 10 ]; then
            print_warning "API Key 长度似乎太短（${#api_key_input} 字符），请确认是否正确"
            print_info "按回车继续，或按 Ctrl+C 退出重新输入"
            read -p ""  # 等待用户确认
            continue
        fi

        # 显示部分 Key 进行确认
        echo ""
        print_info "你输入的 API Key: ${api_key_input:0:8}********************${api_key_input: -8}"
        echo ""
        print_info "按回车确认使用此 API Key，或按 Ctrl+C 退出重新输入"
        read -p ""  # 等待用户确认

        # 使用全局变量返回
        RETURN_VALUE="$api_key_input"
        return
    done
}

# 交互式输入时间
# 交互式配置向导
config_wizard() {
    print_step "配置向导"

    # 确保配置文件存在
    if [ ! -f "$INSTALL_DIR/config.json" ]; then
        print_info "未找到 config.json，开始创建配置文件..."

        # 复制默认配置（使用当前用户权限）
        if [ -f "$INSTALL_DIR/config.default.json" ]; then
            cp "$INSTALL_DIR/config.default.json" "$INSTALL_DIR/config.json"
            print_info "已从默认配置创建 config.json"
        else
            print_error "未找到 config.default.json 模板文件"
            exit 1
        fi
    fi

    echo ""
    print_info "========================================"
    print_info "  交互式配置"
    print_info "========================================"

    # 输入 API Key
    print_info "步骤 1/1: 配置 API Key"
    input_api_key
    api_key="$RETURN_VALUE"

    # 更新配置文件
    print_info "正在写入配置文件..."

    # 使用 printf 和 heredoc 生成 JSON（纯 Bash，无需 Python）
    # 转义 JSON 中的特殊字符
    escaped_api_key=$(printf '%s\n' "$api_key" | sed 's/\\/\\\\/g; s/"/\\"/g')

    cat > "$INSTALL_DIR/config.json" << EOF
{
  "api_key": "$escaped_api_key",
  "log_file": "quota_refresher.log"
}
EOF

    print_info "配置文件已更新"

    echo ""
    print_info "========================================"
    print_info "  配置摘要"
    print_info "========================================"
    print_info "API Key:        ${api_key:0:8}...${api_key: -8}"
    print_info "执行时间:       9:00-18:00，每10分钟（可在 crontab 中修改）"
    print_info "配置文件:       $INSTALL_DIR/config.json"
    print_info "========================================"
    echo ""

    print_info "✅ 配置完成（如需修改，请编辑 $INSTALL_DIR/config.json）"
}

# 检查配置文件
check_config() {
    if [ ! -f "$INSTALL_DIR/config.json" ]; then
        print_error "未找到 config.json 配置文件"
        print_info "请先运行: $0 config"
        exit 1
    fi
    print_info "配置文件检查通过"
}

# 创建 cron 定时任务
create_cron_job() {
    print_step "创建 cron 定时任务..."

    # 确保 Python 脚本有执行权限
    if [ -f "$INSTALL_DIR/${SCRIPT_NAME}" ]; then
        chmod +x "$INSTALL_DIR/${SCRIPT_NAME}" 2>/dev/null || true
    fi

    print_info "默认配置：工作日 9:00-18:00，每10分钟执行一次"

    # 创建 cron 任务：周一到周五，9-18点，每10分钟执行
    local cron_expr="*/10 9-18 * * 1-5"

    # 创建完整的 cron 命令 - 直接使用 python3 解释器执行，不依赖脚本权限
    local cron_cmd="cd $INSTALL_DIR && $PYTHON_PATH ${SCRIPT_NAME} >> $INSTALL_DIR/cron.log 2>&1"

    # 检查是否已存在相同的 cron 任务
    if crontab -l 2>/dev/null | grep -q "$INSTALL_DIR/${SCRIPT_NAME}"; then
        print_warning "检测到已存在的 cron 任务"
        read -p "是否删除旧任务并创建新任务？(y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # 删除旧任务
            crontab -l 2>/dev/null | grep -v "$INSTALL_DIR/${SCRIPT_NAME}" | crontab -
            print_info "旧任务已删除"
        else
            print_info "保留现有 cron 任务"
            return
        fi
    fi

    # 添加新的 cron 任务
    (crontab -l 2>/dev/null; echo "$cron_expr $cron_cmd") | crontab -

    print_info "✅ cron 任务创建完成"
    print_info "定时规则: 工作日 9:00-18:00，每10分钟执行"
    print_info "Cron表达式: $cron_expr"
    print_info "执行命令: $cron_cmd"
    print_info "日志文件: $INSTALL_DIR/cron.log"
    echo ""
    print_info "提示：可使用 'crontab -e' 修改执行时间"
}

# 测试执行一次（验证配置）
test_run() {
    print_step "测试执行..."

    print_info "执行一次检查，验证配置是否正确..."

    # 使用与 cron 相同的方式执行：cd 到目录 + python3 解释器
    if (cd "$INSTALL_DIR" && $PYTHON_PATH "${SCRIPT_NAME}"); then
        print_info "✅ 测试执行成功"
    else
        print_error "❌ 测试执行失败，请检查配置"
        print_info "查看日志: cat $INSTALL_DIR/quota_refresher.log"
        exit 1
    fi
}

# 创建服务（完整安装流程）
install_service() {
    print_info "========================================"
    print_info "  智谱 API 自动刷新工具 - 开始安装"
    print_info "========================================"
    echo ""

    # 第一阶段：普通用户操作（不需要 sudo）
    print_info "阶段 1/2: 准备文件（不需要 sudo 权限）"
    check_commands
    pull_from_github
    check_python_version
    config_wizard

    # 第二阶段：创建 cron 定时任务
    echo ""
    print_info "阶段 2/2: 创建 cron 定时任务"
    create_cron_job
    test_run

    echo ""
    print_info "========================================"
    print_info "  ✅ 部署完成！"
    print_info "========================================"
    print_info "仓库地址: $REPO_URL"
    print_info "安装用户: $REAL_USER"
    print_info "安装目录: $INSTALL_DIR"
    print_info ""
    print_info "常用命令："
    print_info "  查看定时任务: crontab -l"
    print_info "  查看运行日志: tail -f $INSTALL_DIR/cron.log"
    print_info "  查看程序日志: tail -f $INSTALL_DIR/quota_refresher.log"
    print_info "  手动测试: $INSTALL_DIR/${SCRIPT_NAME}"
    print_info ""
    print_info "配置文件: $INSTALL_DIR/config.json"
    print_info "程序日志: $INSTALL_DIR/quota_refresher.log"
    print_info "Cron日志: $INSTALL_DIR/cron.log"
    print_info "========================================"
}

# 更新代码
update_service() {
    print_info "========================================"
    print_info "  更新代码"
    print_info "========================================"

    # 拉取代码（不需要 sudo）
    print_info "拉取最新代码..."
    cd "$INSTALL_DIR" || {
        print_error "安装目录不存在: $INSTALL_DIR"
        exit 1
    }
    git pull

    print_info "✅ 更新完成！"
    print_info "当前版本信息："
    git log -1 --oneline
    print_info ""
    print_info "注意：cron 定时任务不会自动更新，如需修改请重新运行 install"
}

# 移除 cron 任务
remove_service() {
    print_info "========================================"
    print_info "  移除 cron 定时任务"
    print_info "========================================"

    # 检查是否存在相关 cron 任务
    if crontab -l 2>/dev/null | grep -q "$INSTALL_DIR/${SCRIPT_NAME}"; then
        print_info "检测到 cron 任务，正在删除..."

        # 删除包含脚本路径的 cron 行
        crontab -l 2>/dev/null | grep -v "$INSTALL_DIR/${SCRIPT_NAME}" | crontab -

        print_info "✅ cron 任务已删除"
    else
        print_warning "未检测到相关 cron 任务"
    fi

    # 询问是否删除代码目录
    print_warning "cron 任务已删除，安装目录仍保留: $INSTALL_DIR"
    read -p "是否同时删除代码目录？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
        print_info "代码目录已删除"
    fi

    print_info "✅ 清理完成"
}

# 查看服务状态
show_status() {
    print_info "========================================"
    print_info "  定时任务状态"
    print_info "========================================"

    if crontab -l 2>/dev/null | grep -q "$INSTALL_DIR/${SCRIPT_NAME}"; then
        print_info "✅ cron 任务已配置："
        crontab -l | grep "$INSTALL_DIR/${SCRIPT_NAME}"
        echo ""
        print_info "下次执行时间："
        print_info "  根据配置的间隔时间自动执行"
    else
        print_warning "未检测到 cron 任务"
    fi
}

# 显示日志
show_logs() {
    if [ -f "$INSTALL_DIR/cron.log" ]; then
        print_info "查看 cron 执行日志（按 Ctrl+C 退出）："
        tail -f "$INSTALL_DIR/cron.log"
    elif [ -f "$INSTALL_DIR/quota_refresher.log" ]; then
        print_info "查看程序日志（按 Ctrl+C 退出）："
        tail -f "$INSTALL_DIR/quota_refresher.log"
    else
        print_warning "未找到日志文件"
        print_info "请先运行一次: $INSTALL_DIR/${SCRIPT_NAME}"
        exit 1
    fi
}

# 编辑配置
edit_config() {
    if [ -f "$INSTALL_DIR/config.json" ]; then
        ${EDITOR:-nano} "$INSTALL_DIR/config.json"
        print_info "配置文件已更新"
        print_info "下次 cron 执行时会自动使用新配置"
    else
        print_error "配置文件不存在，请先运行: $0 install"
        exit 1
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
智谱 API 自动刷新工具 - 一键部署脚本

仓库地址: $REPO_URL
安装用户: $REAL_USER
安装目录: $INSTALL_DIR

用法: $0 [选项]

选项:
  install     完整安装（拉取代码、配置向导、创建 cron 任务）
  update      更新代码
  remove      移除 cron 任务（可选删除代码）
  status      查看定时任务状态
  logs        查看实时日志
  config      编辑配置文件
  help        显示此帮助信息

示例:
  # 首次安装
  ./$0 install

  # 更新代码
  ./$0 update

  # 查看定时任务
  ./$0 status

  # 查看日志
  ./$0 logs

  # 移除定时任务
  ./$0 remove

说明:
  - 脚本以普通用户身份运行，不需要 sudo 权限
  - 使用 cron 定时任务，按配置的间隔时间执行
  - 支持自定义刷新时间段
  - 程序日志: quota_refresher.log
  - Cron日志: cron.log


EOF
}

# 主函数
main() {
    case "${1:-help}" in
        install)
            install_service
            ;;
        update)
            update_service
            ;;
        remove)
            remove_service
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        config)
            edit_config
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
