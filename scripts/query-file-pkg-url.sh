#!/bin/bash
# query-file-pkg-url.sh — 查询 deb 包信息及下载 URL
# 支持两种模式：
#   -f <文件名>  文件名模糊查询（通过 apt-file 反向查找）
#   -p <包名>    软件包精确查询（直接取 URL）
set -euo pipefail

usage() {
    cat <<EOF
用法: $(basename "$0") -f <文件名>
      $(basename "$0") -p <包名>

查询任意文件所属 deb 包名及完整下载 URL，或直接查询指定 deb 包的下载 URL。

模式:
  -f, --file <文件名>   文件名模糊查询，查找包含该文件的所有 deb 包
  -p, --pkg  <包名>     软件包精确查询，直接返回指定包的下载 URL

示例:
  $(basename "$0") -f libcairo.so.2
  $(basename "$0") -f /usr/lib/x86_64-linux-gnu/libcairo.so.2
  $(basename "$0") -p libcairo2
EOF
}

[ $# -eq 0 ] && { usage; exit 1; }
[[ "$1" == "-h" || "$1" == "--help" ]] && { usage; exit 0; }

mode=""
value=""

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--file)
            mode="file"
            shift
            value="${1:-}"
            ;;
        -p|--pkg)
            mode="pkg"
            shift
            value="${1:-}"
            ;;
        *)
            echo "[ERROR] 未知参数: $1" >&2
            usage
            exit 1
            ;;
    esac
    shift
done

if [ -z "$mode" ] || [ -z "$value" ]; then
    usage
    exit 1
fi

if [ "$mode" = "file" ]; then
    file=$(basename "$value")

    mapfile -t pkgs < <(apt-file search -x "/${file}$" 2>/dev/null | cut -d: -f1 | sort -u)

    if [ ${#pkgs[@]} -eq 0 ]; then
        echo "[ERROR] 未找到包含文件 '$file' 的软件包" >&2
        exit 1
    fi

    for pkg in "${pkgs[@]}"; do
        url=$(apt-get download --print-uris "$pkg" 2>/dev/null | awk -F"'" '{print $2}')
        if [ -n "$url" ]; then
            echo "$pkg  $url"
        fi
    done
elif [ "$mode" = "pkg" ]; then
    url=$(apt-get download --print-uris "$value" 2>/dev/null | awk -F"'" '{print $2}')
    if [ -z "$url" ]; then
        echo "[ERROR] 未找到软件包 '$value' 或获取 URL 失败" >&2
        exit 1
    fi
    echo "$value  $url"
fi
