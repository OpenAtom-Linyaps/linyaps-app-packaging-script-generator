#!/bin/bash
# bin2linyaps.external-missing-deps-fetch
# 静态下载解压脚本，由 pak_linyaps.sh 在构建时调用
# 解析项目根目录下的 missing_deps_urls.conf，下载并解压 deb 到 binary_dir
# 不依赖 fetch_missing_deps.sh 是否执行过，支持用户手动创建 conf
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF_FILE="${PROJECT_ROOT}/missing_deps_urls.conf"
BINARY_DIR="${1:-${PROJECT_ROOT}/binary_dir}"

if [ ! -f "$CONF_FILE" ]; then
  echo "INFO: 未找到 missing_deps_urls.conf，无需下载" >&2
  exit 0
fi

# source 前临时关闭 set -u，避免 conf 未定义数组时中断
set +u
source "$CONF_FILE"
set -u

if [ ${#MISSING_DEPS_URLS[@]} -eq 0 ]; then
  echo "INFO: 没有需要下载的依赖包" >&2
  exit 0
fi

# URL 解码（构建环境支持 python3 原生 urllib.parse.unquote）：
# 将 basename 中的 %2b/%20 等百分号编码还原为实际字符，得到干净缓存文件名
url_decode() {
  python3 -c 'import urllib.parse,sys;print(urllib.parse.unquote(sys.argv[1]))' "$1"
}

DEB_CACHE="/tmp/lingyaps-debs"
mkdir -p "$BINARY_DIR" "$DEB_CACHE"

FAIL_COUNT=0
for url in "${MISSING_DEPS_URLS[@]}"; do
  deb_file="$DEB_CACHE/$(url_decode "$(basename "$url")")"
  echo "下载: $url"
  if ! wget -q --tries=3 "$url" -O "$deb_file"; then
    echo "WARN: 下载失败: $url" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi
  # 校验下载内容确为 deb，拦截返回 200 的 HTML 错误页
  if ! dpkg-deb -I "$deb_file" >/dev/null 2>&1; then
    echo "WARN: 下载内容非有效 deb（可能为错误页）: $url" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    rm -f "$deb_file"
    continue
  fi
  echo "解压: $deb_file"
  EXTRACT_DIR=$(mktemp -d)
  # dpkg 缺失时回退 dpkg-deb -x
  if command -v dpkg >/dev/null 2>&1; then
    dpkg -x "$deb_file" "$EXTRACT_DIR"
  else
    dpkg-deb -x "$deb_file" "$EXTRACT_DIR"
  fi
  if [ $? -ne 0 ]; then
    echo "WARN: 解压失败: $deb_file" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    rm -f "$deb_file"
    rm -rf "$EXTRACT_DIR"
    continue
  fi
  # 复制解压出的全部顶层目录（usr、lib、etc、opt、sbin、bin、share、var 等）。
  # 修复：部分 multiarch 老包（如 libpng12）将共享库放在顶层 lib/<multiarch>/，
  # 而非 usr/ 下，仅复制 usr/ 会丢弃真正的 .so。
  for entry in "$EXTRACT_DIR"/*; do
    [ -e "$entry" ] || continue
    if ! cp -rf "$entry" "$BINARY_DIR/"; then
      echo "WARN: 复制失败: $entry -> $BINARY_DIR/" >&2
      FAIL_COUNT=$((FAIL_COUNT + 1))
      break
    fi
  done
  rm -rf "$EXTRACT_DIR"
  rm -f "$deb_file"
done

TOTAL=${#MISSING_DEPS_URLS[@]}
SUCCESS=$((TOTAL - FAIL_COUNT))
echo "完成: 成功 $SUCCESS/$TOTAL 个依赖包已解压到 $BINARY_DIR"
[ "$FAIL_COUNT" -eq 0 ] || echo "WARN: $FAIL_COUNT 个包处理失败" >&2
