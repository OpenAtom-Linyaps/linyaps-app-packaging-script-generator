#!/bin/bash
#==============================================================================
# 测试脚本: disable_desktop_path_key.sh 回归测试
# 功能: 验证所有 .desktop 文件中的 Path= 键被注释掉，
#       其余键（Exec/Name/Icon 等）逐字节保留，已注释/无 Path 的 no-op，且幂等。
# 场景: 源 desktop 的 Path 键为宿主绝对路径，在 linyaps 沙箱内无效，
#       残留会干扰启动，故构建前注释失效。
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

# 测试目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_SCRIPT="${PROJECT_ROOT}/scripts/disable_desktop_path_key.sh"

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

setup() {
    TEST_TMP_DIR=$(mktemp -d)
}

teardown() {
    rm -rf "${TEST_TMP_DIR}"
}

# 用例 A: 含 Path= 的 desktop，Path 被注释且其余键逐字节不变
test_comment_path_keep_others() {
    log_info "测试: 含 Path= 的 desktop，Path 被注释且 Exec/Name/Icon 逐字节保留"

    local dir="${TEST_TMP_DIR}/a"
    mkdir -p "${dir}"
    printf '[Desktop Entry]\nType=Application\nName=App\nExec=/usr/bin/app\nIcon=app.png\nPath=/home/u/foo\nTerminal=false\n' > "${dir}/a.desktop"

    bash "${TARGET_SCRIPT}" "${dir}" >/dev/null 2>&1
    local status=$?

    # 退出码为 0
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ ${status} -eq 0 ]]; then
        log_success "退出码为 0"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "期望退出码 0，实际 ${status}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Path= 行以 # 开头
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qE '^[[:space:]]*# Path=' "${dir}/a.desktop" && ! grep -qE '^[[:space:]]*Path=' "${dir}/a.desktop"; then
        log_success "Path= 行已注释为 '# Path='"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "Path= 行未被正确注释"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # 其他键逐字节不变
    local expected_name='[Desktop Entry]
Type=Application
Name=App
Exec=/usr/bin/app
Icon=app.png
Terminal=false'
    local actual_others
    actual_others=$(grep -vE '^[[:space:]]*(# )?Path=' "${dir}/a.desktop")

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${actual_others}" == "${expected_name}" ]]; then
        log_success "Exec/Name/Icon/Type/Terminal 行逐字节保留"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "其他键被改动，实际:"
        printf '%s\n' "${actual_others}" | sed 's/^/    /'
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# 用例 B: 已含注释 # Path= 的 desktop，运行后不变
test_already_commented_noop() {
    log_info "测试: 已注释 # Path= 的 desktop 保持不变"

    local dir="${TEST_TMP_DIR}/b"
    mkdir -p "${dir}"
    local content='[Desktop Entry]
Type=Application
Name=App
Exec=/usr/bin/app
# Path=/home/u/foo
'
    printf '%s' "${content}" > "${dir}/b.desktop"

    bash "${TARGET_SCRIPT}" "${dir}" >/dev/null 2>&1

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$(cat "${dir}/b.desktop")" == "$(printf '%s' "${content}")" ]]; then
        log_success "已注释的 desktop 内容逐字节不变"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "已注释的 desktop 内容被改动"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# 用例 C: 无 Path= 的 desktop，运行后不变
test_no_path_noop() {
    log_info "测试: 无 Path= 的 desktop 保持不变"

    local dir="${TEST_TMP_DIR}/c"
    mkdir -p "${dir}"
    local content='[Desktop Entry]
Type=Application
Name=App
Exec=/usr/bin/app
Icon=app.png
'
    printf '%s' "${content}" > "${dir}/c.desktop"

    bash "${TARGET_SCRIPT}" "${dir}" >/dev/null 2>&1
    local status=$?

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ ${status} -eq 0 ]]; then
        log_success "无 Path= 时退出码为 0（no-op 成功）"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "无 Path= 时期望退出码 0，实际 ${status}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$(cat "${dir}/c.desktop")" == "$(printf '%s' "${content}")" ]]; then
        log_success "无 Path= 的 desktop 内容逐字节不变"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "无 Path= 的 desktop 内容被改动"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# 用例 D: 幂等 - 同一目录跑两次，第二次内容不变
test_idempotent() {
    log_info "测试: 幂等 - 同一目录跑两次，第二次内容不变"

    local dir="${TEST_TMP_DIR}/d"
    mkdir -p "${dir}"
    printf '[Desktop Entry]\nType=Application\nName=App\nExec=/usr/bin/app\nPath=/home/u/foo\n' > "${dir}/d.desktop"

    bash "${TARGET_SCRIPT}" "${dir}" >/dev/null 2>&1
    local first
    first=$(cat "${dir}/d.desktop")

    bash "${TARGET_SCRIPT}" "${dir}" >/dev/null 2>&1
    local second
    second=$(cat "${dir}/d.desktop")

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${first}" == "${second}" ]]; then
        log_success "第二次执行为 no-op，内容不变"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "第二次执行改变了内容"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# 用例 E: 参数数量/目录校验失败时退出非 0
test_bad_args() {
    log_info "测试: 参数数量错误或目录不存在时退出非 0"

    # 无参数
    TESTS_RUN=$((TESTS_RUN + 1))
    if ! bash "${TARGET_SCRIPT}" >/dev/null 2>&1; then
        log_success "无参数时退出非 0"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "无参数时期望退出非 0"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # 目录不存在
    TESTS_RUN=$((TESTS_RUN + 1))
    if ! bash "${TARGET_SCRIPT}" "${TEST_TMP_DIR}/nonexistent" >/dev/null 2>&1; then
        log_success "目录不存在时退出非 0"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "目录不存在时期望退出非 0"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 主函数
#------------------------------------------------------------------------------
main() {
    echo "========================================"
    echo "  disable_desktop_path_key.sh 回归测试"
    echo "  (注释 desktop 的 Path= 键)"
    echo "========================================"
    echo ""

    # 前置检查: 目标脚本存在
    if [[ ! -f "${TARGET_SCRIPT}" ]]; then
        echo -e "${RED}[ERROR]${NC} 未找到脚本: ${TARGET_SCRIPT}"
        exit 1
    fi

    setup

    # 执行测试
    test_comment_path_keep_others
    test_already_commented_noop
    test_no_path_noop
    test_idempotent
    test_bad_args

    teardown

    # 输出测试结果
    echo ""
    echo "========================================"
    echo "  测试结果汇总"
    echo "========================================"
    echo "  总计: ${TESTS_RUN}"
    echo -e "  通过: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "  失败: ${RED}${TESTS_FAILED}${NC}"
    echo "========================================"

    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        exit 1
    fi

    exit 0
}

main "$@"
