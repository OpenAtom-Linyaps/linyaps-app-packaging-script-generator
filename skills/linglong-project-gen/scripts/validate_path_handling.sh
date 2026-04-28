#!/bin/bash
# 验证特殊格式路径处理脚本
# 用于测试 deb 包解压后包含特殊字符路径的处理逻辑

# 不使用 set -e，以便继续执行所有测试

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 测试结果统计
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 日志函数
log_info() {
	echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
	echo -e "${GREEN}[PASS]${NC} $1"
	((PASSED_TESTS++))
}

log_error() {
	echo -e "${RED}[FAIL]${NC} $1"
	((FAILED_TESTS++))
}

log_warning() {
	echo -e "${YELLOW}[WARN]${NC} $1"
}

# 测试用例：创建包含特殊字符的目录结构
create_test_structure() {
	local test_dir="$1"
	log_info "创建测试目录结构: ${test_dir}"

	mkdir -p "${test_dir}"

	# 测试用例 1: 包含空格的目录名
	mkdir -p "${test_dir}/opt/My App"
	touch "${test_dir}/opt/My App/myapp"
	chmod +x "${test_dir}/opt/My App/myapp"

	# 测试用例 2: 包含空格的文件名
	mkdir -p "${test_dir}/opt/TestApp"
	touch "${test_dir}/opt/TestApp/my binary"
	chmod +x "${test_dir}/opt/TestApp/my binary"

	# 测试用例 3: 包含逗号的目录名
	mkdir -p "${test_dir}/opt/App,v1.0"
	touch "${test_dir}/opt/App,v1.0/app"
	chmod +x "${test_dir}/opt/App,v1.0/app"

	# 测试用例 4: 包含中文的目录名
	mkdir -p "${test_dir}/opt/我的应用"
	touch "${test_dir}/opt/我的应用/应用"
	chmod +x "${test_dir}/opt/我的应用/应用"

	# 测试用例 5: 包含多个连续空格
	mkdir -p "${test_dir}/opt/App  With  Spaces"
	touch "${test_dir}/opt/App  With  Spaces/binary"
	chmod +x "${test_dir}/opt/App  With  Spaces/binary"

	# 测试用例 6: 包含连字符开头的目录名
	mkdir -p "${test_dir}/opt/-hidden-app"
	touch "${test_dir}/opt/-hidden-app/app"
	chmod +x "${test_dir}/opt/-hidden-app/app"

	# 测试用例 7: 标准路径 /usr/ 下的空格目录
	mkdir -p "${test_dir}/usr/bin"
	mkdir -p "${test_dir}/usr/share/My App"
	touch "${test_dir}/usr/share/My App/resource.txt"

	# 测试用例 8: 包含逗号和空格混合
	mkdir -p "${test_dir}/opt/App, v2.0"
	touch "${test_dir}/opt/App, v2.0/binary"
	chmod +x "${test_dir}/opt/App, v2.0/binary"

	# 测试用例 9: 包含中文和空格混合
	mkdir -p "${test_dir}/opt/我的 应用"
	touch "${test_dir}/opt/我的 应用/binary"
	chmod +x "${test_dir}/opt/我的 应用/binary"

	# 测试用例 10: 包含连字符的目录名（中间位置）
	mkdir -p "${test_dir}/opt/App-v1.0"
	touch "${test_dir}/opt/App-v1.0/app"
	chmod +x "${test_dir}/opt/App-v1.0/app"

	log_info "测试目录结构创建完成"
}

# 调用实际的路径处理脚本
process_paths() {
	local src_dir="$1"
	local dest_dir="$2"

	log_info "调用 handle_special_paths.sh 处理路径转换..."

	# 获取脚本所在目录
	local script_dir="$(dirname "$(readlink -f "$0")")"

	# 调用独立的路径处理脚本
	if [ -f "${script_dir}/handle_special_paths.sh" ]; then
		"${script_dir}/handle_special_paths.sh" "${src_dir}" "${dest_dir}" --verbose
	else
		log_error "找不到 handle_special_paths.sh 脚本"
		exit 1
	fi
}

# 验证路径处理结果
verify_results() {
	local dest_dir="$1"

	log_info "开始验证结果..."
	log_info "目标目录: ${dest_dir}"

	# 列出目标目录内容
	log_info "目标目录内容:"
	ls -la "${dest_dir}/" 2>&1 | while IFS= read -r line; do
		log_info "  ${line}"
	done

	# 列出每个子目录的内容
	log_info "子目录内容详情:"
	find "${dest_dir}" -mindepth 1 -maxdepth 2 -type f | while IFS= read -r file; do
		log_info "  文件: ${file}"
	done

	# 测试 1: 验证空格目录是否被标准化
	((TOTAL_TESTS++))
	if [ -d "${dest_dir}/My_App" ]; then
		log_success "空格目录 'My App' 已标准化为 'My_App'"
	else
		log_error "空格目录 'My App' 标准化失败"
	fi

	# 测试 2: 验证可执行文件是否保留
	((TOTAL_TESTS++))
	if [ -x "${dest_dir}/My_App/myapp" ]; then
		log_success "可执行文件 'myapp' 权限正确"
	else
		log_error "可执行文件 'myapp' 权限错误或文件不存在"
	fi

	# 测试 3: 验证逗号目录是否被标准化
	((TOTAL_TESTS++))
	if [ -d "${dest_dir}/App_v1.0" ]; then
		log_success "逗号目录 'App,v1.0' 已标准化为 'App_v1.0'"
	else
		log_error "逗号目录 'App,v1.0' 标准化失败"
	fi

	# 测试 4: 验证中文目录（中文使用哈希值）
	((TOTAL_TESTS++))
	if [ -d "${dest_dir}/0ecb7b61" ]; then
		log_success "中文目录 '我的应用' 已标准化为哈希值 '0ecb7b61'"
	else
		log_error "中文目录 '我的应用' 标准化失败"
	fi

	# 测试 5: 验证多个空格是否被标准化
	((TOTAL_TESTS++))
	if [ -d "${dest_dir}/App_With_Spaces" ]; then
		log_success "多空格目录 'App  With  Spaces' 已标准化为 'App_With_Spaces'"
	else
		log_error "多空格目录 'App  With  Spaces' 标准化失败"
	fi

	# 测试 6: 验证连字符开头的目录是否被标准化（移除前导连字符）
	((TOTAL_TESTS++))
	if [ -d "${dest_dir}/hidden-app" ]; then
		log_success "连字符开头目录 '-hidden-app' 已标准化为 'hidden-app'"
	else
		log_error "连字符开头目录 '-hidden-app' 标准化失败"
	fi

	# 测试 7: 验证逗号和空格混合目录（连续下划线会被清理为一个）
	((TOTAL_TESTS++))
	if [ -d "${dest_dir}/App_v2.0" ]; then
		log_success "逗号空格混合目录 'App, v2.0' 已标准化为 'App_v2.0'"
	else
		log_error "逗号空格混合目录 'App, v2.0' 标准化失败"
	fi

	# 测试 8: 验证中文和空格混合目录（中文+空格都使用哈希值）
	((TOTAL_TESTS++))
	if [ -d "${dest_dir}/7b07a92d" ]; then
		log_success "中文空格混合目录 '我的 应用' 已标准化为哈希值 '7b07a92d'"
	else
		log_error "中文空格混合目录 '我的 应用' 标准化失败"
	fi

	# 测试 10: 验证文件名中的空格（文件名也需要标准化）
	((TOTAL_TESTS++))
	if [ -f "${dest_dir}/TestApp/my_binary" ]; then
		log_success "空格文件名 'my binary' 已标准化为 'my_binary'"
	else
		log_error "空格文件名 'my binary' 标准化失败"
	fi

	# 测试 11: 验证路径映射文件是否生成
	((TOTAL_TESTS++))
	if [ -f "${dest_dir}/.path_mapping" ]; then
		log_success "路径映射文件 '.path_mapping' 已生成"
	else
		log_error "路径映射文件 '.path_mapping' 未生成"
	fi
}

# 测试软链创建（模拟二进制软链处理）
test_symlink_creation() {
	local dest_dir="$1"
	((TOTAL_TESTS++))

	log_info "测试软链创建..."

	mkdir -p "${dest_dir}/bin"

	# 测试：为标准化后的目录中的二进制创建软链
	# 注意：现在使用标准化后的路径 My_App 而不是 My App
	local binary_path="${dest_dir}/My_App/myapp"
	if [ -f "${binary_path}" ]; then
		cd "${dest_dir}/bin"
		ln -sf "../My_App/myapp" "myapp" 2>/dev/null

		if [ -L "myapp" ]; then
			log_success "软链创建成功: bin/myapp -> ../My_App/myapp"
		else
			log_error "软链创建失败"
		fi
		cd - >/dev/null
	else
		log_error "源二进制文件不存在"
	fi
}

# 检测潜在问题的函数
detect_potential_issues() {
	local test_dir="$1"

	log_info "检测潜在问题..."

	# 检查目录名是否包含需要转义的字符
	find "${test_dir}" -type d | while read dir; do
		dirname=$(basename "${dir}")

		# 检查空格
		if [[ "${dirname}" =~ [[:space:]] ]]; then
			log_warning "目录包含空格: ${dir}"
		fi

		# 检查特殊字符
		if [[ "${dirname}" =~ [\(\)\&\@\#\$\'\"] ]]; then
			log_warning "目录包含特殊字符: ${dir}"
		fi
	done

	# 检查文件名
	find "${test_dir}" -type f | while read file; do
		filename=$(basename "${file}")

		if [[ "${filename}" =~ [[:space:]] ]]; then
			log_warning "文件包含空格: ${file}"
		fi

		if [[ "${filename}" =~ [\(\)\&\@\#\$\'\"] ]]; then
			log_warning "文件包含特殊字符: ${file}"
		fi
	done
}

# 生成测试报告
generate_report() {
	echo ""
	echo "========================================="
	echo "           测试报告"
	echo "========================================="
	echo -e "总测试数: ${TOTAL_TESTS}"
	echo -e "通过: ${GREEN}${PASSED_TESTS}${NC}"
	echo -e "失败: ${RED}${FAILED_TESTS}${NC}"
	echo -e "通过率: $(awk "BEGIN {printf \"%.2f%%\", (${PASSED_TESTS}/${TOTAL_TESTS})*100}")"
	echo "========================================="

	if [ ${FAILED_TESTS} -eq 0 ]; then
		echo -e "${GREEN}所有测试通过！${NC}"
		return 0
	else
		echo -e "${RED}存在失败的测试！${NC}"
		return 1
	fi
}

# 清理函数
cleanup() {
	local test_dir="$1"
	if [ -d "${test_dir}" ]; then
		log_info "清理测试目录: ${test_dir}"
		rm -rf "${test_dir}"
	fi
}

# 主函数
main() {
	local base_tmp_dir="${1:-$(mktemp -d)}"
	local test_src_dir="${base_tmp_dir}/test_src"
	local test_dest_dir="${base_tmp_dir}/test_dest"

	echo "========================================="
	echo "   特殊格式路径处理验证脚本"
	echo "========================================="
	echo ""

	# 步骤 1: 创建测试结构
	create_test_structure "${test_src_dir}"
	echo ""

	# 步骤 2: 检测潜在问题
	detect_potential_issues "${test_src_dir}"
	echo ""

	# 步骤 3: 处理路径
	process_paths "${test_src_dir}" "${test_dest_dir}"
	echo ""

	# 步骤 4: 验证结果
	verify_results "${test_dest_dir}"
	echo ""

	# 步骤 5: 测试软链
	test_symlink_creation "${test_dest_dir}"
	echo ""

	# 步骤 6: 生成报告
	generate_report
	local result=$?

	# 步骤 7: 清理（可选）
	if [ "$2" != "--keep" ]; then
		cleanup "${base_tmp_dir}"
	else
		log_info "测试目录保留在: ${base_tmp_dir}"
	fi

	return ${result}
}

# 使用说明
usage() {
	echo "用法: $0 [临时目录] [--keep]"
	echo ""
	echo "参数:"
	echo "  临时目录  指定测试用的临时目录（可选，默认自动创建）"
	echo "  --keep    保留测试目录，不自动清理"
	echo ""
	echo "示例:"
	echo "  $0                          # 使用自动创建的临时目录"
	echo "  $0 /tmp/test_special_paths  # 指定临时目录"
	echo "  $0 /tmp/test --keep         # 保留测试目录"
}

# 检查参数
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
	usage
	exit 0
fi

# 执行主函数
main "$@"
