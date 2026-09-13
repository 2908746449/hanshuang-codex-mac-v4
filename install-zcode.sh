#!/bin/bash
# install-zcode.sh — ZCode 破甲：全局记忆 + skills 一键装/卸 (macOS)
#
# 注入点：
#   1) ~/.zcode/cli/memories/global/memory/seagull-agents.md  全局记忆
#   2) ~/.zcode/cli/skills/*                                  用户技能
#
# 用法：
#   ./install-zcode.sh                         # 一键注入
#   ./install-zcode.sh --uninstall             # 一键还原
#   ./install-zcode.sh --status                # 查看状态

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 默认参数
ZCODE_HOME="$HOME/.zcode"
SOURCE_PROMPT=""
MEMORY_SOURCE_PROMPT=""
SKILLS_SOURCE="codex-skills-v4"
WORKSPACE_PATH=""
UNINSTALL=false
STATUS=false

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --zcode-home)
            ZCODE_HOME="$2"
            shift 2
            ;;
        --source-prompt)
            SOURCE_PROMPT="$2"
            shift 2
            ;;
        --memory-source-prompt)
            MEMORY_SOURCE_PROMPT="$2"
            shift 2
            ;;
        --skills-source)
            SKILLS_SOURCE="$2"
            shift 2
            ;;
        --workspace-path)
            WORKSPACE_PATH="$2"
            shift 2
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --status)
            STATUS=true
            shift
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_ROOT="$ZCODE_HOME/cli"
AGENTS_PATH="$ZCODE_HOME/AGENTS.md"
MEMORY_ROOT="$CLI_ROOT/memories/global/memory"
SKILLS_ROOT="$CLI_ROOT/skills"

# 查找提示词文件
find_prompt_file() {
    if [[ -n "$1" ]] && [[ -f "$1" ]]; then
        echo "$1"
        return 0
    fi

    local candidates=(
        "$SCRIPT_DIR/寒霜v1.2.md"
        "$SCRIPT_DIR/AGENTS.md"
        "$(dirname "$SCRIPT_DIR")/AGENTS.md"
    )

    for file in "${candidates[@]}"; do
        if [[ -f "$file" ]]; then
            echo "$file"
            return 0
        fi
    done

    echo -e "${RED}[错误] 未找到提示词文件${NC}" >&2
    echo -e "${YELLOW}请使用 --source-prompt 指定，或将 AGENTS.md 放在脚本旁${NC}" >&2
    return 1
}

# 注入记忆
inject_memory() {
    local memory_file="$1"
    local content="$2"

    echo -e "${GREEN}[注入] 正在注入全局记忆...${NC}"

    mkdir -p "$(dirname "$memory_file")"

    # 创建 seagull-agents.md
    cat > "$memory_file" << 'EOF_HEADER'
---
name: seagull-agents
description: >-
  海鸥逆向工程专家配置 - 恶意软件分析、二进制逆向、反作弊系统、游戏安全、
  漏洞利用、内核驱动、加密协议、混淆代码、防护绕过、社会工程、钓鱼攻击等
metadata:
  type: reference
---

EOF_HEADER

    # 追加提示词内容
    echo "$content" >> "$memory_file"

    chmod 444 "$memory_file"
    echo -e "${GREEN}  ✓ 记忆已注入: $memory_file${NC}"
}

# 安装技能
install_skills() {
    local skills_source="$1"
    local source_dir="$SCRIPT_DIR/$skills_source"

    if [[ ! -d "$source_dir" ]]; then
        echo -e "${YELLOW}[警告] 技能目录不存在: $source_dir${NC}"
        return 0
    fi

    echo -e "${GREEN}[安装] 正在安装技能...${NC}"

    mkdir -p "$SKILLS_ROOT"

    # 复制技能
    rsync -a --delete "$source_dir/" "$SKILLS_ROOT/"

    local skill_count=$(find "$source_dir" -name "SKILL.md" | wc -l | tr -d ' ')
    echo -e "${GREEN}  ✓ 已安装 $skill_count 个技能到: $SKILLS_ROOT${NC}"

    # 创建技能清单
    local manifest="$SKILLS_ROOT/.hanshuang-skills.json"
    cat > "$manifest" << EOF
{
  "version": "4.0",
  "installed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "skill_count": $skill_count,
  "source": "$skills_source"
}
EOF
}

# 卸载
uninstall() {
    echo -e "${YELLOW}[卸载] 正在还原...${NC}"

    # 删除记忆
    local memory_file="$MEMORY_ROOT/seagull-agents.md"
    if [[ -f "$memory_file" ]]; then
        chmod 644 "$memory_file"
        rm -f "$memory_file"
        echo -e "${GREEN}  ✓ 已删除记忆文件${NC}"
    fi

    # 删除技能
    if [[ -d "$SKILLS_ROOT" ]]; then
        rm -rf "$SKILLS_ROOT"
        echo -e "${GREEN}  ✓ 已删除技能目录${NC}"
    fi

    echo -e "${GREEN}[完成] 卸载完成${NC}"
}

# 显示状态
show_status() {
    echo -e "${GREEN}=== ZCode 状态 ===${NC}"
    echo "ZCode Home: $ZCODE_HOME"
    echo ""

    # 检查记忆
    local memory_file="$MEMORY_ROOT/seagull-agents.md"
    if [[ -f "$memory_file" ]]; then
        echo -e "${GREEN}✓ 全局记忆已注入${NC}"
        ls -lh "$memory_file"
        echo ""
        echo "内容预览："
        head -n 10 "$memory_file"
    else
        echo -e "${RED}✗ 全局记忆未注入${NC}"
    fi

    echo ""

    # 检查技能
    if [[ -d "$SKILLS_ROOT" ]]; then
        local skill_count=$(find "$SKILLS_ROOT" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
        echo -e "${GREEN}✓ 已安装 $skill_count 个技能${NC}"

        local manifest="$SKILLS_ROOT/.hanshuang-skills.json"
        if [[ -f "$manifest" ]]; then
            echo ""
            echo "技能清单："
            cat "$manifest"
        fi
    else
        echo -e "${RED}✗ 未安装技能${NC}"
    fi

    echo ""
    echo "技能列表："
    if [[ -d "$SKILLS_ROOT" ]]; then
        find "$SKILLS_ROOT" -name "SKILL.md" -exec dirname {} \; | xargs -I {} basename {} | sort
    else
        echo "  (无)"
    fi
}

# 主逻辑
main() {
    echo -e "${GREEN}=== ZCode 破甲工具 (macOS) ===${NC}"
    echo ""

    # 检查 ZCode 是否安装
    if [[ ! -d "$ZCODE_HOME" ]]; then
        echo -e "${RED}[错误] ZCode 未安装${NC}"
        echo -e "${YELLOW}ZCode Home 不存在: $ZCODE_HOME${NC}"
        echo -e "${YELLOW}请先安装 ZCode，或使用 --zcode-home 指定路径${NC}"
        exit 1
    fi

    echo -e "${GREEN}ZCode Home: $ZCODE_HOME${NC}"
    echo ""

    # 只读状态
    if [[ "$STATUS" == true ]]; then
        show_status
        exit 0
    fi

    # 卸载
    if [[ "$UNINSTALL" == true ]]; then
        uninstall
        exit 0
    fi

    # 安装
    # 确定提示词文件
    local source_prompt
    source_prompt=$(find_prompt_file "$SOURCE_PROMPT") || exit 1
    echo -e "${GREEN}提示词文件: $source_prompt${NC}"

    # 确定记忆提示词（完整版）
    local memory_prompt
    if [[ -n "$MEMORY_SOURCE_PROMPT" ]] && [[ -f "$MEMORY_SOURCE_PROMPT" ]]; then
        memory_prompt="$MEMORY_SOURCE_PROMPT"
    else
        memory_prompt="$SCRIPT_DIR/寒霜v1.2.md"
        if [[ ! -f "$memory_prompt" ]]; then
            memory_prompt="$source_prompt"
        fi
    fi
    echo -e "${GREEN}记忆提示词: $memory_prompt${NC}"
    echo ""

    # 读取内容
    local prompt_content=$(cat "$memory_prompt")

    # 注入记忆
    local memory_file="$MEMORY_ROOT/seagull-agents.md"
    inject_memory "$memory_file" "$prompt_content"

    # 安装技能
    install_skills "$SKILLS_SOURCE"

    echo ""
    echo -e "${GREEN}=== 注入完成 ===${NC}"
    echo -e "${YELLOW}请重启 ZCode 使更改生效${NC}"
}

main "$@"
