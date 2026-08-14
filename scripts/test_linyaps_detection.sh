#!/bin/bash
# 测试 linyaps /opt/apps/<id>/ 结构检测与文件平铺
# 使用 examples/com.zjd.gov_2.31.0.4_amd64.deb
#
# 用法: bash scripts/test_linyaps_detection.sh
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEB_FILE="${PROJECT_ROOT}/examples/com.zjd.gov_2.31.0.4_amd64.deb"
HANDLE_SCRIPT="${PROJECT_ROOT}/skills/bin2linyaps.deb.project-gen/scripts/handle_special_paths.sh"
CACHE_DIR="${PROJECT_ROOT}/.cache/test_linyaps"
EXTRACT_DIR="${CACHE_DIR}/extracted"
OUTPUT_DIR="${CACHE_DIR}/output"
CACHE_MARKER="${EXTRACT_DIR}/.extracted"

PASS=0
FAIL=0

assert() {
	local desc="$1"
	local msg="$2"
	if [ "$msg" = "PASS" ]; then
		echo -e "  [PASS] ${desc}"
		((PASS++)) || true
	else
		echo -e "  [FAIL] ${desc}: ${msg}"
		((FAIL++)) || true
	fi
}

check_file() {
	local path="$1"
	local desc="$2"
	if [ -f "$path" ]; then
		assert "$desc" "PASS"
	else
		assert "$desc" "not found: $path"
	fi
}

check_dir_not_exists() {
	local path="$1"
	local desc="$2"
	if [ ! -d "$path" ]; then
		assert "$desc" "PASS"
	else
		assert "$desc" "exists: $path"
	fi
}

echo "=========================================="
echo "  测试: linyaps /opt/apps/<id>/ 结构检测"
echo "=========================================="
echo ""

# 步骤 1: 提取 deb 到缓存
echo "[1/4] 准备 deb 提取缓存..."
mkdir -p "${CACHE_DIR}"

if [ -f "${CACHE_MARKER}" ]; then
	echo "  使用缓存: ${EXTRACT_DIR}"
else
	echo "  提取 deb 到: ${EXTRACT_DIR}"
	rm -rf "${EXTRACT_DIR}"
	mkdir -p "${EXTRACT_DIR}"
	dpkg -x "${DEB_FILE}" "${EXTRACT_DIR}"
	touch "${CACHE_MARKER}"
	echo "  提取完成"
fi
echo ""

# 步骤 2: 清空输出目录
echo "[2/4] 准备输出目录..."
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"
echo "  输出目录: ${OUTPUT_DIR}"
echo ""

# 步骤 3: 运行 handle_special_paths.sh
echo "[3/4] 运行 handle_special_paths.sh..."
echo "  源目录: ${EXTRACT_DIR}"
echo "  目标目录: ${OUTPUT_DIR}"
echo "  脚本: ${HANDLE_SCRIPT}"
echo ""

# 先检查提取目录结构
echo "  提取目录结构:"
ls -la "${EXTRACT_DIR}/" 2>/dev/null | head -5
echo ""

bash "${HANDLE_SCRIPT}" --phase=paths "${EXTRACT_DIR}" "${OUTPUT_DIR}" --verbose 2>&1
echo ""

# 步骤 4: 验证结果
echo "[4/4] 验证结果..."
echo ""

# 4.1 检查 .detected_app_id
DETECTED_ID=""
if [ -f "${OUTPUT_DIR}/.detected_app_id" ]; then
	DETECTED_ID=$(cat "${OUTPUT_DIR}/.detected_app_id")
	assert ".detected_app_id 内容为 com.zjd.gov" \
		$([ "${DETECTED_ID}" = "com.zjd.gov" ] && echo "PASS" || echo "期望 com.zjd.gov, 实际 ${DETECTED_ID}")
else
	assert ".detected_app_id 文件存在" "not found"
fi

# 4.2 检查 Elevator.sh 是否平铺到 output/ 根目录
check_file "${OUTPUT_DIR}/Elevator.sh" "Elevator.sh 平铺到 output/ 根目录"

# 4.3 检查 logo.svg 是否平铺到 output/ 根目录
check_file "${OUTPUT_DIR}/logo.svg" "logo.svg 平铺到 output/ 根目录"

# 4.4 检查 version 文件
check_file "${OUTPUT_DIR}/version" "version 文件平铺到 output/ 根目录"

# 4.5 检查 2.31.0-Release.4 目录
check_file "${OUTPUT_DIR}/2.31.0-Release.4/QtWebEngineProcess" \
	"2.31.0-Release.4/QtWebEngineProcess 存在"

# 4.6 检查 entries/ 未被复制到 output/
check_dir_not_exists "${OUTPUT_DIR}/entries" \
	"entries/ 未被复制到 output/ (由 files_res/ 管线处理)"

# 4.7 检查 entries/ 内容不应出现在 output/applications/
check_dir_not_exists "${OUTPUT_DIR}/applications" \
	"applications/ 不在 output/ 根目录 (desktop 文件未混入)"

# 4.8 检查 apps/ 嵌套不应存在
check_dir_not_exists "${OUTPUT_DIR}/apps" \
	"apps/ 嵌套目录不存在 (linyaps 结构已平铺)"

echo ""
echo "=========================================="
echo "  测试结果"
echo "=========================================="
echo "  通过: ${PASS}"
echo "  失败: ${FAIL}"
echo "=========================================="

if [ "${FAIL}" -gt 0 ]; then
	echo "  状态: 失败"
	exit 1
else
	echo "  状态: 全部通过"
	exit 0
fi