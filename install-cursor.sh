#!/bin/bash
# install-cursor.sh — Cursor 破甲：全局规则 + 项目规则 一键装/卸 (macOS)
#
# 注入点：
#   1) ~/.cursor/rules/寒霜注入.mdc           全局规则（主路径）
#   2) <project>/.cursorrules                 项目级规则（遍历工作区）
#
# 用法：
#   ./install-cursor.sh                       # 一键注入
#   ./install-cursor.sh --uninstall           # 一键还原

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 参数
SOURCE_PROMPT=""
UNINSTALL=false
STATUS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --source-prompt)
            SOURCE_PROMPT="$2"
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
RULE_FILE="寒霜注入.mdc"
LEGACY_RULE_FILE=".cursorrules"
MARKER="<!-- HANSHUANG-CURSOR-INJECT -->"

# 查找 Cursor 规则目录候选
get_rules_candidates() {
    local candidates=()

    # 主路径：~/.cursor/rules
    candidates+=("$HOME/.cursor/rules")

    # 备用路径
    candidates+=("$HOME/Library/Application Support/Cursor/User/rules")
    candidates+=("$HOME/Library/Application Support/Cursor/rules")

    printf '%s\n' "${candidates[@]}"
}

# 查找 Cursor 项目
get_cursor_projects() {
    local ws_root="$HOME/Library/Application Support/Cursor/User/workspaceStorage"

    if [[ ! -d "$ws_root" ]]; then
        return 0
    fi

    local projects=()

    for wdir in "$ws_root"/*; do
        if [[ ! -d "$wdir" ]]; then
            continue
        fi

        local ws_json="$wdir/workspace.json"
        if [[ ! -f "$ws_json" ]]; then
            continue
        fi

        # 解析 workspace.json
        local loc=$(python3 -c "
import json, sys, urllib.parse
try:
    with open('$ws_json', 'r') as f:
        data = json.load(f)
    loc = data.get('folder') or data.get('workspace')
    if loc:
        if loc.startswith('file://'):
            loc = loc[7:]
        loc = urllib.parse.unquote(loc)
        print(loc)
except:
    pass
" 2>/dev/null)

        if [[ -n "$loc" ]] && [[ -d "$loc" ]]; then
            projects+=("$loc")
        fi
    done

    printf '%s\n' "${projects[@]}" | sort -u
}

# 获取提示词文件
get_prompt_file() {
    if [[ -n "$SOURCE_PROMPT" ]] && [[ -f "$SOURCE_PROMPT" ]]; then
        echo "$SOURCE_PROMPT"
        return 0
    fi

    local candidates=(
        "$SCRIPT_DIR/寒霜v4.md"
        "$SCRIPT_DIR/寒霜v3.md"
        "$SCRIPT_DIR/寒霜v1.2.md"
    )

    for file in "${candidates[@]}"; do
        if [[ -f "$file" ]]; then
            echo "$file"
            return 0
        fi
    done

    echo -e "${RED}[错误] 未找到提示词文件${NC}" >&2
    return 1
}

# 注入全局规则
inject_global_rule() {
    local prompt_file="$1"

    echo -e "${GREEN}[注入] 正在注入全局规则...${NC}"

    local candidates=($(get_rules_candidates))
    local injected=false

    for rules_dir in "${candidates[@]}"; do
        mkdir -p "$rules_dir"

        local target="$rules_dir/$RULE_FILE"

        # 创建规则文件
        {
            echo "$MARKER"
            cat "$prompt_file"
        } > "$target"

        chmod 644 "$target"
        echo -e "${GREEN}  ✓ 全局规则已注入: $target${NC}"
        injected=true
        break
    done

    if [[ "$injected" == false ]]; then
        echo -e "${RED}[错误] 无法找到 Cursor 规则目录${NC}"
        return 1
    fi
}

# 注入项目规则
inject_project_rules() {
    local prompt_file="$1"

    echo -e "${GREEN}[注入] 正在注入项目规则...${NC}"

    local projects=($(get_cursor_projects))

    if [[ ${#projects[@]} -eq 0 ]]; then
        echo -e "${YELLOW}  [提示] 未找到 Cursor 项目工作区${NC}"
        return 0
    fi

    local count=0
    for project in "${projects[@]}"; do
        local cursorrules="$project/$LEGACY_RULE_FILE"

        # 备份现有规则
        if [[ -f "$cursorrules" ]]; then
            if ! grep -q "$MARKER" "$cursorrules" 2>/dev/null; then
                cp "$cursorrules" "$cursorrules.bak"
            fi
        fi

        # 注入规则
        {
            echo "$MARKER"
            cat "$prompt_file"
        } > "$cursorrules"

        chmod 644 "$cursorrules"
        ((count++))
    done

    echo -e "${GREEN}  ✓ 已注入 $count 个项目${NC}"
}

# 卸载
uninstall() {
    echo -e "${YELLOW}[卸载] 正在还原...${NC}"

    # 删除全局规则
    local candidates=($(get_rules_candidates))
    for rules_dir in "${candidates[@]}"; do
        local target="$rules_dir/$RULE_FILE"
        if [[ -f "$target" ]]; then
            rm -f "$target"
            echo -e "${GREEN}  ✓ 已删除: $target${NC}"
        fi
    done

    # 删除项目规则
    local projects=($(get_cursor_projects))
    local count=0

    for project in "${projects[@]}"; do
        local cursorrules="$project/$LEGACY_RULE_FILE"

        if [[ -f "$cursorrules" ]] && grep -q "$MARKER" "$cursorrules" 2>/dev/null; then
            # 恢复备份
            if [[ -f "$cursorrules.bak" ]]; then
                mv "$cursorrules.bak" "$cursorrules"
            else
                rm -f "$cursorrules"
            fi
            ((count++))
        fi
    done

    echo -e "${GREEN}  ✓ 已还原 $count 个项目${NC}"
    echo -e "${GREEN}[完成] 卸载完成${NC}"
}

# 显示状态
show_status() {
    echo -e "${GREEN}=== Cursor 状态 ===${NC}"
    echo ""

    # 检查全局规则
    echo "全局规则："
    local candidates=($(get_rules_candidates))
    local found=false

    for rules_dir in "${candidates[@]}"; do
        local target="$rules_dir/$RULE_FILE"
        if [[ -f "$target" ]]; then
            echo -e "${GREEN}  ✓ $target${NC}"
            ls -lh "$target"
            found=true
        fi
    done

    if [[ "$found" == false ]]; then
        echo -e "${RED}  ✗ 未注入${NC}"
    fi

    echo ""
    echo "项目规则："

    local projects=($(get_cursor_projects))

    if [[ ${#projects[@]} -eq 0 ]]; then
        echo "  (未找到项目)"
    else
        local injected=0
        for project in "${projects[@]}"; do
            local cursorrules="$project/$LEGACY_RULE_FILE"
            if [[ -f "$cursorrules" ]] && grep -q "$MARKER" "$cursorrules" 2>/dev/null; then
                echo -e "${GREEN}  ✓ $project${NC}"
                ((injected++))
            fi
        done

        echo ""
        echo "已注入: $injected / ${#projects[@]} 个项目"
    fi
}

# 主逻辑
main() {
    echo -e "${GREEN}=== Cursor 破甲工具 (macOS) ===${NC}"
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
    local prompt_file
    prompt_file=$(get_prompt_file) || exit 1
    echo -e "${GREEN}提示词文件: $prompt_file${NC}"
    echo ""

    inject_global_rule "$prompt_file"
    inject_project_rules "$prompt_file"

    echo ""
    echo -e "${GREEN}=== 注入完成 ===${NC}"
    echo -e "${YELLOW}请重启 Cursor 使更改生效${NC}"
}

main "$@"
