#!/bin/bash
# bin2linyaps.compat-testing 前置检测脚本
# 用法: validate_projects.sh --task-file=<task.json> [options]
# 检查项目目录完整性: pak_linyaps.sh, linglong.yaml, desktop, icons

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $*" >&2; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

TASK_FILE=""
PKG_NAME=""
PROJECTS_ROOT=""
OUTPUT_FILE=""

show_help() {
    cat <<'HELP'
bin2linyaps.compat-testing 前置检测脚本

用法:
  ./validate_projects.sh --task-file=<task.json> [options]
  ./validate_projects.sh --pkg-name=<names> --projects-root=<path> [options]

必要参数（至少指定一个）:
  --task-file=<file>    任务 JSON 文件路径
  --pkg-name=<names>    逗号分隔的包名列表

选项:
  --projects-root=<path>  项目根目录
  --output=<file.json>    结果输出文件路径（JSON 格式）
  --help                  显示此说明

退出码:
  0  — 全部通过
  1  — 存在失败

检查项:
  - 项目目录存在（CI_ll_<pkgName> / <pkgName> / 模糊匹配）
  - pak_linyaps.sh 存在且可执行
  - linglong.yaml 存在
  - templates/files_res/share/applications/*.desktop ≥ 1
  - templates/files_res/share/icons/hicolor/ 结构合规
HELP
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --task-file=*)    TASK_FILE="${1#*=}"; shift ;;
        --pkg-name=*)     PKG_NAME="${1#*=}"; shift ;;
        --projects-root=*) PROJECTS_ROOT="${1#*=}"; shift ;;
        --output=*)       OUTPUT_FILE="${1#*=}"; shift ;;
        --help)           show_help ;;
        *)                log_err "未知参数: $1"; show_help ;;
    esac
done

if [[ -z "$TASK_FILE" && -z "$PKG_NAME" ]]; then
    log_err "至少需要指定一个参数: --task-file 或 --pkg-name"
    show_help
fi

if [[ -n "$TASK_FILE" && ! -f "$TASK_FILE" ]]; then
    log_err "任务文件不存在: $TASK_FILE"
    exit 1
fi

declare -a ALL_PKG_NAMES=()
CLI_PROJECTS_ROOT=""
JSON_PROJECTS_ROOT=""

if [[ -n "$TASK_FILE" ]]; then
    PARSE_RESULT=$(python3 -c "
import json, sys
with open('${TASK_FILE}') as f:
    data = json.load(f)
g = data.get('global', {})
projects_root = g.get('projects_root', '') or ''
tasks = data.get('tasks', [])
print('JSON_PROJECTS_ROOT=' + json.dumps(projects_root))
print('JSON_TASK_COUNT=' + str(len(tasks)))
for i, t in enumerate(tasks):
    print(f'TASK_{i}_PKGNAME=' + json.dumps(t.get('pkgName', '')))
" 2>/dev/null) || { log_err "JSON 解析失败"; exit 1; }

    eval "$PARSE_RESULT"
    JSON_PROJECTS_ROOT="${JSON_PROJECTS_ROOT//\"/}"

    for ((i = 0; i < JSON_TASK_COUNT; i++)); do
        pkg_var="TASK_${i}_PKGNAME"
        pkg_name="${!pkg_var}"
        pkg_name="${pkg_name//\"/}"
        [[ -n "$pkg_name" ]] && ALL_PKG_NAMES+=("$pkg_name")
    done
    log_info "从 JSON 读取到 $JSON_TASK_COUNT 个包名"
fi

if [[ -n "$PKG_NAME" ]]; then
    IFS=',' read -ra CLI_PKGS <<< "$PKG_NAME"
    for pkg in "${CLI_PKGS[@]}"; do
        pkg="$(echo "$pkg" | xargs)"
        [[ -n "$pkg" ]] && ALL_PKG_NAMES+=("$pkg")
    done
    log_info "从 --pkg-name 读取到 ${#CLI_PKGS[@]} 个包名"
fi

TASK_COUNT="${#ALL_PKG_NAMES[@]}"
if [[ $TASK_COUNT -eq 0 ]]; then
    log_err "未读取到任何有效的包名"
    exit 1
fi

if [[ -n "$PROJECTS_ROOT" ]]; then
    : # use CLI value
elif [[ -n "$JSON_PROJECTS_ROOT" ]]; then
    PROJECTS_ROOT="$JSON_PROJECTS_ROOT"
fi

if [[ -z "$PROJECTS_ROOT" ]]; then
    log_err "未指定 projects-root"
    exit 1
fi

PROJECTS_ROOT="$(cd "$PROJECTS_ROOT" 2>/dev/null && pwd)" || {
    log_err "项目根目录不存在: $PROJECTS_ROOT"
    exit 1
}

log_info "项目根目录: $PROJECTS_ROOT"
log_info "任务数量:   $TASK_COUNT"
echo ""

find_project_dir() {
    local pkg_name="$1"
    local root="$2"
    local candidate="$root/CI_ll_${pkg_name}"
    if [[ -d "$candidate" && -f "$candidate/pak_linyaps.sh" ]]; then
        echo "$candidate"; return
    fi
    candidate="$root/$pkg_name"
    if [[ -d "$candidate" && -f "$candidate/pak_linyaps.sh" ]]; then
        echo "$candidate"; return
    fi
    local found
    found=$(find "$root" -maxdepth 2 -type d -name "*${pkg_name}*" 2>/dev/null | head -1)
    if [[ -n "$found" && -f "$found/pak_linyaps.sh" ]]; then
        echo "$found"; return
    fi
    return 1
}

check_icon_structure() {
    local icons_dir="$1"
    if [[ ! -d "$icons_dir" ]]; then
        echo "missing_icons_dir"
        return
    fi
    local has_valid=0
    while IFS= read -r -d '' icon; do
        has_valid=1
        break
    done < <(find "$icons_dir" -type f \( -name "*.png" -o -name "*.svg" -o -name "*.svgz" -o -name "*.xpm" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.tiff" -o -name "*.tif" -o -name "*.gif" -o -name "*.bmp" -o -name "*.ico" -o -name "*.xbm" \) 2>/dev/null -print0)
    if [[ $has_valid -eq 0 ]]; then
        echo "no_icon_files"
    else
        echo "ok"
    fi
}

declare -a STATUSES=()
declare -a DIRS=()
declare -a MESSAGES=()
PASS_COUNT=0
FAIL_COUNT=0

for pkg_name in "${ALL_PKG_NAMES[@]}"; do
    project_dir=$(find_project_dir "$pkg_name" "$PROJECTS_ROOT") || true

    if [[ -z "$project_dir" ]]; then
        STATUSES+=("NOT_FOUND")
        DIRS+=("")
        MESSAGES+=("项目目录不存在")
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # 检查 pak_linyaps.sh
    if [[ ! -f "$project_dir/pak_linyaps.sh" ]]; then
        STATUSES+=("FAIL")
        DIRS+=("$project_dir")
        MESSAGES+=("缺少 pak_linyaps.sh")
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    if [[ ! -x "$project_dir/pak_linyaps.sh" ]]; then
        chmod +x "$project_dir/pak_linyaps.sh"
    fi

    # 检查 linglong.yaml
    if [[ ! -f "$project_dir/linglong.yaml" ]]; then
        STATUSES+=("FAIL")
        DIRS+=("$project_dir")
        MESSAGES+=("缺少 linglong.yaml")
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # 检查 desktop 文件
    desktop_count=0
    desktop_dir="$project_dir/templates/files_res/share/applications"
    if [[ -d "$desktop_dir" ]]; then
        desktop_count=$(find "$desktop_dir" -name "*.desktop" -type f 2>/dev/null | wc -l)
    fi
    if [[ $desktop_count -lt 1 ]]; then
        STATUSES+=("FAIL")
        DIRS+=("$project_dir")
        MESSAGES+=("缺少 desktop 文件 (找到 $desktop_count 个)")
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # 检查图标目录结构
    local icons_dir="$project_dir/templates/files_res/share/icons/hicolor"
    local icon_status
    icon_status=$(check_icon_structure "$icons_dir")
    if [[ "$icon_status" != "ok" ]]; then
        log_warn "图标目录检查: $pkg_name — $icon_status (非致命)"
    fi

    STATUSES+=("PASS")
    DIRS+=("$project_dir")
    MESSAGES+=("通过")
    PASS_COUNT=$((PASS_COUNT + 1))
done

# --- 输出结果 ---
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          bin2linyaps 前置检测结果                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

printf "%-10s | %-35s | %-50s | %s\n" "状态" "包名" "项目目录" "说明"
printf "%s\n" "──────────────────────────────────────────────────────────────────────────────────────────────────"

for ((i = 0; i < TASK_COUNT; i++)); do
    pkg="${ALL_PKG_NAMES[$i]}"
    status="${STATUSES[$i]}"
    dir="${DIRS[$i]}"
    msg="${MESSAGES[$i]}"
    case "$status" in
        PASS)      printf "${GREEN}PASS${NC}      | %-35s | %-50s | %s\n" "$pkg" "$dir" "✓" ;;
        FAIL)      printf "${RED}FAIL${NC}      | %-35s | %-50s | %s\n" "$pkg" "$dir" "✗ $msg" ;;
        NOT_FOUND) printf "${YELLOW}NOT_FOUND${NC} | %-35s | %-50s | %s\n" "$pkg" "-" "✗ $msg" ;;
    esac
done

echo ""
echo "总计: $TASK_COUNT | 通过: $PASS_COUNT | 失败: $FAIL_COUNT"

if [[ -n "$OUTPUT_FILE" ]]; then
    json_results="["
    for ((i = 0; i < TASK_COUNT; i++)); do
        [[ $i -gt 0 ]] && json_results+=","
        pkg="${ALL_PKG_NAMES[$i]}"
        status="${STATUSES[$i]}"
        dir="${DIRS[$i]}"
        msg="${MESSAGES[$i]}"
        json_results+="{\"pkgName\":\"${pkg}\",\"status\":\"${status}\",\"project_dir\":\"${dir}\",\"message\":\"${msg}\"}"
    done
    json_results+="]"
    timestamp=$(date +"%Y-%m-%dT%H:%M:%S%z")
    python3 -c "
import json
result = {
    'validated_at': '${timestamp}',
    'projects_root': '${PROJECTS_ROOT}',
    'summary': {'total': ${TASK_COUNT}, 'passed': ${PASS_COUNT}, 'failed': ${FAIL_COUNT}},
    'results': ${json_results}
}
with open('${OUTPUT_FILE}', 'w') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
" 2>/dev/null || log_warn "JSON 结果文件写入失败: $OUTPUT_FILE"
    log_info "结果已写入: $OUTPUT_FILE"
fi

echo ""
if [[ $FAIL_COUNT -eq 0 ]]; then
    log_ok "所有项目前置检测通过！"
    exit 0
else
    log_err "存在 $FAIL_COUNT 个检测未通过的项目"
    exit 1
fi
