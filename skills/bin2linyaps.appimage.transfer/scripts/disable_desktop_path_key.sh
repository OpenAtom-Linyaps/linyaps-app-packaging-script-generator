#!/bin/bash
# 注释所有 .desktop 文件中的 Path= 键
#
# 用途：
# 转换（deb/tar/appimage → linyaps）时，源 .desktop 文件的 Path= 键常携带
# 宿主绝对路径（如 Path=/home/xxx/...）。在 linyaps 沙箱内该路径无效，
# 残留的 Path 键会干扰启动。
#
# 本脚本在 ll-builder build 之前执行，将指定目录下每个 .desktop 文件中的
# Path= 行注释掉，使打包产物不含 Path 键。
#
# 用法：
#   disable_desktop_path_key.sh <desktop_root_dir>
#
# 参数：
#   desktop_root_dir - 递归扫描的根目录（如 build_tmp_dir）
#
# 行为：
#   - 递归扫描所有 *.desktop 文件（含子目录）
#   - 注释匹配 ^[[:space:]]*Path= 的行，改为 \1# Path=
#   - 幂等：已注释的行以 # 开头，正则不命中 → 二次执行为 no-op
#   - 无匹配不是错误（退出 0），仅打印汇总
#
# 示例：
#   disable_desktop_path_key.sh /project/build_tmp

set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
	echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

# 显示使用说明
usage() {
	echo "用法: $0 <desktop_root_dir>"
	echo ""
	echo "参数:"
	echo "  desktop_root_dir - 递归扫描的根目录，其下所有 *.desktop 文件的 Path= 键将被注释"
	echo ""
	echo "示例:"
	echo "  $0 /project/build_tmp"
}

main() {
	if [ "$#" -ne 1 ]; then
		echo -e "\033[0;31m[ERROR]\033[0m 参数数量错误：需要 1 个参数" >&2
		usage >&2
		exit 1
	fi

	local root="$1"

	if [ ! -d "${root}" ]; then
		echo -e "\033[0;31m[ERROR]\033[0m 目录不存在: ${root}" >&2
		exit 1
	fi

	local count=0

	while IFS= read -r -d '' f; do
		if grep -qE '^[[:space:]]*Path=' "${f}"; then
			sed -i -E 's|^([[:space:]]*)Path=|\1# Path=|' "${f}"
			log_success "Disabled Path= in: ${f}"
			count=$((count + 1))
		fi
	done < <(find "${root}" -type f -name "*.desktop" -print0)

	log_info "${count} desktop file(s) with Path= disabled"
	exit 0
}

main "$@"
