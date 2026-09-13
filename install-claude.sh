#!/bin/bash
# Claude Code 寒霜注入器 (macOS/Linux)
# 功能：将寒霜指令集注入到 ~/.claude/CLAUDE.md 并同步技能库

set -e

CLAUDE_DIR="$HOME/.claude"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
SKILLS_DIR="$CLAUDE_DIR/skills"
BACKUP_DIR="$CLAUDE_DIR/.backup"
STATE_FILE="$CLAUDE_DIR/.hanshuang-state.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查指令集文件
PROMPT_FILE="$SCRIPT_DIR/寒霜v4-claude.md"
if [[ ! -f "$PROMPT_FILE" ]]; then
    log_error "找不到指令集文件: $PROMPT_FILE"
    exit 1
fi

# 创建必要目录
mkdir -p "$CLAUDE_DIR" "$BACKUP_DIR" "$SKILLS_DIR"

# 备份现有配置
if [[ -f "$CLAUDE_MD" ]]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/CLAUDE.md.$TIMESTAMP"
    cp "$CLAUDE_MD" "$BACKUP_FILE"
    log_info "已备份现有配置到: $BACKUP_FILE"
fi

# 写入寒霜指令集
cp "$PROMPT_FILE" "$CLAUDE_MD"
log_info "已注入寒霜指令集到: $CLAUDE_MD"

# 同步技能库
SKILLS_SOURCE="$SCRIPT_DIR/codex-skills-v4"
if [[ -d "$SKILLS_SOURCE" ]]; then
    log_info "正在同步技能库..."
    rsync -a --delete "$SKILLS_SOURCE/" "$SKILLS_DIR/"
    SKILL_COUNT=$(find "$SKILLS_DIR" -name "*.md" | wc -l | tr -d ' ')
    log_info "已同步 $SKILL_COUNT 个技能模块"
else
    log_warn "技能库目录不存在: $SKILLS_SOURCE"
fi

# 记录状态
cat > "$STATE_FILE" <<EOF
{
  "installed": true,
  "version": "v4-claude",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "prompt_file": "寒霜v4-claude.md",
  "backup": "$BACKUP_FILE"
}
EOF

log_info "✅ Claude Code 注入完成"
log_info "请在 Claude Code 中输入「寒霜」激活"
