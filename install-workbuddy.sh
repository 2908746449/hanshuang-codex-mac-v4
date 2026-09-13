#!/bin/bash
# install-workbuddy.sh — WorkBuddy AI 破甲：全局记忆 + 文件记忆 + skills 一键装/卸 (macOS)
#
# 注入点：
#   1) <ConfigDir>/memory/<uid>_memory.md          账号级云记忆档案
#   2) <ConfigDir>/MEMORY.md                       用户级文件记忆
#   3) <ConfigDir>/app/app-config.json             generateMemoryEnabled/localMemoryEnabled
#   4) <ConfigDir>/skills/<name>/SKILL.md          用户级 Skills
#
# 用法：
#   ./install-workbuddy.sh                         # 一键：寒霜V4 + V4 技能库
#   ./install-workbuddy.sh /path/to/寒霜v4.md [codex-skills-v4] # GUI 传递方式
#   ./install-workbuddy.sh --uninstall             # 一键还原
#   ./install-workbuddy.sh --status                # 只读状态

set -e

# 颜色输出
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

# 默认参数
VERSION="v4"
SOURCE_PROMPT=""
SKILLS_SOURCE="codex-skills-v4"
NO_SKILLS=false
KILL_APP=false
RESTART=false
UNINSTALL=false
STATUS=false
CONFIG_DIR=""
TARGET_USER_ID=""

# 解析命令行参数（同时支持位置参数与命名字段）
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --source-prompt)
            SOURCE_PROMPT="$2"
            shift 2
            ;;
        --skills-source)
            SKILLS_SOURCE="$2"
            shift 2
            ;;
        --config-dir)
            CONFIG_DIR="$2"
            shift 2
            ;;
        --uid)
            TARGET_USER_ID="$2"
            shift 2
            ;;
        --no-skills)
            NO_SKILLS=true
            shift
            ;;
        --kill-app)
            KILL_APP=true
            shift
            ;;
        --restart)
            RESTART=true
            shift
            ;;
        --uninstall|-u)
            UNINSTALL=true
            shift
            ;;
        --status)
            STATUS=true
            shift
            ;;
        *)
            if [[ -z "$SOURCE_PROMPT" && ! "$1" =~ ^- ]]; then
                SOURCE_PROMPT="$1"
                shift
            elif [[ -n "$SOURCE_PROMPT" && ! "$1" =~ ^- ]]; then
                SKILLS_SOURCE="$1"
                shift
            else
                echo -e "${RED}未知参数: $1${NC}"
                exit 1
            fi
            ;;
    esac
done

# 脚本根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 查找 WorkBuddy 配置目录
find_workbuddy_config() {
    if [[ -n "$CONFIG_DIR" ]] && [[ -d "$CONFIG_DIR" ]]; then
        echo "$CONFIG_DIR"
        return 0
    fi

    # macOS 路径检测优先级
    local candidates=(
        "$HOME/.workbuddy-ai"
        "$HOME/.workbuddy"
        "$HOME/Library/Application Support/WorkBuddy"
    )

    for dir in "${candidates[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "$dir"
            return 0
        fi
    done

    echo "$HOME/.workbuddy-ai"
    return 0
}

# 查找用户 UID 档案
find_user_uids() {
    local config_dir="$1"
    local uids=()

    if [[ -n "$TARGET_USER_ID" ]]; then
        echo "$TARGET_USER_ID"
        return 0
    fi

    local memory_dir="$config_dir/memory"
    if [[ -d "$memory_dir" ]]; then
        for f in "$memory_dir"/*_memory.md; do
            if [[ -f "$f" && ! "$f" =~ \.bak ]]; then
                local bname=$(basename "$f")
                local u="${bname%_memory.md}"
                if [[ -n "$u" && "$u" != "*" ]]; then
                    uids+=("$u")
                fi
            fi
        done
    fi

    if [[ ${#uids[@]} -gt 0 ]]; then
        printf "%s\n" "${uids[@]}"
        return 0
    fi

    # 从 settings.json 中解析 legacyOwnerUid
    local settings_file="$config_dir/settings.json"
    if [[ -f "$settings_file" ]]; then
        local uid_from_json=$(python3 -c "
import json
try:
    with open('$settings_file', 'r', encoding='utf-8') as f:
        d = json.load(f)
    print(d.get('claw', {}).get('legacyOwnerUid', ''))
except Exception:
    pass
" 2>/dev/null || true)
        if [[ -n "$uid_from_json" ]]; then
            echo "$uid_from_json"
            return 0
        fi
    fi

    return 1
}

# 确定提示词文件
get_prompt_file() {
    if [[ -n "$SOURCE_PROMPT" ]] && [[ -f "$SOURCE_PROMPT" ]]; then
        echo "$SOURCE_PROMPT"
        return 0
    fi

    local candidates=(
        "$SCRIPT_DIR/寒霜${VERSION}.md"
        "$SCRIPT_DIR/寒霜v4.md"
        "$SCRIPT_DIR/寒霜v3.md"
        "$SCRIPT_DIR/寒霜v1.2.md"
    )

    for f in "${candidates[@]}"; do
        if [[ -f "$f" ]]; then
            echo "$f"
            return 0
        fi
    done

    echo -e "${RED}[错误] 未找到提示词文件${NC}" >&2
    return 1
}

# 结束 WorkBuddy 进程
kill_workbuddy() {
    echo -e "${YELLOW}[操作] 结束 WorkBuddy 进程...${NC}"
    pkill -f "WorkBuddy" 2>/dev/null || true
    sleep 1
}

# 启动 WorkBuddy
start_workbuddy() {
    echo -e "${GREEN}[操作] 启动 WorkBuddy...${NC}"
    open -a "WorkBuddy" 2>/dev/null || open -a "WorkBuddy AI" 2>/dev/null || echo -e "${YELLOW}[提示] 请手动启动 WorkBuddy${NC}"
}

# 注入记忆
inject_memory() {
    local config_dir="$1"
    local prompt_file="$2"
    shift 2
    local uids=("$@")

    echo -e "${GREEN}[注入] 正在注入记忆...${NC}"

    local prompt_content
    prompt_content=$(cat "$prompt_file")
    local now_iso
    now_iso=$(python3 -c "import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z'))")

    # 1. 注入云记忆档案
    local memory_dir="$config_dir/memory"
    mkdir -p "$memory_dir"

    if [[ ${#uids[@]} -gt 0 ]]; then
        for u in "${uids[@]}"; do
            [[ -z "$u" ]] && continue
            local cloud_memory_file="$memory_dir/${u}_memory.md"
            local bak_file="${cloud_memory_file}.bak-inject"

            # 备份原文件
            if [[ -f "$cloud_memory_file" && ! -f "$bak_file" ]]; then
                cp "$cloud_memory_file" "$bak_file"
            fi

            # 解除只读属性
            chmod +w "$cloud_memory_file" 2>/dev/null || true

            # 生成标准的 RAW_JSON 结构
            python3 -c "
import json, sys

uid = sys.argv[1]
prompt_file = sys.argv[2]
out_file = sys.argv[3]
now_iso = sys.argv[4]

with open(prompt_file, 'r', encoding='utf-8') as f:
    text = f.read()

profile = {
    'uid': uid,
    'memoryBlock': text,
    'updatedAt': now_iso,
    'version': 999999
}

raw_json = json.dumps(profile, ensure_ascii=False, indent=2)
content = f'''# User Memory Profile
> Last updated: {now_iso}
> Version: 999999

## Memory Block

{text}

---

<!-- RAW_JSON_START
{raw_json}
RAW_JSON_END -->
'''

with open(out_file, 'w', encoding='utf-8') as f:
    f.write(content)
" "$u" "$prompt_file" "$cloud_memory_file" "$now_iso"

            # 加只读锁防被程序回写覆盖
            chmod 444 "$cloud_memory_file"
            echo -e "${GREEN}  ✓ 云记忆档案已注入 (${u}): $cloud_memory_file (Version: 999999, 已设只读)${NC}"
        done
    else
        echo -e "${YELLOW}  [提示] 未发现现有云记忆档案，将在 WorkBuddy 登录产生记忆时由守护线程自动补注入${NC}"
    fi

    # 2. 注入用户级文件记忆 MEMORY.md
    local file_memory="$config_dir/MEMORY.md"
    local file_memory_bak="${file_memory}.bak-inject"
    if [[ -f "$file_memory" && ! -f "$file_memory_bak" ]]; then
        cp "$file_memory" "$file_memory_bak"
    fi
    cp "$prompt_file" "$file_memory"
    echo -e "${GREEN}  ✓ 文件记忆已注入: $file_memory${NC}"

    # 3. 更新 app-config.json 中的记忆开关
    local app_config="$config_dir/app/app-config.json"
    mkdir -p "$(dirname "$app_config")"
    local app_config_bak="${app_config}.bak-inject"
    if [[ -f "$app_config" && ! -f "$app_config_bak" ]]; then
        cp "$app_config" "$app_config_bak"
    fi

    python3 -c "
import json, os

cfg_path = '$app_config'
cfg = {}
if os.path.exists(cfg_path):
    try:
        with open(cfg_path, 'r', encoding='utf-8') as f:
            cfg = json.load(f)
    except Exception:
        cfg = {}

cfg['generateMemoryEnabled'] = True
cfg['localMemoryEnabled'] = True
if 'locale' not in cfg:
    cfg['locale'] = 'zh-CN'

with open(cfg_path, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
"
    echo -e "${GREEN}  ✓ 记忆开关已开启: generateMemoryEnabled=true, localMemoryEnabled=true${NC}"
}

# 安装技能
install_skills() {
    local config_dir="$1"
    local skills_source="$2"

    if [[ "$NO_SKILLS" == true ]]; then
        echo -e "${YELLOW}[跳过] 不安装技能 (--no-skills)${NC}"
        return 0
    fi

    local source_dir="$SCRIPT_DIR/$skills_source"
    if [[ ! -d "$source_dir" ]]; then
        if [[ -d "$SCRIPT_DIR/codex-skills-v4" ]]; then
            source_dir="$SCRIPT_DIR/codex-skills-v4"
        elif [[ -d "$SCRIPT_DIR/codex-skills" ]]; then
            source_dir="$SCRIPT_DIR/codex-skills"
        else
            echo -e "${YELLOW}[警告] 技能目录不存在: $source_dir${NC}"
            return 0
        fi
    fi

    echo -e "${GREEN}[安装] 正在安装技能...${NC}"

    local target_dir="$config_dir/skills"
    mkdir -p "$target_dir"

    # 复制所有技能
    rsync -a --delete "$source_dir/" "$target_dir/"

    local skill_count=$(find "$target_dir" -name "SKILL.md" 2>/dev/null | wc -l | tr -d " ")
    echo -e "${GREEN}  ✓ 已安装 $skill_count 个技能到: $target_dir${NC}"

    # 创建技能清单
    local manifest="$target_dir/.hanshuang-skills.json"
    python3 -c "
import json, os, hashlib, datetime, glob

skills_dir = '$target_dir'
manifest_file = '$manifest'
src_name = '$skills_source'

skills = {}
for skill_md in glob.glob(os.path.join(skills_dir, '*', 'SKILL.md')):
    name = os.path.basename(os.path.dirname(skill_md))
    with open(skill_md, 'rb') as f:
        sha = hashlib.sha256(f.read()).hexdigest()
    skills[name] = {'sha256': sha}

data = {
    'source': src_name,
    'installedAt': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z'),
    'skill_count': len(skills),
    'skills': skills
}

with open(manifest_file, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
"

    # 清除 settings.json 中的 skillOverrides 禁用项
    local settings_file="$config_dir/settings.json"
    if [[ -f "$settings_file" ]]; then
        python3 -c "
import json, os

st_file = '$settings_file'
try:
    with open(st_file, 'r', encoding='utf-8') as f:
        d = json.load(f)
    if 'skillOverrides' in d:
        del d['skillOverrides']
        with open(st_file, 'w', encoding='utf-8') as f:
            json.dump(d, f, ensure_ascii=False, indent=2)
except Exception:
    pass
"
    fi
}

# 记录状态文件（供守护进程比对）
record_state() {
    local config_dir="$1"
    local prompt_file="$2"
    local skills_source="$3"
    local state_file="$config_dir/.hanshuang-state.json"

    python3 -c "
import json, os, hashlib, datetime

config_dir = '$config_dir'
prompt_file = '$prompt_file'
state_file = '$state_file'

with open(prompt_file, 'rb') as f:
    sha = hashlib.sha256(f.read()).hexdigest()

mem_dir = os.path.join(config_dir, 'memory')
archives = []
if os.path.isdir(mem_dir):
    for n in os.listdir(mem_dir):
        if n.endswith('_memory.md') and '.bak' not in n:
            archives.append(os.path.join(mem_dir, n))

state = {
    'prompt': os.path.basename(prompt_file),
    'promptSha256': sha,
    'configDir': config_dir,
    'memoryDir': mem_dir,
    'archives': archives,
    'archive': archives[0] if archives else '',
    'memoryFile': os.path.join(config_dir, 'MEMORY.md'),
    'appConfig': os.path.join(config_dir, 'app', 'app-config.json'),
    'version': 999999,
    'installedAt': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z')
}

with open(state_file, 'w', encoding='utf-8') as f:
    json.dump(state, f, ensure_ascii=False, indent=2)
"
    echo -e "${GREEN}  ✓ 注入状态已记录: $state_file${NC}"
}

# 卸载
uninstall() {
    local config_dir="$1"

    echo -e "${YELLOW}[卸载] 正在还原 WorkBuddy...${NC}"

    # 1. 还原云记忆档案
    local memory_dir="$config_dir/memory"
    if [[ -d "$memory_dir" ]]; then
        for af in "$memory_dir"/*_memory.md; do
            if [[ -f "$af" ]]; then
                chmod +w "$af" 2>/dev/null || true
                local bak="${af}.bak-inject"
                if [[ -f "$bak" ]]; then
                    mv "$bak" "$af"
                    echo -e "${GREEN}  ✓ 档案已从备份还原: $(basename "$af")${NC}"
                else
                    local uid=$(basename "$af" | sed 's/_memory\.md$//')
                    local now_iso=$(python3 -c "import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z'))")
                    cat > "$af" << EOF
# User Memory Profile
> Last updated: $now_iso
> Version: 999999

## Memory Block



---

<!-- RAW_JSON_START
{
  "uid": "$uid",
  "memoryBlock": "",
  "updatedAt": "$now_iso",
  "version": 999999
}
RAW_JSON_END -->
EOF
                    echo -e "${GREEN}  ✓ 档案 memoryBlock 已清空: $(basename "$af")${NC}"
                fi
            fi
        done
    fi

    # 2. 还原 MEMORY.md
    local file_mem="$config_dir/MEMORY.md"
    local file_mem_bak="${file_mem}.bak-inject"
    if [[ -f "$file_mem_bak" ]]; then
        mv "$file_mem_bak" "$file_mem"
        echo -e "${GREEN}  ✓ MEMORY.md 已从备份还原${NC}"
    elif [[ -f "$file_mem" ]]; then
        rm -f "$file_mem"
        echo -e "${GREEN}  ✓ MEMORY.md 已删除${NC}"
    fi

    # 3. 还原 app-config.json
    local app_config="$config_dir/app/app-config.json"
    local app_config_bak="${app_config}.bak-inject"
    if [[ -f "$app_config_bak" ]]; then
        mv "$app_config_bak" "$app_config"
        echo -e "${GREEN}  ✓ app-config.json 已从备份还原${NC}"
    elif [[ -f "$app_config" ]]; then
        python3 -c "
import json, os
p = '$app_config'
if os.path.exists(p):
    try:
        with open(p, 'r') as f: d = json.load(f)
        d['generateMemoryEnabled'] = False
        d['localMemoryEnabled'] = False
        with open(p, 'w') as f: json.dump(d, f, indent=2)
    except Exception: pass
" 2>/dev/null || true
        echo -e "${GREEN}  ✓ app-config.json 记忆开关已关闭${NC}"
    fi

    # 4. 删除技能
    local skills_dir="$config_dir/skills"
    local manifest="$skills_dir/.hanshuang-skills.json"
    if [[ -f "$manifest" ]]; then
        rm -rf "$skills_dir"
        echo -e "${GREEN}  ✓ 技能目录已移除${NC}"
    fi

    # 5. 删除状态文件
    rm -f "$config_dir/.hanshuang-state.json"

    echo -e "${GREEN}  ✓ 卸载完成${NC}"
}

# 显示状态
show_status() {
    local config_dir="$1"

    echo -e "${CYAN}=== WorkBuddy 状态 ===${NC}"
    echo "配置目录: $config_dir"
    echo ""

    local memory_dir="$config_dir/memory"
    if ls "$memory_dir"/*_memory.md 1> /dev/null 2>&1; then
        echo -e "${GREEN}✓ 云记忆档案已存在：${NC}"
        ls -lh "$memory_dir"/*_memory.md
    else
        echo -e "${YELLOW}✗ 未检测到云记忆档案${NC}"
    fi

    if [[ -f "$config_dir/MEMORY.md" ]]; then
        echo -e "${GREEN}✓ MEMORY.md 存在 ($(wc -c < "$config_dir/MEMORY.md" | tr -d " ") bytes)${NC}"
    else
        echo -e "${RED}✗ MEMORY.md 不存在${NC}"
    fi

    local app_config="$config_dir/app/app-config.json"
    if [[ -f "$app_config" ]]; then
        echo -e "${GREEN}✓ app-config.json:${NC}"
        cat "$app_config"
    else
        echo -e "${RED}✗ app-config.json 不存在${NC}"
    fi

    local skills_dir="$config_dir/skills"
    if [[ -d "$skills_dir" ]]; then
        local count=$(find "$skills_dir" -name "SKILL.md" 2>/dev/null | wc -l | tr -d " ")
        echo -e "${GREEN}✓ 已安装 $count 个技能${NC}"
    else
        echo -e "${RED}✗ 未安装技能${NC}"
    fi
}

main() {
    echo -e "${CYAN}== WorkBuddy 破甲 (macOS) ==${NC}"

    local config_dir
    config_dir=$(find_workbuddy_config)
    echo -e "配置目录: ${CYAN}$config_dir${NC}"

    if [[ "$STATUS" == true ]]; then
        show_status "$config_dir"
        exit 0
    fi

    if [[ "$UNINSTALL" == true ]]; then
        if [[ "$KILL_APP" == true ]]; then
            kill_workbuddy
        fi
        uninstall "$config_dir"
        if [[ "$RESTART" == true ]]; then
            start_workbuddy
        fi
        exit 0
    fi

    if [[ "$KILL_APP" == true ]]; then
        kill_workbuddy
    fi

    local prompt_file
    prompt_file=$(get_prompt_file) || exit 1
    echo -e "提示词文件: ${CYAN}$prompt_file${NC}"

    local uids_output
    uids_output=$(find_user_uids "$config_dir" || true)
    local uids=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && uids+=("$line")
    done <<< "$uids_output"

    inject_memory "$config_dir" "$prompt_file" "${uids[@]}"
    install_skills "$config_dir" "$SKILLS_SOURCE"
    record_state "$config_dir" "$prompt_file" "$SKILLS_SOURCE"

    echo ""
    echo -e "${GREEN}=== WorkBuddy 破甲注入成功 ===${NC}"
    if [[ "$RESTART" == true ]]; then
        start_workbuddy
    else
        echo -e "${YELLOW}请完全重启 WorkBuddy 使更改生效${NC}"
    fi
}

main "$@"
