#!/bin/bash
# fix_nonstd_lib_symlinks.sh - 修复非标准目录的 .so 软链接
# 在 binary/lib/ 下为所有非标准目录的 ELF 共享库创建相对路径软链接
# 使用方式: "${project_root}/scripts/fix_nonstd_lib_symlinks.sh" "${binary_dir}"

binary_dir="$1"
if [ -z "${binary_dir}" ]; then
    echo "Usage: $0 <binary_dir>"
    exit 1
fi

lib_dir="${binary_dir}/lib"
if [ ! -d "${binary_dir}" ]; then
    echo "Error: binary_dir does not exist: ${binary_dir}"
    exit 1
fi
mkdir -p "${lib_dir}"

tmpfile=$(mktemp)
trap 'rm -f "${tmpfile}"' EXIT

find "${binary_dir}" \( -type f -o -type l \) -name "*.so*" ! -path "${lib_dir}/*" -print0 2>/dev/null > "${tmpfile}"

# 第一遍：为所有非标准目录的 ELF 共享库创建软链接
while IFS= read -r -d '' entry; do
    real_path=$(readlink -f "${entry}" 2>/dev/null || true)
    if [ -z "${real_path}" ] || [ ! -f "${real_path}" ]; then
        continue
    fi

    file_type=$(file -b "${real_path}" 2>/dev/null || true)
    if ! echo "${file_type}" | grep -q "ELF.*shared object"; then
        continue
    fi

    lib_name=$(basename "${real_path}")
    if [ -z "${lib_name}" ]; then
        continue
    fi

    symlink_path="${lib_dir}/${lib_name}"

    if [ -e "${symlink_path}" ] || [ -L "${symlink_path}" ]; then
        existing_target=$(readlink -f "${symlink_path}" 2>/dev/null || true)
        if [ "${existing_target}" = "${real_path}" ]; then
            continue
        fi
    fi

    target_rel_path=$(realpath --relative-to="${lib_dir}" "${real_path}")
    ln -sf "${target_rel_path}" "${symlink_path}"
    echo "创建软链: ${symlink_path} -> ${target_rel_path}"
done < "${tmpfile}"

# 第二遍：为已创建的版本化软链补充基名软链
# 如 libfoo.so.1.0.0 已创建，则补充 libfoo.so -> libfoo.so.1.0.0
shopt -s nullglob
for entry in "${lib_dir}"/*.so*; do
    [ -e "${entry}" ] || [ -L "${entry}" ] || continue
    lib_name=$(basename "${entry}")

    base_name="${lib_name%%.so*}.so"
    if [ "${base_name}" = "${lib_name}" ]; then
        continue
    fi

    if [ ! -e "${lib_dir}/${base_name}" ]; then
        target=$(readlink -f "${entry}" 2>/dev/null || true)
        if [ -n "${target}" ]; then
            target_rel_path=$(realpath --relative-to="${lib_dir}" "${target}")
            ln -sf "${target_rel_path}" "${lib_dir}/${base_name}"
            echo "创建版本化软链: ${lib_dir}/${base_name} -> ${target_rel_path}"
        fi
    fi
done