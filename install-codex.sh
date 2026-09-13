#!/bin/bash
# Codex 寒霜注入器 (macOS/Linux)
# 功能：将寒霜指令集注入到 Codex config.toml
# 支持安装和卸载模式

set -e

CODEX_DIR="$HOME/.codex"
CONFIG_FILE="$CODEX_DIR/config.toml"
BACKUP_DIR="$CODEX_DIR/.backup"
STATE_FILE="$CODEX_DIR/.hanshuang-state.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查是否是卸载模式
UNINSTALL_MODE=false
if [[ "$1" == "--uninstall" || "$1" == "-u" ]]; then
    UNINSTALL_MODE=true
fi

if [[ "$UNINSTALL_MODE" == false ]]; then
    # 安装模式：检查指令集文件
    PROMPT_FILE="$SCRIPT_DIR/寒霜v4.md"
    if [[ ! -f "$PROMPT_FILE" ]]; then
        log_error "找不到指令集文件: $PROMPT_FILE"
        exit 1
    fi
fi

# 检查 Codex 是否安装
if [[ ! -d "$CODEX_DIR" ]]; then
    log_error "Codex 未安装或配置目录不存在: $CODEX_DIR"
    exit 1
fi

# 创建备份目录
mkdir -p "$BACKUP_DIR"

if [[ "$UNINSTALL_MODE" == true ]]; then
    # ========== 卸载模式 ==========
    log_info "开始卸载 Codex 寒霜注入..."

    # 检查是否已安装
    if [[ ! -f "$STATE_FILE" ]]; then
        log_warn "未找到安装状态文件，可能未安装"
    fi

    # 读取备份文件路径
    LATEST_BACKUP=""
    if [[ -f "$STATE_FILE" ]]; then
        LATEST_BACKUP=$(grep -o '"backup": "[^"]*"' "$STATE_FILE" | cut -d'"' -f4)
    fi

    # 如果有备份文件，恢复它
    if [[ -n "$LATEST_BACKUP" && -f "$LATEST_BACKUP" ]]; then
        cp "$LATEST_BACKUP" "$CONFIG_FILE"
        log_info "已从备份恢复配置: $LATEST_BACKUP"
    elif [[ -f "$CONFIG_FILE" ]]; then
        # 否则移除 model_instructions_file 行
        if grep -q "model_instructions_file" "$CONFIG_FILE"; then
            sed -i.bak '/model_instructions_file/d' "$CONFIG_FILE"
            rm -f "$CONFIG_FILE.bak"
            log_info "已从 config.toml 移除 model_instructions_file"
        else
            log_warn "config.toml 中未找到 model_instructions_file 配置"
        fi
    fi

    # 删除指令集文件
    PROMPT_DEST="$CODEX_DIR/hanshuang-prompt.md"
    if [[ -f "$PROMPT_DEST" ]]; then
        rm -f "$PROMPT_DEST"
        log_info "已删除指令集文件: $PROMPT_DEST"
    fi

    # 删除状态文件
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        log_info "已删除状态文件"
    fi

    log_info "✅ Codex 卸载完成"
    log_info "请重启 Codex 生效"

else
    # ========== 安装模式 ==========

    # 备份现有配置
    if [[ -f "$CONFIG_FILE" ]]; then
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        BACKUP_FILE="$BACKUP_DIR/config.toml.$TIMESTAMP"
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        log_info "已备份现有配置到: $BACKUP_FILE"
    else
        log_warn "config.toml 不存在，将创建新文件"
        BACKUP_FILE=""
    fi

    # 复制指令集到 Codex 目录
    PROMPT_DEST="$CODEX_DIR/hanshuang-prompt.md"
    cp "$PROMPT_FILE" "$PROMPT_DEST"
    log_info "已复制指令集到: $PROMPT_DEST"

    # 修改 config.toml
    if [[ -f "$CONFIG_FILE" ]]; then
        # 如果已存在 model_instructions_file，替换它
        if grep -q "model_instructions_file" "$CONFIG_FILE"; then
            sed -i.bak "s|model_instructions_file.*|model_instructions_file = \"$PROMPT_DEST\"|" "$CONFIG_FILE"
            rm -f "$CONFIG_FILE.bak"
            log_info "已更新 config.toml 中的 model_instructions_file"
        else
            # 否则添加到文件末尾
            echo "" >> "$CONFIG_FILE"
            echo "model_instructions_file = \"$PROMPT_DEST\"" >> "$CONFIG_FILE"
            log_info "已添加 model_instructions_file 到 config.toml"
        fi
    else
        # 创建新的 config.toml
        echo "model_instructions_file = \"$PROMPT_DEST\"" > "$CONFIG_FILE"
        log_info "已创建新的 config.toml"
    fi

    # 记录状态
    cat > "$STATE_FILE" <<EOF
{
  "installed": true,
  "version": "v4",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "prompt_file": "寒霜v4.md",
  "backup": "$BACKUP_FILE"
}
EOF

    log_info "✅ Codex 注入完成"
    log_info "请重启 Codex 并输入「寒霜」激活"
fi
