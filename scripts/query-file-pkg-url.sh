#!/bin/bash
# query-file-pkg-url.sh — 查询任意文件所属 deb 包名及下载 URL
# 输入：文件名或路径（如 libcairo.so.2 或 /usr/lib/x86_64-linux-gnu/libcairo.so.2）
# 输出：包名  下载URL
set -euo pipefail

usage() {
    cat <<EOF
用法: $(basename "$0") <文件名或路径>

查询任意文件所属 deb 包名及完整下载 URL。

示例:
  $(basename "$0") libcairo.so.2
  $(basename "$0") /usr/lib/x86_64-linux-gnu/libcairo.so.2
  $(basename "$0") /usr/share/fonts/truetype/DejaVuSans.ttf
EOF
}

[ $# -eq 0 ] && { usage; exit 1; }
[[ "$1" == "-h" || "$1" == "--help" ]] && { usage; exit 0; }

file=$(basename "$1")

# apt-file 反向查找（不依赖本地安装，查询远程仓库索引）
pkg=$(apt-file search -x "/${file}$" 2>/dev/null | cut -d: -f1 | sort -u)

if [ -z "$pkg" ]; then
    echo "[ERROR] 未找到包含文件 '$file' 的软件包" >&2
    exit 1
fi

# 获取 deb 下载 URL
url=$(apt-get download --print-uris "$pkg" 2>/dev/null | awk -F"'" '{print $2}')

if [ -z "$url" ]; then
    echo "[ERROR] 无法获取 $pkg 的下载 URL" >&2
    exit 1
fi

echo "$pkg  $url"
