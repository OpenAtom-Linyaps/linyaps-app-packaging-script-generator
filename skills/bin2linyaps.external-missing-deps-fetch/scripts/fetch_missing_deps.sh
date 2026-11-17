#!/bin/bash
# bin2linyaps.external-missing-deps-fetch
# 分析 missing_deps 文件，搜索包名，更新 templates/linglong.yaml（模板），生成下载脚本
# 约束：
#   - 只修改 <project_dir>/templates/linglong.yaml（保留 envsubst 变量的源模板）
#   - 绝不修改 build_tmp_dir 中的任何文件（envsubst 后的瞬态副本）
#   - missing_deps.* 由 ll-builder build 在 build_tmp_dir 中生成
set -euo pipefail

print_usage() {
    cat <<EOF
用法: $(basename "$0") --project-dir=<project_dir> [--build-tmp-dir=<build_tmp_dir>]

分析 missing_deps 文件，搜索 apt 包名，更新 templates/linglong.yaml，
生成 missing_deps_urls.conf 和 download_missing_deps.sh。

参数:
  --project-dir=<dir>     玲珑构建工程目录（CI_ll_xxx），必填
  --build-tmp-dir=<dir>   构建临时目录（ll-builder 执行目录），可选
                          未指定时搜索 <project_dir>/missing_deps.*
EOF
}

log_info()  { echo "[INFO]  $*" >&2; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

cleanup() { rm -rf "$TEMP_DIR"; }
TEMP_DIR=$(mktemp -d)
trap cleanup EXIT

PROJECT_DIR=""
BUILD_TMP_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir=*) PROJECT_DIR="${1#*=}"; shift ;;
        --build-tmp-dir=*) BUILD_TMP_DIR="${1#*=}"; shift ;;
        --help|-h) print_usage; exit 0 ;;
        *) log_error "未知参数: $1"; print_usage; exit 1 ;;
    esac
done

if [ -z "$PROJECT_DIR" ]; then
    log_error "缺少 --project-dir 参数"; print_usage; exit 1
fi
if [ ! -d "$PROJECT_DIR" ]; then
    log_error "项目目录不存在: $PROJECT_DIR"; exit 1
fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

if [ -n "$BUILD_TMP_DIR" ]; then
    if [ ! -d "$BUILD_TMP_DIR" ]; then
        log_warn "构建临时目录不存在: $BUILD_TMP_DIR，将仅搜索项目目录"
        BUILD_TMP_DIR=""
    else
        BUILD_TMP_DIR="$(cd "$BUILD_TMP_DIR" && pwd)"
    fi
fi

log_info "项目目录:       $PROJECT_DIR"
log_info "构建临时目录:    ${BUILD_TMP_DIR:-未指定}"

SO_LIST="${TEMP_DIR}/so_list.txt"
PKG_LIST="${TEMP_DIR}/pkg_list.txt"
MISSING_DEPS_FILE=""

# 优先 build_tmp_dir（ll-builder 的产物）
if [ -n "$BUILD_TMP_DIR" ]; then
    if [ -f "${BUILD_TMP_DIR}/missing_deps.json" ]; then
        MISSING_DEPS_FILE="${BUILD_TMP_DIR}/missing_deps.json"
    elif [ -f "${BUILD_TMP_DIR}/missing_deps.csv" ]; then
        MISSING_DEPS_FILE="${BUILD_TMP_DIR}/missing_deps.csv"
    fi
fi

# 回退 project_dir
if [ -z "$MISSING_DEPS_FILE" ]; then
    if [ -f "${PROJECT_DIR}/missing_deps.json" ]; then
        MISSING_DEPS_FILE="${PROJECT_DIR}/missing_deps.json"
    elif [ -f "${PROJECT_DIR}/missing_deps.csv" ]; then
        MISSING_DEPS_FILE="${PROJECT_DIR}/missing_deps.csv"
    fi
fi

if [ -z "$MISSING_DEPS_FILE" ]; then
    log_info "未找到 missing_deps 文件，无需处理"; exit 0
fi

log_info "读取缺失依赖报告: $MISSING_DEPS_FILE"

case "$MISSING_DEPS_FILE" in
    *.json) jq -r '.[].dependency' "$MISSING_DEPS_FILE" 2>/dev/null | sort -u > "$SO_LIST" ;;
    *.csv)  awk -F',' 'NR>1{print $1}' "$MISSING_DEPS_FILE" 2>/dev/null | sort -u > "$SO_LIST" ;;
esac

SO_COUNT=$(wc -l < "$SO_LIST")
log_info "提取到 $SO_COUNT 个唯一的 .so 依赖"
[ "$SO_COUNT" -eq 0 ] && { log_info "没有缺失依赖，无需处理"; exit 0; }

log_info "开始通过 apt-file 搜索包名..."
search_package() {
    local so_name="$1"
    local result
    result=$(apt-file search -x "/${so_name}$" 2>/dev/null | cut -d: -f1 | sort -u || true)
    [ -n "$result" ] && echo "$result" || log_warn "未找到提供 $so_name 的包"
}
export -f search_package log_warn
cat "$SO_LIST" | xargs -P "$(nproc)" -I{} bash -c 'search_package "$@"' _ {} | sort -u > "$PKG_LIST"

PKG_COUNT=$(wc -l < "$PKG_LIST")
log_info "搜索到 $PKG_COUNT 个相关包名"
[ "$PKG_COUNT" -eq 0 ] && { log_info "没有搜索到任何包名，无需更新"; exit 0; }

# ==== 关键：只修改 templates/linglong.yaml（源模板），不碰 build_tmp 中的副本 ====
YAML_FILE="${PROJECT_DIR}/templates/linglong.yaml"
if [ ! -f "$YAML_FILE" ]; then
    log_error "未找到 templates/linglong.yaml（模板文件）: $YAML_FILE"
    log_error "目标必须是 templates/linglong.yaml（含 ${ll_version} 等 envsubst 变量）"
    exit 1
fi
log_info "更新模板文件: $YAML_FILE"

python3 -c "
import sys
from ruamel.yaml import YAML
ry = YAML()
ry.preserve_quotes = True
ry.width = 4096

with open('${YAML_FILE}') as f:
    data = ry.load(f)

existing = set()
for dep in data.get('buildext', {}).get('apt', {}).get('depends', []) or []:
    if dep: existing.add(dep)

new_pkgs = []
with open('${PKG_LIST}') as f:
    for line in f:
        line = line.strip()
        if line and line not in existing:
            new_pkgs.append(line)
            existing.add(line)

if not new_pkgs:
    print('NO_NEW_PKGS')
    sys.exit(0)

data.setdefault('buildext', {}).setdefault('apt', {}).setdefault('depends', [])
data['buildext']['apt']['depends'].extend(new_pkgs)

with open('${YAML_FILE}', 'w') as f:
    ry.dump(data, f)

print('\n'.join(new_pkgs))
" > "${TEMP_DIR}/update_result.txt" 2>&1 || true

UPDATE_RESULT=$(cat "${TEMP_DIR}/update_result.txt")
if [ "$UPDATE_RESULT" = "NO_NEW_PKGS" ]; then
    log_info "所有包名已存在于 depends 中，无需更新"
    HAS_NEW_PKGS=0
elif [ -z "$UPDATE_RESULT" ]; then
    HAS_NEW_PKGS=0
else
    HAS_NEW_PKGS=$(echo "$UPDATE_RESULT" | wc -l)
    log_info "新增 $HAS_NEW_PKGS 个包到 buildext.apt.depends:"
    echo "$UPDATE_RESULT" | while IFS= read -r pkg; do log_info "  + $pkg"; done
    echo "$UPDATE_RESULT" > "${TEMP_DIR}/new_pkgs_for_url.txt"
fi

# ==== 获取下载 URL ====
URL_COUNT=0
if [ "${HAS_NEW_PKGS:-0}" -ne 0 ] && [ -f "${TEMP_DIR}/new_pkgs_for_url.txt" ]; then
    URL_FILE="${TEMP_DIR}/urls.txt"
    log_info "获取新包的下载 URL..."
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        url=$(apt-get download --print-uris "$pkg" 2>/dev/null | awk -F"'" '{print $2}' || true)
        [ -n "$url" ] && echo "$url" >> "$URL_FILE" || log_warn "无法获取 $pkg 的下载 URL"
    done < "${TEMP_DIR}/new_pkgs_for_url.txt"
    if [ -f "$URL_FILE" ]; then
        sort -u "$URL_FILE" -o "$URL_FILE"
        URL_COUNT=$(wc -l < "$URL_FILE")
        log_info "获取到 $URL_COUNT 个 deb 下载 URL"
    fi
fi

# ==== 生成 missing_deps_urls.conf + download_missing_deps.sh（到 project_dir 根目录）====
CONF_FILE="${PROJECT_DIR}/missing_deps_urls.conf"
if [ "$URL_COUNT" -gt 0 ]; then
    log_info "生成 missing_deps_urls.conf..."
    {
        echo "# 由 bin2linyaps.external-missing-deps-fetch 自动生成"
        echo "# 位于 $(basename "$PROJECT_DIR")/，与 pak_linyaps.sh 同级"
        echo "# 可人工编辑：增删改 URL 行后重新运行 download_missing_deps.sh 即可"
        echo "MISSING_DEPS_URLS=("
        awk '{print "  \"" $0 "\""}' "$URL_FILE"
        echo ")"
    } > "$CONF_FILE"
    log_info "生成: $CONF_FILE"
fi

# download_missing_deps.sh 已改为静态脚本，不再由 fetch_missing_deps.sh 生成
# 静态版本位于 scripts/download_missing_deps.sh，由项目初始化时 cp 到项目 scripts/ 目录

# ==== 输出摘要 ====
echo ""
echo "========================================"
echo "外部缺失依赖获取报告"
echo "========================================"
echo "项目目录:        $PROJECT_DIR"
echo "缺失依赖来源:    ${MISSING_DEPS_FILE:-无}"
echo "缺失 so 数量:    $SO_COUNT"
echo "搜索到包名数:    $PKG_COUNT"
echo "新增到 depends:  ${HAS_NEW_PKGS:-0}"
echo "下载 URL 数:     $URL_COUNT"
echo ""
echo "生成/更新文件（均在项目目录内）:"
echo "  更新: $YAML_FILE              <- 保留 envsubst 变量的源模板"
[ -f "$CONF_FILE" ] && echo "  生成: $CONF_FILE"
echo "注意: 下载解压脚本由静态 scripts/download_missing_deps.sh 提供（项目初始化时已复制）"
echo "注意: 只修改了 templates/linglong.yaml（源模板），未修改 build_tmp_dir 中的任何文件"
echo "========================================"
