#!/bin/bash
# bin2linyaps.external-missing-deps-fetch 主脚本
# 分析 missing_deps 文件，搜索包名，更新 linglong.yaml，生成下载脚本
set -euo pipefail

print_usage() {
    cat <<EOF
用法: $(basename "$0") <project_dir>

分析 missing_deps 文件，搜索 apt 包名，更新 linglong.yaml，
生成 missing_deps_urls.conf 和 download_missing_deps.sh。

参数:
  project_dir   玲珑构建工程目录（包含 missing_deps.json/csv 和 linglong.yaml）
EOF
}

log_info()  { echo "[INFO]  $*" >&2; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

cleanup() {
    rm -rf "$TEMP_DIR"
}
TEMP_DIR=$(mktemp -d)
trap cleanup EXIT

# ============================================================
# 步骤1: 参数校验
# ============================================================
if [ $# -ne 1 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    print_usage
    exit 1
fi

PROJECT_DIR="$1"
if [ ! -d "$PROJECT_DIR" ]; then
    log_error "项目目录不存在: $PROJECT_DIR"
    exit 1
fi

# 转为绝对路径
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

log_info "项目目录: $PROJECT_DIR"

# ============================================================
# 步骤2: 查找缺失依赖文件
# ============================================================
MISSING_DEPS_JSON="${PROJECT_DIR}/missing_deps.json"
MISSING_DEPS_CSV="${PROJECT_DIR}/missing_deps.csv"

SO_LIST="${TEMP_DIR}/so_list.txt"
PKG_LIST="${TEMP_DIR}/pkg_list.txt"

if [ -f "$MISSING_DEPS_JSON" ]; then
    log_info "读取缺失依赖报告: missing_deps.json"
    jq -r '.[].dependency' "$MISSING_DEPS_JSON" | sort -u > "$SO_LIST"
elif [ -f "$MISSING_DEPS_CSV" ]; then
    log_info "读取缺失依赖报告: missing_deps.csv"
    awk -F',' 'NR>1{print $1}' "$MISSING_DEPS_CSV" | sort -u > "$SO_LIST"
else
    log_error "未找到 missing_deps.json 或 missing_deps.csv"
    exit 1
fi

SO_COUNT=$(wc -l < "$SO_LIST")
log_info "提取到 $SO_COUNT 个唯一的 .so 依赖"

if [ "$SO_COUNT" -eq 0 ]; then
    log_info "没有缺失依赖，无需处理"
    exit 0
fi

# ============================================================
# 步骤3: apt-file 搜索包名 (并行)
# ============================================================
log_info "开始通过 apt-file 搜索包名..."

search_package() {
    local so_name="$1"
    local result
    result=$(apt-file search -x "/${so_name}$" 2>/dev/null | cut -d: -f1 | sort -u || true)
    if [ -n "$result" ]; then
        echo "$result"
    else
        log_warn "未找到提供 $so_name 的包"
    fi
}
export -f search_package log_warn

# 并行搜索
cat "$SO_LIST" | xargs -P "$(nproc)" -I{} bash -c 'search_package "$@"' _ {} | sort -u > "$PKG_LIST"

PKG_COUNT=$(wc -l < "$PKG_LIST")
log_info "搜索到 $PKG_COUNT 个相关包名"

if [ "$PKG_COUNT" -eq 0 ]; then
    log_info "没有搜索到任何包名，无需更新"
    exit 0
fi

# ============================================================
# 步骤4: 更新 linglong.yaml
# ============================================================
YAML_FILE="${PROJECT_DIR}/linglong.yaml"
if [ ! -f "$YAML_FILE" ]; then
    log_error "未找到 linglong.yaml"
    exit 1
fi

log_info "更新 linglong.yaml 的 buildext.apt.depends..."

update_yaml_depends() {
    local yaml_file="$1"
    local new_pkgs_file="$2"

    python3 -c "
import sys

yaml_file = '$yaml_file'
new_pkgs_file = '$new_pkgs_file'

# 用 safe_load 只读, 获取已有 depends 判断新包
try:
    from ruamel.yaml import YAML
    ry = YAML()
    ry.preserve_quotes = True
    with open(yaml_file, 'r') as f:
        data = ry.load(f)
except ImportError:
    import yaml as _yaml
    with open(yaml_file, 'r') as f:
        data = _yaml.safe_load(f)

existing = set()
for dep in data.get('buildext', {}).get('apt', {}).get('depends', []) or []:
    if dep:
        existing.add(dep)

new_pkgs = []
with open(new_pkgs_file, 'r') as f:
    for line in f:
        line = line.strip()
        if line and line not in existing:
            new_pkgs.append(line)
            existing.add(line)

if not new_pkgs:
    print('NO_NEW_PKGS')
    sys.exit(0)

# ---- 文本级追加: 在下一个顶层 key 前插入 ----
with open(yaml_file, 'r') as f:
    lines = f.readlines()

# 定位 buildext.apt.depends 行
depends_line_idx = None
for i, line in enumerate(lines):
    stripped = line.strip()
    if stripped == 'depends:':
        leading = line[:len(line) - len(line.lstrip())]
        if len(leading) >= 4:
            for k in range(i - 1, max(i - 100, -1), -1):
                if lines[k].strip() == 'buildext:':
                    depends_line_idx = i
                    break
            if depends_line_idx is not None:
                break

if depends_line_idx is None:
    # 降级: 找不到则用 ruamel 追加
    try:
        from ruamel.yaml import YAML
        ry = YAML()
        ry.preserve_quotes = True
        with open(yaml_file, 'r') as f:
            data = ry.load(f)
        data.setdefault('buildext', {}).setdefault('apt', {}).setdefault('depends', [])
        data['buildext']['apt']['depends'].extend(new_pkgs)
        with open(yaml_file, 'w') as f:
            ry.dump(data, f)
    except:
        print('NO_NEW_PKGS')
        sys.exit(0)
else:
    # 找到下一个顶层 key 所在行号
    next_key_idx = len(lines)
    for j in range(depends_line_idx + 1, len(lines)):
        stripped = lines[j].rstrip()
        if stripped and not stripped.startswith(' ') and not stripped.startswith('#'):
            next_key_idx = j
            break
    # 从后往前找到最后一个非空 depends 行，清除其与 next_key 之间的空行
    last_depends_idx = next_key_idx - 1
    while last_depends_idx > depends_line_idx and not lines[last_depends_idx].strip():
        last_depends_idx -= 1
    # 动态获取缩进: 使用 depends 条目的缩进
    last_line = lines[last_depends_idx]
    pkg_indent = last_line[:len(last_line) - len(last_line.lstrip())]
    # 构造新行
    new_lines = [f'{pkg_indent}- {pkg}\n' for pkg in new_pkgs]
    # 删除 depends 末尾到下一 key 之间的空行
    del lines[last_depends_idx + 1:next_key_idx]
    # 插入新行
    insert_at = last_depends_idx + 1
    for i, nl in enumerate(new_lines):
        lines.insert(insert_at + i, nl)
    with open(yaml_file, 'w') as f:
        f.writelines(lines)

print('\\n'.join(new_pkgs))
" 2>&1 || return 0
}

run_update() {
    local result
    result=$(update_yaml_depends "$YAML_FILE" "$PKG_LIST")

    if [ "$result" = "NO_NEW_PKGS" ]; then
        log_info "所有包名已存在于 depends 中，无需更新"
        echo 0
        return
    fi

    if [ -z "$result" ]; then
        echo 0
        return
    fi

    local count
    count=$(echo "$result" | wc -l)
    log_info "新增 $count 个包到 buildext.apt.depends:"
    echo "$result" | while IFS= read -r pkg; do
        log_info "  + $pkg"
    done

    echo "$result" > "$TEMP_DIR/new_pkgs_for_url.txt"
    echo "$count"
}

HAS_NEW_PKGS=$(run_update)

# ============================================================
# 步骤5: 获取下载 URL
# ============================================================
if [ $HAS_NEW_PKGS -ne 0 ]; then
    URL_FILE="${TEMP_DIR}/urls.txt"
    log_info "获取新包的下载 URL..."

    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        url=$(apt-get download --print-uris "$pkg" 2>/dev/null | awk -F"'" '{print $2}' || true)
        if [ -n "$url" ]; then
            echo "$url" >> "$URL_FILE"
        else
            log_warn "无法获取 $pkg 的下载 URL"
        fi
    done < "$TEMP_DIR/new_pkgs_for_url.txt"

    # 去重 URL
    if [ -f "$URL_FILE" ]; then
        sort -u "$URL_FILE" -o "$URL_FILE"
        URL_COUNT=$(wc -l < "$URL_FILE")
        log_info "获取到 $URL_COUNT 个 deb 下载 URL"
    else
        URL_COUNT=0
        log_warn "未能获取任何下载 URL"
    fi
else
    URL_COUNT=0
fi

# ============================================================
# 步骤6: 生成 missing_deps_urls.conf + download_missing_deps.sh
# ============================================================
CONF_FILE="${PROJECT_DIR}/missing_deps_urls.conf"

if [ $URL_COUNT -gt 0 ]; then
    log_info "生成 missing_deps_urls.conf..."

    cat > "$CONF_FILE" <<CONF_EOF
# 由 bin2linyaps.external-missing-deps-fetch 自动生成
# 位于 $(basename "$PROJECT_DIR")/
# 可人工编辑：增删改 URL 行后重新运行 download_missing_deps.sh 即可
MISSING_DEPS_URLS=(
$(awk '{print "  \"" $0 "\""}' "$URL_FILE")
)
CONF_EOF

    log_info "生成: $CONF_FILE"
else
    log_info "未获取到 URL，跳过生成配置文件"
fi

DOWNLOAD_SCRIPT="${PROJECT_DIR}/download_missing_deps.sh"
log_info "生成 download_missing_deps.sh..."

cat > "$DOWNLOAD_SCRIPT" <<SCRIPT_EOF
#!/bin/bash
# 由 bin2linyaps.external-missing-deps-fetch 自动生成
# 通用下载解压脚本，从同目录的 missing_deps_urls.conf 读取 URL
# 用法: ./download_missing_deps.sh [binary_dir 路径]
set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
BINARY_DIR="\${1:-\${SCRIPT_DIR}/binary_dir}"

if [ ! -f "\${SCRIPT_DIR}/missing_deps_urls.conf" ]; then
  echo "ERROR: missing_deps_urls.conf not found in \${SCRIPT_DIR}"
  exit 1
fi

source "\${SCRIPT_DIR}/missing_deps_urls.conf"

if [ \${#MISSING_DEPS_URLS[@]} -eq 0 ]; then
  echo "INFO: 没有需要下载的依赖包"
  exit 0
fi

DEB_CACHE="/tmp/lingyaps-debs"
mkdir -p "\$BINARY_DIR" "\$DEB_CACHE"

for url in "\${MISSING_DEPS_URLS[@]}"; do
  deb_file="\$DEB_CACHE/\$(basename "\$url")"
  echo "下载: \$url"
  wget -q "\$url" -O "\$deb_file"
  echo "解压: \$deb_file → \$BINARY_DIR"
  dpkg -x "\$deb_file" "\$BINARY_DIR"
  rm -f "\$deb_file"
done

echo "完成: 已下载并解压 \${#MISSING_DEPS_URLS[@]} 个依赖包到 \$BINARY_DIR"
SCRIPT_EOF

chmod +x "$DOWNLOAD_SCRIPT"
log_info "生成: $DOWNLOAD_SCRIPT"

# ============================================================
# 步骤7: 输出摘要
# ============================================================
echo ""
echo "========================================"
echo "外部缺失依赖获取报告"
echo "========================================"
echo "项目目录:      $PROJECT_DIR"
echo "缺失 so 数量:  $SO_COUNT"
echo "搜索到包名数:  $PKG_COUNT"
echo "新增到 depends: $HAS_NEW_PKGS"
echo "下载 URL 数:   $URL_COUNT"
echo ""
echo "生成文件:"
echo "  更新: $YAML_FILE"
if [ -f "$CONF_FILE" ]; then
    echo "  生成: $CONF_FILE"
fi
echo "  生成: $DOWNLOAD_SCRIPT"
echo ""
echo "下一步:"
if [ $URL_COUNT -gt 0 ]; then
    echo "  1. (可选) 编辑 $CONF_FILE 增删 URL"
    echo "  2. 运行 cd $PROJECT_DIR && ./download_missing_deps.sh"
fi
echo "========================================"