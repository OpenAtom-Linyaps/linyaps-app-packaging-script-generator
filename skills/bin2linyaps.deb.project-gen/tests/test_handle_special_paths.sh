#!/bin/bash
#==============================================================================
# 测试脚本: handle_special_paths.sh 回归测试
# 功能: 验证中文/非 ASCII binaryDir 路径规范化正确保留 ASCII 前缀
# 场景: examples/ppthelper-agent_1.0.8_amd64.deb 内含 /opt/PPT遥控翻页/
#   bug: 在 zh_CN.UTF-8 locale 下 'sed [^ -~]' 会连带替换 ASCII 字母，
#        'PPT遥控翻页' -> 'bfa33cee'（丢失 PPT 前缀）
#   修复: LC_ALL=C sed 按字节比较，'PPT遥控翻页' -> 'PPT_bfa33cee'
#==============================================================================

# 不使用 set -e，因为测试用例的失败不应该立即退出整个脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试计数器
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# 测试目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HANDLE_SCRIPT="${PROJECT_ROOT}/templates/scripts/handle_special_paths.sh"
# 仓库根目录下 examples/ 中的真实 deb 用例
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
DEB_FILE="${REPO_ROOT}/examples/ppthelper-agent_1.0.8_amd64.deb"

# 测试用临时目录
TEST_TMP_DIR=""

#------------------------------------------------------------------------------
# 测试辅助函数
#------------------------------------------------------------------------------
log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

setup() {
    TEST_TMP_DIR=$(mktemp -d)
}

teardown() {
    rm -rf "${TEST_TMP_DIR}"
}

# 提取脚本中的函数并独立执行
# 用法: extract_and_run '<func_name1> <func_name2>...' '<表达式>'
# 例: extract_and_run "log_info normalize_dirname" "normalize_dirname 'PPT遥控翻页'"
extract_and_run() {
    local funcs="$1"
    local expr="$2"
    local file="${HANDLE_SCRIPT}"
    local awk_prog=""
    local f
    for f in ${funcs}; do
        awk_prog="${awk_prog} /^${f}\\(\\) \\{/,/^\\}/ {print} "
    done
    bash -c "
        log_info() { :; }
        $(awk "${awk_prog}" "${file}")
        ${expr}
    " 2>/dev/null
}

# 计算 8 位 md5 哈希（与脚本一致）
md5_8() {
    echo -n "$1" | md5sum | cut -c1-8
}

#------------------------------------------------------------------------------
# 测试用例 A: 单元级 normalize_dirname 中文前缀保留
#   'PPT遥控翻页' 应保留 ASCII 前缀 'PPT'，中文哈希化
#   'PPT遥控翻页' 的 md5 前 8 位为 bfa33cee -> 期望 'PPT_bfa33cee'
#------------------------------------------------------------------------------
test_normalize_ascii_prefix_kept() {
    log_info "测试: normalize_dirname 保留中文路径中的 ASCII 前缀"

    local hash
    hash=$(md5_8 "PPT遥控翻页")
    local expect="PPT_${hash}"
    local got
    got=$(extract_and_run "log_info normalize_dirname" "normalize_dirname 'PPT遥控翻页'")

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${got}" == "${expect}" ]]; then
        log_success "PPT遥控翻页 -> '${got}'（保留 ASCII 前缀）"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "期望 '${expect}'，实际 '${got}'（ASCII 前缀丢失，bug 复发）"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例 A2: 纯 ASCII 目录名不应被改变
#------------------------------------------------------------------------------
test_normalize_ascii_unchanged() {
    log_info "测试: normalize_dirname 纯 ASCII 名称保持不变"

    local got
    got=$(extract_and_run "log_info normalize_dirname" "normalize_dirname 'uTools'")

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${got}" == "uTools" ]]; then
        log_success "uTools -> '${got}'（保持不变）"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "期望 'uTools'，实际 '${got}'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例 A3: 纯中文名 -> 仅哈希（无 ASCII 前缀可保留）
#------------------------------------------------------------------------------
test_normalize_pure_chinese_hash_only() {
    log_info "测试: normalize_dirname 纯中文名哈希化"

    local hash
    hash=$(md5_8 "遥控翻页")
    local got
    got=$(extract_and_run "log_info normalize_dirname" "normalize_dirname '遥控翻页'")

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${got}" == "${hash}" ]]; then
        log_success "遥控翻页 -> '${got}'（哈希化）"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "期望 '${hash}'，实际 '${got}'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例 A4: 含空格/括号/特殊符号的 ASCII 名规范化后仍可读
#------------------------------------------------------------------------------
test_normalize_special_chars_readable() {
    log_info "测试: normalize_dirname 特殊符号规范化后仍可读"

    local got
    got=$(extract_and_run "log_info normalize_dirname" "normalize_dirname 'My App(1)'")

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${got}" == *App* ]]; then
        log_success "My App(1) -> '${got}'（可读）"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "My App(1) 规范化异常: '${got}'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例 B: 端到端，用真实 deb（ppthelper-agent）
#   deb 缺失时跳过
#   断言:
#     1. 产物 binary/ 中不存在任何非 ASCII 路径
#     2. 应用目录保留 ASCII 前缀（存在 PPT_<hash> 目录）
#     3. 可执行文件 pthelper-agent 在该目录下可找到
#------------------------------------------------------------------------------
test_e2e_real_deb() {
    log_info "测试: 端到端 - 真实 deb 中文 binaryDir 规范化"

    if [[ ! -f "${DEB_FILE}" ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        log_skip "未找到 deb 用例 ${DEB_FILE}，跳过端到端测试"
        return
    fi

    if ! command -v dpkg >/dev/null 2>&1; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        log_skip "未安装 dpkg，跳过端到端测试"
        return
    fi

    local src="${TEST_TMP_DIR}/src"
    local binary="${TEST_TMP_DIR}/binary"
    mkdir -p "${src}" "${binary}"

    # 解包 deb
    if ! dpkg -x "${DEB_FILE}" "${src}" >/dev/null 2>&1; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        log_skip "dpkg -x 解包失败，跳过端到端测试"
        return
    fi

    # 运行 paths 阶段
    if ! bash "${HANDLE_SCRIPT}" --phase=paths "${src}" "${binary}" >/dev/null 2>&1; then
        TESTS_RUN=$((TESTS_RUN + 1))
        log_error "handle_special_paths paths 阶段执行失败（exit != 0）"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return
    fi

    local hash
    hash=$(md5_8 "PPT遥控翻页")
    local expect_dir="PPT_${hash}"

    # 断言 1: 不存在任何非 ASCII 路径
    local nonascii
    nonascii=$(find "${binary}" -print0 2>/dev/null | tr '\0' '\n' | grep -P '[^\x00-\x7F]' || true)

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -z "${nonascii}" ]]; then
        log_success "binary/ 中不存在非 ASCII 路径"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "binary/ 中仍存在非 ASCII 路径: ${nonascii}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # 断言 2: 应用目录保留 ASCII 前缀
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -d "${binary}/${expect_dir}" ]]; then
        log_success "应用目录保留 ASCII 前缀: ${expect_dir}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "未找到目录 '${expect_dir}'，实际二进制目录:"
        find "${binary}" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sed 's/^/    /'
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # 断言 3: 可执行文件 pthelper-agent 可找到
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -x "${binary}/${expect_dir}/ppthelper-agent" ]]; then
        log_success "可执行文件 pthelper-agent 位于 ${expect_dir}/"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "未找到可执行文件 ${expect_dir}/ppthelper-agent"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 主函数
#------------------------------------------------------------------------------
main() {
    echo "========================================"
    echo "  handle_special_paths.sh 回归测试"
    echo "  (非 ASCII binaryDir 路径规范化)"
    echo "========================================"
    echo ""

    # 前置检查: 目标脚本存在
    if [[ ! -f "${HANDLE_SCRIPT}" ]]; then
        echo -e "${RED}[ERROR]${NC} 未找到脚本: ${HANDLE_SCRIPT}"
        exit 1
    fi

    setup

    # 执行测试
    test_normalize_ascii_prefix_kept
    test_normalize_ascii_unchanged
    test_normalize_pure_chinese_hash_only
    test_normalize_special_chars_readable
    test_e2e_real_deb

    teardown

    # 输出测试结果
    echo ""
    echo "========================================"
    echo "  测试结果汇总"
    echo "========================================"
    echo "  总计: ${TESTS_RUN}"
    echo -e "  通过: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "  失败: ${RED}${TESTS_FAILED}${NC}"
    echo -e "  跳过: ${YELLOW}${TESTS_SKIPPED}${NC}"
    echo "========================================"

    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        exit 1
    fi

    exit 0
}

main "$@"
