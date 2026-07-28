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

source "$CONF_FILE"

if [ ${#MISSING_DEPS_URLS[@]} -eq 0 ]; then
  echo "INFO: 没有需要下载的依赖包" >&2
  exit 0
fi

DEB_CACHE="/tmp/lingyaps-debs"
mkdir -p "$BINARY_DIR" "$DEB_CACHE"

FAIL_COUNT=0
for url in "${MISSING_DEPS_URLS[@]}"; do
  deb_file="$DEB_CACHE/$(basename "$url")"
  echo "下载: $url"
  if ! wget -q "$url" -O "$deb_file"; then
    echo "WARN: 下载失败: $url" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi
  echo "解压: $deb_file"
  EXTRACT_DIR=$(mktemp -d)
  if ! dpkg -x "$deb_file" "$EXTRACT_DIR"; then
    echo "WARN: 解压失败: $deb_file" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    rm -f "$deb_file"
    rm -rf "$EXTRACT_DIR"
    continue
  fi
  if [ -d "$EXTRACT_DIR/usr" ]; then
    for subdir in "$EXTRACT_DIR/usr/"*; do
      [ -e "$subdir" ] || continue
      if ! cp -rf "$subdir" "$BINARY_DIR/"; then
        echo "WARN: 复制失败: $subdir -> $BINARY_DIR/" >&2
        FAIL_COUNT=$((FAIL_COUNT + 1))
        break
      fi
    done
  fi
  rm -rf "$EXTRACT_DIR"
  rm -f "$deb_file"
done

TOTAL=${#MISSING_DEPS_URLS[@]}
SUCCESS=$((TOTAL - FAIL_COUNT))
echo "完成: 成功 $SUCCESS/$TOTAL 个依赖包已解压到 $BINARY_DIR"
[ "$FAIL_COUNT" -eq 0 ] || echo "WARN: $FAIL_COUNT 个包处理失败" >&2