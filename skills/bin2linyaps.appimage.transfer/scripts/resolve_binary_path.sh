#!/bin/bash
#=============================================================================
# resolve_binary_path.sh - 根據 binary_name 定位真實可執行文件
#=============================================================================
# 功能：在解壓後的 AppImage 目錄中，按 binary_name 查找唯一可執行文件，
#       並輸出其相對於搜索根的相對路徑（供 wrapper 使用）。
#
# 背景：
#   部分 AppImage（尤其是 Electron 應用）的 binary_name 指向的是 app bundle
#   目錄（如 xyz.chatboxapp.app/），真正的可執行文件位於目錄內
#   （如 xyz.chatboxapp.app/xyz.chatboxapp.app）；另一些 AppImage 的
#   binary_name 直接對應根層可執行 ELF（如 xyz.chatboxapp.app 即為文件）。
#   本腳本用 find 統一定位，規避"目錄名與 binary name 同名"導致的誤判。
#
# 用法：resolve_binary_path.sh <search_root_dir> <binary_name>
# 輸出：相對 search_root 的可執行文件路徑（唯一命中時）
# 退出碼：0=唯一命中；1=零個或多個（無法唯一確定）
#=============================================================================

set -euo pipefail

# 參數驗證
if [ $# -lt 2 ]; then
    echo "用法: $0 <search_root_dir> <binary_name>" >&2
    exit 1
fi

search_root="$1"
binary_name="$2"

if [ -z "${binary_name}" ]; then
    echo "錯誤: binary_name 為空" >&2
    exit 1
fi

if [ ! -d "${search_root}" ]; then
    echo "錯誤: 搜索根目錄不存在: ${search_root}" >&2
    exit 1
fi

# binary_name 可能是相對路徑（如 usr/bin/shotcut）或文件名（如 shotcut）
# 優先按相對路徑精確命中，未命中再回退按文件名（basename）搜索
if [[ "${binary_name}" == */* ]]; then
	candidate="${search_root}/${binary_name}"
	if [ -f "${candidate}" ] && [ -x "${candidate}" ]; then
		echo "${binary_name}"
		exit 0
	fi
	# 相對路徑未命中，回退為文件名搜索
	echo "提示: 相對路徑 '${binary_name}' 未命中可執行文件，回退按文件名 '$(basename "${binary_name}")' 搜索" >&2
	binary_name="$(basename "${binary_name}")"
fi

# 查找可執行文件
# - -maxdepth 3: 覆蓋 squashfs-root 根層 + bundle 目錄 + bundle/binary 層
# - -type f: 排除同名目錄（Electron bundle 目錄）
# - -name "${binary_name}": 精確匹配 binary name
# - -perm /+x: 匹配具備執行權限的文件
matches=$(find "${search_root}" -maxdepth 3 -type f -name "${binary_name}" -perm /+x 2>/dev/null || true)

# 計算匹配數（按行，過濾空行）
count=$(printf '%s\n' "${matches}" | grep -c '^/' || true)

if [ "${count}" -eq 1 ]; then
    # 唯一命中，輸出相對路徑
    rel_path="${matches#${search_root}/}"
    echo "${rel_path}"
    exit 0
fi

if [ "${count}" -gt 1 ]; then
    echo "錯誤: binary_name '${binary_name}' 匹配到多個可執行文件（${count} 個），無法唯一確定:" >&2
    printf '%s\n' "${matches}" | sed "s|^|    |" >&2
    exit 1
fi

echo "錯誤: binary_name '${binary_name}' 在 ${search_root}（depth≤3）未找到可執行文件" >&2
exit 1
