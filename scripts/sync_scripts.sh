#!/bin/bash
# 同步各 skill 的共享可部署脚本
#
# 规范源: skills/bin2linyaps.deb.project-gen/scripts/
#   包含全部可部署脚本（handle_special_paths/dedup_desktop_files/
#   validate_bin_nesting/analyze_entry_script/download_missing_deps）
#
# 同步目标:
#   - skills/bin2linyaps.appimage.transfer/scripts/   (全部共享脚本)
#   - skills/bin2linyaps.tar.transfer/scripts/        (全部共享脚本)
#   - skills/bin2linyaps.external-missing-deps-fetch/scripts/ (仅 download_missing_deps.sh)
#
# skill 特有脚本（extract_appimage.sh、resolve_exec_command.sh、
# parse_appimage_metadata.sh、parse_build_config.sh、scan_executables.sh 等）不参与同步。
#
# 用法: ./scripts/sync_scripts.sh [--check]
#   --check   仅校验 MD5 是否一致，不做拷贝（返回 1 表示有差异）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CANONICAL="${REPO_ROOT}/skills/bin2linyaps.deb.project-gen/scripts"

# 共享脚本集合（规范源中需同步到其他 skill 的脚本）
SHARED_SCRIPTS=(
    "handle_special_paths.sh"
    "dedup_desktop_files.sh"
    "disable_desktop_path_key.sh"
    "validate_bin_nesting.sh"
    "analyze_entry_script.sh"
    "download_missing_deps.sh"
)

# 目标列表：每个目标用 "目录|同步的脚本列表(逗号分隔)"
# all 表示全部 SHARED_SCRIPTS
TARGETS=(
    "${REPO_ROOT}/skills/bin2linyaps.appimage.transfer/scripts|all"
    "${REPO_ROOT}/skills/bin2linyaps.tar.transfer/scripts|all"
    "${REPO_ROOT}/skills/bin2linyaps.external-missing-deps-fetch/scripts|download_missing_deps.sh"
)

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then
    CHECK_ONLY=1
fi

DIFF_COUNT=0

for target in "${TARGETS[@]}"; do
    target_dir="${target%%|*}"
    script_list="${target#*|}"

    [ -d "${target_dir}" ] || continue

    if [ "${script_list}" = "all" ]; then
        scripts=("${SHARED_SCRIPTS[@]}")
    else
        IFS=',' read -r -a scripts <<< "${script_list}"
    fi

    for s in "${scripts[@]}"; do
        src="${CANONICAL}/${s}"
        dst="${target_dir}/${s}"

        if [ ! -f "${src}" ]; then
            echo "WARN: 规范源脚本不存在，跳过: ${src}" >&2
            continue
        fi

        if [ -f "${dst}" ] && [ "$(md5sum < "${src}" | cut -d' ' -f1)" = "$(md5sum < "${dst}" | cut -d' ' -f1)" ]; then
            echo "OK   : ${dst}"
            continue
        fi

        echo "DIFF : ${dst} 与规范源不一致"
        DIFF_COUNT=$((DIFF_COUNT + 1))

        if [ "${CHECK_ONLY}" = "0" ]; then
            cp "${src}" "${dst}"
            chmod +x "${dst}"
            echo "      已从规范源复制: ${src}"
        fi
    done
done

echo ""
if [ "${DIFF_COUNT}" -eq 0 ]; then
    echo "结果: 所有共享脚本与规范源一致"
    exit 0
else
    if [ "${CHECK_ONLY}" = "1" ]; then
        echo "结果: ${DIFF_COUNT} 个脚本存在差异（--check 模式，未执行复制）"
    else
        echo "结果: ${DIFF_COUNT} 个脚本已同步为规范源版本"
    fi
    exit 1
fi
