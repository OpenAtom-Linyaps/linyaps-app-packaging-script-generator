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

# 重要目录白名单：只有列入其中的顶层目录才会被复制进 binary_dir（binary_dir 等价容器虚拟 /usr）。
# 仅保留 FHS /usr 合法子目录（bin/lib/share/sbin/...）；opt、var、etc、srv、tmp 等
# 不属于 /usr 层级，一律不复制（避免生成 /usr/opt、/usr/var 等非法路径）。
# 维护：在此数组新增/删减目录名即可控制复制范围，可持续扩展。
# usr 为特例——其内容平铺进 binary_dir（usr/bin -> bin），而非复制成 usr/usr/…
IMPORTANT_DIRS=(usr bin sbin lib lib32 lib64 libexec include share local)

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
	# 只复制白名单内 FHS /usr 合法的重要目录（见脚本顶部 IMPORTANT_DIRS，可持续维护）。
	# usr 平铺其子项（usr/bin -> bin），否则会复制成 usr/usr/…，使依赖的 bin/ 可执行
	# 文件与 lib/ 库永远到不了预期路径；其余白名单顶层目录（如 legacy 包顶层
	# lib/<multiarch>/ 的 .so）直接复制。
	for entry in "$EXTRACT_DIR"/*; do
		[ -e "$entry" ] || continue
		name="$(basename "$entry")"
		important=0
		for d in "${IMPORTANT_DIRS[@]}"; do
			if [ "$d" = "$name" ]; then
				important=1
				break
			fi
		done
		[ "$important" -eq 1 ] || continue
		if [ "$name" = "usr" ] && [ -d "$entry" ]; then
			for sub in "$entry"/*; do
				[ -e "$sub" ] || continue
				if ! cp -rf "$sub" "$BINARY_DIR/"; then
					echo "WARN: 复制失败: $sub -> $BINARY_DIR/" >&2
					FAIL_COUNT=$((FAIL_COUNT + 1))
				fi
			done
		else
			if ! cp -rf "$entry" "$BINARY_DIR/"; then
				echo "WARN: 复制失败: $entry -> $BINARY_DIR/" >&2
				FAIL_COUNT=$((FAIL_COUNT + 1))
			fi
		fi
	done
	rm -rf "$EXTRACT_DIR"
	rm -f "$deb_file"
done

TOTAL=${#MISSING_DEPS_URLS[@]}
SUCCESS=$((TOTAL - FAIL_COUNT))
echo "完成: 成功 $SUCCESS/$TOTAL 个依赖包已解压到 $BINARY_DIR"
[ "$FAIL_COUNT" -eq 0 ] || echo "WARN: $FAIL_COUNT 个包处理失败" >&2
