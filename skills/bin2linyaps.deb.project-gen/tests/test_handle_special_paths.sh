#!/bin/bash
#==============================================================================
# 测试脚本: handle_special_paths.sh 回归测试
# 功能: 验证中文/非 ASCII 路径在 binaryDir 中被【原样保留】，
#       仅对真正破坏 shell 解析的 ASCII 特殊字符（空格/括号/& # $/开头 -）
#       做规范化。非 ASCII 若需嵌入 bash 脚本，由 pak_linyaps.sh 的
#       shell_escape() 负责转义，而非改名。
# 场景: examples/com.hymake.nucleus_3.9.0_amd64.deb 内含大量中文目录
#       （费用定额/、项目汇总/ 等）及中文可执行名（海迈云计价平台）
#   bug(旧): 把所有非 ASCII 替换为下划线+MD5 哈希，丢失原始文件名语义
#   修复: 非 ASCII 字符原样保留，仅处理 shell 危险 ASCII 字符
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
NUCLEUS_DEB_FILE="${REPO_ROOT}/examples/com.hymake.nucleus_3.9.0_amd64.deb"

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

#------------------------------------------------------------------------------
# 测试用例 A: 单元级 normalize_dirname 保留非 ASCII（含中文前缀）
#   'PPT遥控翻页' 应【原样保留】，不再哈希化
#------------------------------------------------------------------------------
test_normalize_ascii_prefix_kept() {
    log_info "测试: normalize_dirname 保留中文路径中的 ASCII 前缀（原样）"

    local got
    got=$(extract_and_run "log_info normalize_dirname" "normalize_dirname 'PPT遥控翻页'")

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${got}" == "PPT遥控翻页" ]]; then
        log_success "PPT遥控翻页 -> '${got}'（非 ASCII 原样保留，不清除前缀）"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "期望 'PPT遥控翻页'，实际 '${got}'（非 ASCII 被改名，bug 复发）"
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
# 测试用例 A3: 纯中文名 -> 原样保留（不再哈希化）
#------------------------------------------------------------------------------
test_normalize_pure_chinese_hash_only() {
    log_info "测试: normalize_dirname 纯中文名原样保留"

    local got
    got=$(extract_and_run "log_info normalize_dirname" "normalize_dirname '遥控翻页'")

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${got}" == "遥控翻页" ]]; then
        log_success "遥控翻页 -> '${got}'（原样保留）"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "期望 '遥控翻页'，实际 '${got}'（纯中文被改名，bug 复发）"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例 A4: 含空格的 ASCII 名空格被规范化（空格会破坏 shell 解析）
#   括号/非 ASCII 等可安全嵌入双引号 bash 字符串的字符原样保留
#   'My App(1)' -> 'My_App(1)'
#------------------------------------------------------------------------------
test_normalize_special_chars_readable() {
    log_info "测试: normalize_dirname 空格规范化，括号/中文保留"

    local got
    got=$(extract_and_run "log_info normalize_dirname" "normalize_dirname 'My App(1)'")

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${got}" == "My_App(1)" ]]; then
        log_success "My App(1) -> '${got}'（空格规范化，括号保留）"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "My App(1) 规范化异常: '${got}'（期望 'My_App(1)'）"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例 A5: 中文路径含括号（如 福建(清单13)）应原样保留
#   括号可安全嵌入双引号 bash 字符串，由 pak_linyaps.sh 的 shell_escape()
#   负责转义，故文件名中的括号无需改动，中文更应保留
#   '福建(清单13)' -> '福建(清单13)'
#------------------------------------------------------------------------------
test_normalize_chinese_with_parens() {
    log_info "测试: normalize_dirname 中文路径含括号原样保留"

    local got
    got=$(extract_and_run "log_info normalize_dirname" "normalize_dirname '福建(清单13)'")

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${got}" == "福建(清单13)" ]]; then
        log_success "福建(清单13) -> '${got}'（中文与括号均原样保留）"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "福建(清单13) 未被原样保留: '${got}'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例 B: 端到端，用真实 deb（ppthelper-agent）
#   deb 缺失时跳过
#   断言:
#     1. 产物 binary/ 中【保留】原始中文目录 PPT遥控翻页
#     2. binary/ 中存在非 ASCII 路径（证明未被强制改名）
#     3. 可执行文件 pthelper-agent 在该目录下可找到
#------------------------------------------------------------------------------
test_e2e_real_deb() {
    log_info "测试: 端到端 - 真实 deb 中文 binaryDir 原样保留"

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

    local expect_dir="PPT遥控翻页"

    # 断言 1: 原始中文目录被保留
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -d "${binary}/${expect_dir}" ]]; then
        log_success "应用目录原样保留中文名: ${expect_dir}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "未找到目录 '${expect_dir}'，实际二进制目录:"
        find "${binary}" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sed 's/^/    /'
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # 断言 2: binary/ 中存在非 ASCII 路径（证明未被强制改名）
    local nonascii
    nonascii=$(find "${binary}" -print0 2>/dev/null | tr '\0' '\n' | grep -P '[^\x00-\x7F]' || true)

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -n "${nonascii}" ]]; then
        log_success "binary/ 中保留非 ASCII 路径（中文未被改名）"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "binary/ 中不存在任何非 ASCII 路径（非 ASCII 被全部改名，与预期不符）"
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
# 测试用例 C: 端到端 - nucleus 真实 deb（用户指定用例）
#   examples/com.hymake.nucleus_3.9.0_amd64.deb
#   内含大量中文目录（费用定额/、项目汇总/）及中文可执行名（海迈云计价平台）
#   linyaps 结构 /opt/apps/<id>/files/ 平铺到 binary/
#   断言:
#     1. 中文目录 '费用定额' 被原样保留
#     2. 中文可执行文件 '海迈云计价平台' 位于 binary/bin/ 下
#------------------------------------------------------------------------------
test_e2e_nucleus_deb() {
    log_info "测试: 端到端 - nucleus 真实 deb 中文路径原样保留"

    if [[ ! -f "${NUCLEUS_DEB_FILE}" ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        log_skip "未找到 deb 用例 ${NUCLEUS_DEB_FILE}，跳过端到端测试"
        return
    fi

    if ! command -v dpkg >/dev/null 2>&1; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        log_skip "未安装 dpkg，跳过端到端测试"
        return
    fi

    local src="${TEST_TMP_DIR}/nucleus_src"
    local binary="${TEST_TMP_DIR}/nucleus_binary"
    mkdir -p "${src}" "${binary}"

    if ! dpkg -x "${NUCLEUS_DEB_FILE}" "${src}" >/dev/null 2>&1; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        log_skip "dpkg -x 解包失败，跳过端到端测试"
        return
    fi

    if ! bash "${HANDLE_SCRIPT}" --phase=paths "${src}" "${binary}" >/dev/null 2>&1; then
        TESTS_RUN=$((TESTS_RUN + 1))
        log_error "nucleus handle_special_paths paths 阶段执行失败（exit != 0）"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return
    fi

    # 断言 1: 中文目录 '费用定额' 被原样保留（bin/ 下）
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -d "${binary}/bin/费用定额" ]]; then
        log_success "中文目录原样保留: bin/费用定额/"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "未找到目录 'bin/费用定额'，实际 bin/ 下目录:"
        find "${binary}/bin" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sed 's/^/    /'
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # 断言 2: 中文可执行文件 '海迈云计价平台' 位于 binary/bin/ 下
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -x "${binary}/bin/海迈云计价平台" ]]; then
        log_success "中文可执行文件原样保留: bin/海迈云计价平台"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "未找到可执行文件 'bin/海迈云计价平台'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 主函数
#------------------------------------------------------------------------------
main() {
    echo "========================================"
    echo "  handle_special_paths.sh 回归测试"
    echo "  (非 ASCII 路径原样保留)"
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
    test_normalize_chinese_with_parens
    test_e2e_real_deb
    test_e2e_nucleus_deb

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
