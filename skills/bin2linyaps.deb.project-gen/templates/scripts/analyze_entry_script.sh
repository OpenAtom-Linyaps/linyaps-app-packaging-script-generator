#!/bin/bash
#=============================================================================
# analyze_entry_script.sh - 入口腳本位置參數風險檢測
#=============================================================================
# 功能：檢測目標文件是否為腳本，以及是否使用了 $1/$2 等位置參數
#       用於判斷 wrapper 生成時是否需要過濾 desktop Exec 中的非 freedesktop 參數
# 用法：analyze_entry_script.sh <target_file>
# 輸出：JSON 格式
#   {"is_script":true/false, "has_positional_params":true/false, "risk_level":"high"/"low"}
# 返回值：0=有風險（腳本且使用了位置參數），1=無風險，2=文件不存在
#
# 檢測原理：
#   主流 appimagetool 生成的 AppRun 使用 $0 和 $@ 管理參數，從不使用 $1-$9
#   非標準的 AppRun 可能使用 $1 來定位 AppDir（如 while 循環搜索 $path/$1）
#   這類腳本在 dde-application-manager 注入 --no-sandbox 等參數時會崩潰
#
# 參考：analysis_APPDIR_empty_root_cause.md
#=============================================================================

set -euo pipefail

# 輸出 JSON 並退出
output_and_exit() {
    local is_script="$1"
    local has_params="$2"

    if [ "${is_script}" = "true" ] && [ "${has_params}" = "true" ]; then
        local risk_level="high"
        local exit_code=0
    else
        local risk_level="low"
        local exit_code=1
    fi

    cat <<JSON_EOF
{"is_script":${is_script},"has_positional_params":${has_params},"risk_level":"${risk_level}"}
JSON_EOF
    exit "${exit_code}"
}

# 參數驗證
if [ $# -lt 1 ]; then
    echo "用法: $0 <target_file>" >&2
    output_and_exit "false" "false"
fi

target_file="$1"

# 檢查文件是否存在
if [ ! -f "${target_file}" ]; then
    echo "錯誤: 文件不存在: ${target_file}" >&2
    output_and_exit "false" "false"
fi

# Step 1: 判斷是否為腳本文件（shell script, python, perl 等）
# 使用 file 命令檢測腳本類型，排除 ELF 二進制和數據文件
is_script="false"
file_output=$(file "${target_file}" 2>/dev/null || echo "")

case "${file_output}" in
*"script"* | *"text"*)
    is_script="true"
    ;;
*"ELF"*)
    # ELF 二進制，不是腳本
    output_and_exit "false" "false"
    ;;
*)
    # 無法確定的文件類型（可能是二進制或未知格式）
    # 嘗試讀取文件頭判斷是否為 shebang 腳本
    if [ -r "${target_file}" ]; then
        first_line=$(head -1 "${target_file}" 2>/dev/null || echo "")
        case "${first_line}" in
        "#!"*)
            is_script="true"
            ;;
        *)
            output_and_exit "false" "false"
            ;;
        esac
    else
        output_and_exit "false" "false"
    fi
    ;;
esac

# Step 2: 檢測是否使用了 $1-$9 位置參數
# 檢測模式：
#   - $1, $2, ... $9（單獨的位置參數）
#   - ${1}, ${2}, ... ${9}（大括號形式的位置參數）
# 排除：
#   - $0（腳本名，無風險）
#   - $@, $*（所有參數，無風險）
#   - 註解行中的匹配
has_params="false"

if [ "${is_script}" = "true" ] && [ -r "${target_file}" ]; then
    # 使用 grep 搜索位置參數模式
    # - 排除以 # 開頭的註解行
    # - 只匹配 $1-$9 和 ${1}-${9}
    # - 不匹配 $0, $@, $*
    if grep -vE '^\s*#' "${target_file}" 2>/dev/null | grep -qE '(^|[^$])\$\{?[1-9]\}?'; then
        has_params="true"
    fi
fi

# 輸出結果
output_and_exit "${is_script}" "${has_params}"