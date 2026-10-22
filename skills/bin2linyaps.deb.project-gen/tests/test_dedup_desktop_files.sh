#!/bin/bash
#==============================================================================
# 测试脚本: dedup_desktop_files.sh 功能测试
# 功能: 验证 dedup_desktop_files.sh 的去重逻辑
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
DEDUP_SCRIPT="${PROJECT_ROOT}/scripts/dedup_desktop_files.sh"

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

# 检查文件是否存在（存在返回 true）
file_exists() {
    [ -f "$1" ]
}

# 统计目录下 desktop 文件数量（find 顺序不保证，用数量断言更稳健）
desktop_count() {
    find "$1" -maxdepth 1 -name "*.desktop" -type f 2>/dev/null | wc -l
}

# 创建 desktop 文件
mkdesktop() {
    local file="$1"
    local exec_line="$2"
    local nodisplay="$3"
    mkdir -p "$(dirname "${file}")"
    {
        echo "[Desktop Entry]"
        echo "Name=$(basename "${file}" .desktop)"
        if [ -n "${exec_line}" ]; then
            echo "Exec=${exec_line}"
        fi
        if [ -n "${nodisplay}" ]; then
            echo "NoDisplay=${nodisplay}"
        fi
        echo "Icon=app"
    } > "${file}"
}

# 运行去重脚本（忽略 stderr）
run_dedup() {
    bash "${DEDUP_SCRIPT}" "$@" > /dev/null 2>&1
    return $?
}

#------------------------------------------------------------------------------
# 测试用例: 目录内去重 - 完整 Exec 值一致才去重
#------------------------------------------------------------------------------
test_intra_dir_exact_exec() {
    log_info "测试: 目录内去重 - 完整 Exec 值一致才去重"

    local target="${TEST_TMP_DIR}/intra"
    mkdir -p "${target}/share/applications"
    mkdesktop "${target}/share/applications/a.desktop" "/usr/bin/app %F"
    mkdesktop "${target}/share/applications/b.desktop" "/usr/bin/app %U"

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target}"
    if file_exists "${target}/share/applications/a.desktop" && file_exists "${target}/share/applications/b.desktop"; then
        log_success "同 binary 不同 args 不去重，两份均保留"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "同 binary 不同 args 不应去重"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # 相同 Exec 值应去重
    local target2="${TEST_TMP_DIR}/intra2"
    mkdir -p "${target2}/share/applications"
    mkdesktop "${target2}/share/applications/a.desktop" "/usr/bin/app %F"
    mkdesktop "${target2}/share/applications/b.desktop" "/usr/bin/app %F"

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target2}"
    if [ "$(desktop_count "${target2}/share/applications")" -eq 1 ]; then
        log_success "完整 Exec 值一致才去重（保留 1 份）"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "完整 Exec 值一致应去重为 1 份"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: 目录内去重 - NoDisplay 与非 NoDisplay 分属不同组，互不去重
#------------------------------------------------------------------------------
test_intra_dir_nodisplay_different_group() {
    log_info "测试: 目录内去重 - 不同 NoDisplay 组不去重"

    local target="${TEST_TMP_DIR}/nodisp"
    mkdir -p "${target}/share/applications"
    mkdesktop "${target}/share/applications/a.desktop" "/usr/bin/app %F" "true"
    mkdesktop "${target}/share/applications/b.desktop" "/usr/bin/app %F"

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target}"
    if file_exists "${target}/share/applications/a.desktop" && file_exists "${target}/share/applications/b.desktop"; then
        log_success "不同 NoDisplay 组不去重，均保留"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "不同 NoDisplay 组应均保留"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: 跨目录 - files_res 有 desktop 且 exec 存在于 binary -> 删光 binary 非 NoDisplay
#------------------------------------------------------------------------------
test_cross_authoritative_exec_in_binary() {
    log_info "测试: 跨目录 - files_res 权威，exec 存在于 binary/，删除 binary 非 NoDisplay desktop"

    local target="${TEST_TMP_DIR}/cross_auth_bin"
    local ref="${TEST_TMP_DIR}/cross_auth_ref"
    mkdir -p "${target}/share/applications"
    mkdir -p "${ref}/share/applications"
    # exec binary 存在于 binary/ 根目录
    touch "${target}/ppthelper-agent"
    mkdesktop "${ref}/share/applications/app.desktop" "/usr/bin/ppthelper-agent"
    mkdesktop "${target}/share/applications/a.desktop" "/usr/bin/ppthelper-agent"

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target}" --reference-dir "${ref}"
    if [ ! -f "${target}/share/applications/a.desktop" ]; then
        log_success "exec 存在时删除 binary/ 的非 NoDisplay desktop"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "exec 存在时应删除 binary/ 的非 NoDisplay desktop"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: 跨目录 - exec 存在于 files_res -> 删除 binary 非 NoDisplay
#------------------------------------------------------------------------------
test_cross_authoritative_exec_in_files_res() {
    log_info "测试: 跨目录 - exec 存在于 files_res/，删除 binary 非 NoDisplay desktop"

    local target="${TEST_TMP_DIR}/cross_auth_fr"
    local ref="${TEST_TMP_DIR}/cross_auth_fr_ref"
    mkdir -p "${target}/share/applications"
    mkdir -p "${ref}/share/applications"
    # exec binary 存在于 files_res/ 根目录
    touch "${ref}/ppthelper-agent"
    mkdesktop "${ref}/share/applications/app.desktop" "/usr/bin/ppthelper-agent"
    mkdesktop "${target}/share/applications/a.desktop" "/usr/bin/ppthelper-agent"

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target}" --reference-dir "${ref}"
    if [ ! -f "${target}/share/applications/a.desktop" ]; then
        log_success "exec 存在于 files_res/ 时删除 binary/ 的非 NoDisplay desktop"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "exec 存在于 files_res/ 时应删除 binary/ 的非 NoDisplay desktop"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: 跨目录 - exec 缺失 -> 回退保留 binary desktop
#------------------------------------------------------------------------------
test_cross_fallback_exec_missing() {
    log_info "测试: 跨目录 - exec 两目录均缺失，回退保留 binary desktop"

    local target="${TEST_TMP_DIR}/cross_fallback"
    local ref="${TEST_TMP_DIR}/cross_fallback_ref"
    mkdir -p "${target}/share/applications"
    mkdir -p "${ref}/share/applications"
    # 无 exec binary
    mkdesktop "${ref}/share/applications/app.desktop" "/usr/bin/nonexistent-app"
    mkdesktop "${target}/share/applications/a.desktop" "/usr/bin/ppthelper-agent"

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target}" --reference-dir "${ref}"
    if file_exists "${target}/share/applications/a.desktop"; then
        log_success "exec 缺失时回退保留 binary/ 的 desktop"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "exec 缺失时应回退保留 binary/ 的 desktop"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: 跨目录 - files_res 无 desktop -> 跳过，保留 binary desktop
#------------------------------------------------------------------------------
test_cross_no_ref_desktop() {
    log_info "测试: 跨目录 - files_res 无 desktop，跳过跨目录去重"

    local target="${TEST_TMP_DIR}/cross_noref"
    local ref="${TEST_TMP_DIR}/cross_noref_ref"
    mkdir -p "${target}/share/applications"
    mkdir -p "${ref}/share/applications"
    # files_res/ 无 desktop 文件
    mkdesktop "${target}/share/applications/a.desktop" "/usr/bin/app"

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target}" --reference-dir "${ref}"
    if file_exists "${target}/share/applications/a.desktop"; then
        log_success "files_res 无 desktop 时保留 binary/ 的 desktop"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "files_res 无 desktop 时应保留 binary/ 的 desktop"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: 跨目录 - NoDisplay 组隔离（NoDisplay target 无 NoDisplay ref 时保留）
#------------------------------------------------------------------------------
test_cross_nodisplay_group_isolation() {
    log_info "测试: 跨目录 - NoDisplay 组隔离，不同组互不比较"

    local target="${TEST_TMP_DIR}/cross_nodisp"
    local ref="${TEST_TMP_DIR}/cross_nodisp_ref"
    mkdir -p "${target}/share/applications"
    mkdir -p "${ref}/share/applications"
    touch "${target}/ppthelper-agent"
    mkdesktop "${ref}/share/applications/app.desktop" "/usr/bin/ppthelper-agent"
    mkdesktop "${target}/share/applications/a.desktop" "/usr/bin/ppthelper-agent" "true"
    mkdesktop "${target}/share/applications/b.desktop" "/usr/bin/ppthelper-agent"

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target}" --reference-dir "${ref}"
    if file_exists "${target}/share/applications/a.desktop" && [ ! -f "${target}/share/applications/b.desktop" ]; then
        log_success "NoDisplay target 在无 NoDisplay ref 时保留，非 NoDisplay target 在有同组 ref 时删除"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "NoDisplay 组隔离失败"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: 真实场景 - 带引号 Exec 路径 + 空格目录 + binary 位于深目录（opt/APP/）
#------------------------------------------------------------------------------
test_cross_real_deb_quoted_deep_path() {
    log_info "测试: 真实场景 - 带引号 Exec + 空格路径 + binary 位于 opt/APP/ 深度3"

    local target="${TEST_TMP_DIR}/cross_real"
    local ref="${TEST_TMP_DIR}/cross_real_ref"
    mkdir -p "${target}/share/applications"
    mkdir -p "${target}/opt/PPT遥控翻页"
    mkdir -p "${ref}/share/applications"
    # binary 位于 opt/APP/ 深度 3（真实 deb 布局）
    touch "${target}/opt/PPT遥控翻页/ppthelper-agent"
    # 带引号 Exec 路径 + 空格目录 + %U 参数（ppthelper-agent 真实 desktop）
    mkdesktop "${ref}/share/applications/app.desktop" '"/opt/PPT遥控翻页/ppthelper-agent" %U'
    mkdesktop "${target}/share/applications/a.desktop" '"/opt/PPT遥控翻页/ppthelper-agent" %U'

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target}" --reference-dir "${ref}"
    if [ ! -f "${target}/share/applications/a.desktop" ]; then
        log_success "引号路径正确解析 + 深目录 binary 检出，删除 binary/ 非 NoDisplay desktop"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "应能解析引号路径并在深目录检出 exec，删除 binary/ desktop"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: extract_exec_command 返回完整 Exec 值
#------------------------------------------------------------------------------
test_extract_exec_command_full_value() {
    log_info "测试: extract_exec_command 返回完整 Exec 值"

    local desktop="${TEST_TMP_DIR}/exec_test.desktop"
    mkdir -p "$(dirname "${desktop}")"
    mkdesktop "${desktop}" "/usr/bin/app %F"

    local result
    result=$(bash -c "
        funcs=\$(awk '/^extract_exec_command\\(\\) \{/,/^\}/' '${DEDUP_SCRIPT}')
        eval \"\$funcs\"
        extract_exec_command '${desktop}'
    " 2>/dev/null)

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${result}" == "/usr/bin/app %F" ]]; then
        log_success "extract_exec_command 返回完整 Exec 值: '${result}'"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "期望 '/usr/bin/app %F'，实际: '${result}'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: 目录内去重 - NoDisplay 组内去重（同组同 Exec 去重）
#------------------------------------------------------------------------------
test_intra_dir_nodisplay_dedup_within_group() {
    log_info "测试: 目录内去重 - NoDisplay 组内同 Exec 去重"

    local target="${TEST_TMP_DIR}/nodisp_dedup"
    mkdir -p "${target}/share/applications"
    mkdesktop "${target}/share/applications/a.desktop" "/usr/bin/handler %U" "true"
    mkdesktop "${target}/share/applications/b.desktop" "/usr/bin/handler %U" "true"

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target}"
    if [ "$(desktop_count "${target}/share/applications")" -eq 1 ]; then
        log_success "NoDisplay 组内同 Exec 去重为 1 份"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "NoDisplay 组内同 Exec 应去重为 1 份"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: 跨目录 - 权威模式仅删除 Exec 匹配的同组文件，保留 Exec 不匹配的
#------------------------------------------------------------------------------
test_cross_authoritative_preserves_non_matching_exec() {
    log_info "测试: 跨目录权威 - 仅删除 Exec 匹配，保留 Exec 不匹配"

    local target="${TEST_TMP_DIR}/cross_preserve"
    local ref="${TEST_TMP_DIR}/cross_preserve_ref"
    mkdir -p "${target}/share/applications"
    mkdir -p "${ref}/share/applications"
    touch "${target}/app1"
    mkdesktop "${ref}/share/applications/app.desktop" "/usr/bin/app1"
    mkdesktop "${target}/share/applications/a.desktop" "/usr/bin/app1"
    mkdesktop "${target}/share/applications/b.desktop" "/usr/bin/app2"

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target}" --reference-dir "${ref}"
    if [ ! -f "${target}/share/applications/a.desktop" ] && file_exists "${target}/share/applications/b.desktop"; then
        log_success "Exec 匹配的删除，Exec 不匹配的保留"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "应仅删除 Exec 匹配的，保留 Exec 不匹配的"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: 跨目录 - 合并 binary/ 缺失的本地化 Name 字段到 files_res/
#------------------------------------------------------------------------------
test_cross_merge_localized_names() {
    log_info "测试: 跨目录 - 合并 binary/ 缺失的本地化 Name 字段"

    local target="${TEST_TMP_DIR}/merge_loc"
    local ref="${TEST_TMP_DIR}/merge_loc_ref"
    mkdir -p "${target}/share/applications"
    mkdir -p "${ref}/share/applications"
    touch "${target}/app"
    # files_res/ 模板：只有 Name + Name[zh_CN]
    {
        echo "[Desktop Entry]"
        echo "Name=app"
        echo "Name[zh_CN]=应用"
        echo "Exec=/usr/bin/app"
        echo "Icon=app"
    } > "${ref}/share/applications/app.desktop"
    # binary/：有 Name[zh_TW]、Name[ja]、Comment[ja]
    {
        echo "[Desktop Entry]"
        echo "Name=app"
        echo "Name[zh_CN]=应用"
        echo "Name[zh_TW]=應用"
        echo "Name[ja]=アプリ"
        echo "Comment[ja]=計算機"
        echo "Exec=/usr/bin/app"
        echo "Icon=app"
    } > "${target}/share/applications/a.desktop"

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target}" --reference-dir "${ref}"
    # files_res/ 文件应合并 Name[zh_TW]、Name[ja]、Comment[ja]
    if grep -q "^Name\[zh_TW\]=應用$" "${ref}/share/applications/app.desktop" \
       && grep -q "^Name\[ja\]=アプリ$" "${ref}/share/applications/app.desktop" \
       && grep -q "^Comment\[ja\]=計算機$" "${ref}/share/applications/app.desktop"; then
        log_success "binary/ 缺失的本地化字段已合并到 files_res/"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "应合并 binary/ 缺失的本地化字段到 files_res/"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: 跨目录 - files_res/ 已有字段保留不变（不追加 binary/ 同 key 值）
#------------------------------------------------------------------------------
test_cross_merge_existing_field_preserved() {
    log_info "测试: 跨目录 - files_res/ 已有字段保留不变"

    local target="${TEST_TMP_DIR}/merge_keep"
    local ref="${TEST_TMP_DIR}/merge_keep_ref"
    mkdir -p "${target}/share/applications"
    mkdir -p "${ref}/share/applications"
    touch "${target}/app"
    # files_res/ 已有 Comment=Template
    {
        echo "[Desktop Entry]"
        echo "Name=app"
        echo "Comment=Template"
        echo "Exec=/usr/bin/app"
        echo "Icon=app"
    } > "${ref}/share/applications/app.desktop"
    # binary/ 有 Comment=Binary（同 key，应不覆盖）
    {
        echo "[Desktop Entry]"
        echo "Name=app"
        echo "Comment=Binary"
        echo "Exec=/usr/bin/app"
        echo "Icon=app"
    } > "${target}/share/applications/a.desktop"

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target}" --reference-dir "${ref}"
    if grep -q "^Comment=Template$" "${ref}/share/applications/app.desktop" \
       && ! grep -q "^Comment=Binary$" "${ref}/share/applications/app.desktop"; then
        log_success "files_res/ 已有字段值保留不变"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "files_res/ 已有字段应保留不变"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: 跨目录 - binary/ 有 [Desktop Action] 段而 files_res/ 没有 → 整段追加
#------------------------------------------------------------------------------
test_cross_merge_desktop_action_section() {
    log_info "测试: 跨目录 - 合并 [Desktop Action] 段"

    local target="${TEST_TMP_DIR}/merge_action"
    local ref="${TEST_TMP_DIR}/merge_action_ref"
    mkdir -p "${target}/share/applications"
    mkdir -p "${ref}/share/applications"
    touch "${target}/app"
    {
        echo "[Desktop Entry]"
        echo "Name=app"
        echo "Exec=/usr/bin/app"
        echo "Icon=app"
    } > "${ref}/share/applications/app.desktop"
    {
        echo "[Desktop Entry]"
        echo "Name=app"
        echo "Exec=/usr/bin/app"
        echo "Icon=app"
        echo ""
        echo "[Desktop Action new-window]"
        echo "Name=New Window"
        echo "Exec=/usr/bin/app --new-window"
    } > "${target}/share/applications/a.desktop"

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target}" --reference-dir "${ref}"
    if grep -q "^\[Desktop Action new-window\]$" "${ref}/share/applications/app.desktop" \
       && grep -q "^Name=New Window$" "${ref}/share/applications/app.desktop" \
       && grep -q "^Exec=/usr/bin/app --new-window$" "${ref}/share/applications/app.desktop"; then
        log_success "[Desktop Action] 段已整段追加到 files_res/"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "应整段追加 [Desktop Action] 段到 files_res/"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: 跨目录 - binary/ 所有字段 files_res/ 都有 → 无追加，正常删除
#------------------------------------------------------------------------------
test_cross_merge_no_fields_to_merge() {
    log_info "测试: 跨目录 - binary/ 字段与 files_res/ 完全一致，无追加"

    local target="${TEST_TMP_DIR}/merge_none"
    local ref="${TEST_TMP_DIR}/merge_none_ref"
    mkdir -p "${target}/share/applications"
    mkdir -p "${ref}/share/applications"
    touch "${target}/app"
    # 两个文件内容完全一致
    {
        echo "[Desktop Entry]"
        echo "Name=app"
        echo "Comment=hello"
        echo "Exec=/usr/bin/app"
        echo "Icon=app"
    } > "${ref}/share/applications/app.desktop"
    cp "${ref}/share/applications/app.desktop" "${target}/share/applications/a.desktop"

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target}" --reference-dir "${ref}"
    # binary/ 文件应被删除
    if [ ! -f "${target}/share/applications/a.desktop" ]; then
        log_success "无追加字段时正常删除 binary/ 文件"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "无追加字段时应正常删除 binary/ 文件"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 测试用例: 跨目录 - binary/ 字段是 files_res/ 子集 → 无追加
#------------------------------------------------------------------------------
test_cross_merge_no_binary_extra_fields() {
    log_info "测试: 跨目录 - binary/ 字段是 files_res/ 子集，无追加"

    local target="${TEST_TMP_DIR}/merge_subset"
    local ref="${TEST_TMP_DIR}/merge_subset_ref"
    mkdir -p "${target}/share/applications"
    mkdir -p "${ref}/share/applications"
    touch "${target}/app"
    # files_res/ 有 Comment、Categories（binary/ 没有）
    {
        echo "[Desktop Entry]"
        echo "Name=app"
        echo "Comment=hello"
        echo "Categories=Utility;"
        echo "Exec=/usr/bin/app"
        echo "Icon=app"
    } > "${ref}/share/applications/app.desktop"
    # binary/ 是子集
    {
        echo "[Desktop Entry]"
        echo "Name=app"
        echo "Exec=/usr/bin/app"
        echo "Icon=app"
    } > "${target}/share/applications/a.desktop"

    TESTS_RUN=$((TESTS_RUN + 1))
    run_dedup "${target}" --reference-dir "${ref}"
    # files_res/ 文件内容不应变化（无追加）
    local before_lines
    before_lines=$(grep -c "^" "${ref}/share/applications/app.desktop")
    # binary/ 应被删除
    if [ ! -f "${target}/share/applications/a.desktop" ] && [ "${before_lines}" -eq 6 ]; then
        log_success "binary/ 子集时无追加，正常删除"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "binary/ 子集时应无追加并正常删除"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

#------------------------------------------------------------------------------
# 主函数
#------------------------------------------------------------------------------
main() {
    echo "========================================"
    echo "  dedup_desktop_files.sh 功能测试"
    echo "========================================"
    echo ""

    setup

    # 执行测试
    test_extract_exec_command_full_value
    test_intra_dir_exact_exec
    test_intra_dir_nodisplay_different_group
    test_intra_dir_nodisplay_dedup_within_group
    test_cross_authoritative_exec_in_binary
    test_cross_authoritative_exec_in_files_res
    test_cross_authoritative_preserves_non_matching_exec
    test_cross_fallback_exec_missing
    test_cross_no_ref_desktop
    test_cross_nodisplay_group_isolation
    test_cross_real_deb_quoted_deep_path
    test_cross_merge_localized_names
    test_cross_merge_existing_field_preserved
    test_cross_merge_desktop_action_section
    test_cross_merge_no_fields_to_merge
    test_cross_merge_no_binary_extra_fields

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
