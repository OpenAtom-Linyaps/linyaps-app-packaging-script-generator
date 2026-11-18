#!/bin/bash
# Desktop 文件去重脚本
# 用于去除 share/applications/ 目录下相同 Exec 命令的 desktop 文件
#
# 功能：
# 1. 扫描指定目录下的所有 .desktop 文件
# 2. 提取每个文件的 Exec 命令（完整 Exec 值，仅 trim 首尾空白）
# 3. 按 Exec 命令分组，相同命令的文件只保留一份
# 4. 支持跨目录去重（依据参考目录 files_res/ 的 desktop 判定）
# 5. 跨目录去重删除前，合并 binary/ desktop 缺失字段到 files_res/（本地化 Name/Comment 等）
# 6. 删除重复文件，输出去重报告
#
# 去重策略：
# - 目录内去重基于「完整 Exec 值」进行去重（非文件内容哈希）
#   - 同 binary 不同 args 不视为重复（保留）
#   - Exec=/usr/bin/app 与 Exec=app 视为不同（保守不去重）
#   - 例如：Exec=/usr/bin/app %F 和 Exec=/usr/bin/app %U 保留两份
# - 跨目录去重（--reference-dir，target=binary, reference=files_res）：
#   - 删除 binary/ 重复 desktop 前，先将 binary/ 中 files_res/ 缺失的字段（本地化 Name/Comment、
#     Comment、GenericName、Categories、MimeType、Keywords 等）合并到 files_res/ 文件
#   - files_res/ 已有的字段值保留不变（模板权威），仅追加 files_res/ 缺失的 key
#   - [Desktop Action] 段：files_res/ 缺少的整段追加；已有段内逐字段比较补充缺失 key
# - NoDisplay=true 的 desktop 文件参与自身组的去重（与非 NoDisplay 文件分属不同组，互不比较）
#
# 用法：
#   dedup_desktop_files.sh <target_dir> [--verbose]
#   dedup_desktop_files.sh <target_dir> --reference-dir <ref_dir> [--verbose]
#
# 参数：
#   target_dir     - 目标目录路径（如 /project/files_res 或 /project/binary）
#   --reference-dir - 可选，参考目录路径。指定后，依据 ref_dir 的 desktop 判定是否删除 target_dir 的 desktop
#   --verbose      - 可选，显示详细日志
#
# 示例：
#   # 单目录去重：删除 files_res 内部重复的 desktop 文件
#   dedup_desktop_files.sh /project/files_res
#
#   # 跨目录去重：依据 files_res/ 判定是否删除 binary/ 的 desktop 文件
#   dedup_desktop_files.sh /project/binary --reference-dir /project/files_res

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 全局变量
VERBOSE=false
TARGET_DIR=""
REFERENCE_DIR=""
STAT_TOTAL_FILES=0
STAT_UNIQUE_FILES=0
STAT_DUPLICATE_FILES=0
STAT_SKIPPED_FILES=0
STAT_MERGED_FIELDS=0

# 日志函数
log_info() {
	echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
	echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1" >&2
}

# 显示使用说明
usage() {
	echo "用法: $0 <target_dir> [--reference-dir <ref_dir>] [--verbose]"
	echo ""
	echo "参数:"
	echo "  target_dir      - 目标目录路径"
	echo "  --reference-dir - 可选，参考目录路径。指定后依据 ref_dir 判定是否删除 target_dir 中重复的文件"
	echo "  --verbose       - 显示详细日志"
	echo ""
	echo "示例:"
	echo "  # 单目录去重"
	echo "  $0 /project/files_res"
	echo ""
	echo "  # 跨目录去重：依据 files_res/ 判定是否删除 binary/ 的 desktop"
	echo "  $0 /project/binary --reference-dir /project/files_res"
}

# 解析参数
parse_args() {
	if [ $# -lt 1 ]; then
		usage
		exit 1
	fi

	TARGET_DIR="$1"
	shift

	while [ $# -gt 0 ]; do
		case "$1" in
		--reference-dir)
			if [ $# -lt 2 ]; then
				log_error "--reference-dir 需要指定目录路径"
				exit 1
			fi
			REFERENCE_DIR="$2"
			shift 2
			;;
		--verbose)
			VERBOSE=true
			shift
			;;
		*)
			log_error "未知参数: $1"
			usage
			exit 1
			;;
		esac
	done

	# 验证目标目录存在
	if [ ! -d "${TARGET_DIR}" ]; then
		log_error "目标目录不存在: ${TARGET_DIR}"
		exit 1
	fi

	# 验证参考目录存在（如果指定）
	if [ -n "${REFERENCE_DIR}" ] && [ ! -d "${REFERENCE_DIR}" ]; then
		log_error "参考目录不存在: ${REFERENCE_DIR}"
		exit 1
	fi
}

# 检查 desktop 文件是否设置了 NoDisplay=true
# NoDisplay=true 文件参与自身组的去重（与非 NoDisplay 文件分属不同组）
is_nodisplay() {
	local desktop_file="$1"
	local nodisplay_line
	nodisplay_line=$(grep -E "^NoDisplay=" "${desktop_file}" 2>/dev/null | head -n 1)
	if [ -z "${nodisplay_line}" ]; then
		return 1 # 非 NoDisplay
	fi
	local nodisplay_value="${nodisplay_line#NoDisplay=}"
	# 忽略大小写比较
	if [ "${nodisplay_value,,}" = "true" ]; then
		return 0 # 是 NoDisplay=true
	fi
	return 1
}

# 提取 Exec 命令（返回完整 Exec 值，仅 trim 首尾空白）
# 不再移除路径或参数，以保证精确匹配（同 binary 不同 args 不去重）
extract_exec_command() {
	local desktop_file="$1"
	local exec_line

	# 读取 Exec 行
	exec_line=$(grep -E "^Exec=" "${desktop_file}" | head -n 1)

	if [ -z "${exec_line}" ]; then
		echo ""
		return
	fi

	# 提取 Exec= 后面的内容
	local exec_value="${exec_line#Exec=}"

	# 仅 trim 首尾空白，保留完整值（路径与参数）
	exec_value="${exec_value#"${exec_value%%[![:space:]]*}"}"
	exec_value="${exec_value%"${exec_value##*[![:space:]]}"}"

	echo "${exec_value}"
}

# 提取 exec 的二进制名（仅用于跨目录去重的 exec 存在性校验）
# 例如：/usr/bin/app %F -> app
# 处理带引号路径："/opt/My App/app" %U -> app
get_exec_binary_name() {
	local exec_value="$1"
	local first_token

	# 移除 env VAR=val 前缀（与 pak_linyaps 保持一致）
	exec_value=$(echo "${exec_value}" | sed 's/^env \(\S*=\S*\s\)*//')
	first_token=$(echo "${exec_value}" | awk '{print $1}')

	if [ -z "${first_token}" ]; then
		echo ""
		return
	fi

	# 去除首尾引号（desktop 中 Exec 路径可能带双引号）
	first_token="${first_token#\"}"
	first_token="${first_token%\"}"

	basename "${first_token}"
}

# 字段合并函数：将 binary/ desktop 的缺失字段合并到 files_res/ desktop
# 规则：target 已有的 key 保留（模板权威），仅追加 target 缺失的 key
# 本地化字段（Name[locale]、Comment[locale] 等）按 key（含 locale）逐个比较，不冲突
# [Desktop Action] 段：target 缺少的整段追加；已有段内逐字段比较补充缺失 key 到段末尾
merge_desktop_fields() {
	local source_desktop="$1" # binary/ 文件（即将被删除）
	local target_desktop="$2" # files_res/ 文件（保留）

	# 1. 读取 target 文件到数组，并记录每个 section 的行号范围（1-based 闭区间）
	local -a target_lines=()
	local -A section_ranges=() # "[Desktop Entry]" -> "start:end"
	local -A target_keys=()    # "[Desktop Entry]|Name" -> 1
	local current_section="[Desktop Entry]"
	local section_start=1
	local line_num=0

	while IFS= read -r line || [ -n "${line}" ]; do
		line_num=$((line_num + 1))
		target_lines+=("${line}")
		case "${line}" in
		\[*\])
			if [ ${line_num} -gt 1 ]; then
				section_ranges["${current_section}"]="${section_start}:$((line_num - 1))"
			fi
			current_section="${line}"
			section_start=${line_num}
			;;
		*=*)
			target_keys["${current_section}|${line%%=*}"]=1
			;;
		esac
	done <"${target_desktop}"
	section_ranges["${current_section}"]="${section_start}:${line_num}"

	# 2. 遍历 source，收集缺失字段和缺失整段
	#    missing_in_section["[Desktop Entry]"]="line1\nline2"  — 已有 section 中缺失的字段
	#    missing_section_lines:  数组，每个元素是一个完整缺失 section 的所有行（$'\n' 分隔）
	local -A missing_in_section=()
	local -a missing_section_lines=()
	local -a cur_missing_section=()
	local in_missing_section=false
	current_section="[Desktop Entry]"

	while IFS= read -r line || [ -n "${line}" ]; do
		case "${line}" in
		\[*\])
			# 关闭上一个 missing section
			if [ "${in_missing_section}" = true ]; then
				missing_section_lines+=("$(printf '%s\n' "${cur_missing_section[@]}")")
				cur_missing_section=()
				in_missing_section=false
			fi
			current_section="${line}"
			if [ -z "${section_ranges["${current_section}"]+x}" ]; then
				in_missing_section=true
				cur_missing_section=("${line}")
			fi
			;;
		*=*)
			if [ "${in_missing_section}" = true ]; then
				cur_missing_section+=("${line}")
			else
				local key="${line%%=*}"
				local full_key="${current_section}|${key}"
				if [ -z "${target_keys["${full_key}"]+x}" ]; then
					local prev="${missing_in_section["${current_section}"]}"
					if [ -n "${prev}" ]; then
						missing_in_section["${current_section}"]="${prev}"$'\n'"${line}"
					else
						missing_in_section["${current_section}"]="${line}"
					fi
				fi
			fi
			;;
		"")
			if [ "${in_missing_section}" = true ]; then
				cur_missing_section+=("${line}")
			fi
			;;
		*)
			# 注释行：仅当在 missing section 内时保留
			if [ "${in_missing_section}" = true ]; then
				cur_missing_section+=("${line}")
			fi
			;;
		esac
	done <"${source_desktop}"
	if [ "${in_missing_section}" = true ]; then
		missing_section_lines+=("$(printf '%s\n' "${cur_missing_section[@]}")")
	fi

	# 3. 计算总追加行数
	local total_to_append=0
	local sec
	for sec in "${!missing_in_section[@]}"; do
		total_to_append=$((total_to_append + $(printf '%s\n' "${missing_in_section["${sec}"]}" | wc -l)))
	done
	local msl
	for msl in "${missing_section_lines[@]}"; do
		total_to_append=$((total_to_append + $(printf '%s\n' "${msl}" | wc -l)))
	done

	if [ ${total_to_append} -eq 0 ]; then
		return 0
	fi

	# 4. 重建 target 文件
	#    a) 已有 section：在 section 末尾插入缺失字段
	#    b) 缺失 section：整段追加到文件末尾
	local -a new_lines=()
	current_section="[Desktop Entry]"
	local i
	for i in "${!target_lines[@]}"; do
		local tline="${target_lines[$i]}"
		new_lines+=("${tline}")

		case "${tline}" in
		\[*\]) current_section="${tline}" ;;
		esac

		# 到达 section 最后一行时插入缺失字段
		local range="${section_ranges["${current_section}"]}"
		local range_end="${range##*:}"
		if [ "$((i + 1))" = "${range_end}" ]; then
			local missing="${missing_in_section["${current_section}"]}"
			if [ -n "${missing}" ]; then
				while IFS= read -r mline || [ -n "${mline}" ]; do
					[ -n "${mline}" ] && new_lines+=("${mline}")
				done <<<"${missing}"
			fi
		fi
	done

	# 4b. 追加 target 没有的完整 section
	for msl in "${missing_section_lines[@]}"; do
		# 确保前面有空行分隔
		if [ ${#new_lines[@]} -gt 0 ] && [ -n "${new_lines[-1]}" ]; then
			new_lines+=("")
		fi
		while IFS= read -r mline || [ -n "${mline}" ]; do
			new_lines+=("${mline}")
		done <<<"${msl}"
		# 去掉 section 末尾的空行（如果有），保持文件整洁
		while [ ${#new_lines[@]} -gt 0 ] && [ -z "${new_lines[-1]}" ]; do
			unset 'new_lines[-1]'
		done
	done

	# 5. 写回 target 文件
	local tmp_file
	tmp_file=$(mktemp)
	local nl
	for nl in "${new_lines[@]}"; do
		printf '%s\n' "${nl}"
	done >"${tmp_file}"
	mv "${tmp_file}" "${target_desktop}"

	STAT_MERGED_FIELDS=$((STAT_MERGED_FIELDS + total_to_append))
	log_info "合并了 ${total_to_append} 个字段: $(basename "${source_desktop}") -> $(basename "${target_desktop}")"
}

# 去重函数
dedup_desktop_files() {
	local apps_dir="${TARGET_DIR}/share/applications"

	# 检查 applications 目录是否存在
	if [ ! -d "${apps_dir}" ]; then
		log_info "applications 目录不存在，跳过去重"
		return 0
	fi

	# 查找所有 desktop 文件
	local desktop_files
	desktop_files=$(find "${apps_dir}" -maxdepth 1 -name "*.desktop" -type f 2>/dev/null || true)

	if [ -z "${desktop_files}" ]; then
		log_info "未找到 desktop 文件，跳过去重"
		return 0
	fi

	# 转换为数组
	local -a files_array
	readarray -t files_array <<<"${desktop_files}"
	STAT_TOTAL_FILES=${#files_array[@]}

	if [ ${STAT_TOTAL_FILES} -eq 0 ]; then
		log_info "未找到 desktop 文件，跳过去重"
		return 0
	fi

	log_info "扫描到 ${STAT_TOTAL_FILES} 个 desktop 文件"

	# 关联数组：Exec 命令 -> 第一个文件路径（按 NoDisplay 分组）
	local -A exec_to_file_visible
	local -A exec_to_file_nodisplay
	# 数组：需要删除的文件
	local -a files_to_delete

	# 跨目录去重判定状态
	local cross_dedup_active=false
	local cross_authoritative=false

	# 如果指定了参考目录，依据参考目录的 desktop 判定跨目录去重策略
	if [ -n "${REFERENCE_DIR}" ]; then
		local ref_apps_dir="${REFERENCE_DIR}/share/applications"
		if [ -d "${ref_apps_dir}" ]; then
			local ref_desktop_files
			ref_desktop_files=$(find "${ref_apps_dir}" -maxdepth 1 -name "*.desktop" -type f 2>/dev/null || true)

			if [ -n "${ref_desktop_files}" ]; then
				log_info "分析参考目录 ${REFERENCE_DIR} 中的 desktop 文件..."
				local -a ref_files_array
				readarray -t ref_files_array <<<"${ref_desktop_files}"

				local ref_visible_count=0
				local ref_nodisplay_count=0
				local ref_exec_binary=""
				local -a ref_execs_visible=()
				local -a ref_execs_nodisplay=()
				local -A ref_file_visible
				local -A ref_file_nodisplay
				for ref_file in "${ref_files_array[@]}"; do
					local ref_exec
					ref_exec=$(extract_exec_command "${ref_file}")
					if is_nodisplay "${ref_file}"; then
						ref_nodisplay_count=$((ref_nodisplay_count + 1))
						ref_execs_nodisplay+=("${ref_exec}")
						ref_file_nodisplay["${ref_exec}"]="${ref_file}"
					else
						ref_visible_count=$((ref_visible_count + 1))
						ref_execs_visible+=("${ref_exec}")
						ref_file_visible["${ref_exec}"]="${ref_file}"
					fi
					# 从第一个 ref 文件提取 ref_exec_binary（任意组），用于 cross_authoritative 校验
					if [ -z "${ref_exec_binary}" ] && [ -n "${ref_exec}" ]; then
						ref_exec_binary=$(get_exec_binary_name "${ref_exec}")
					fi
				done

				if [ $((ref_visible_count + ref_nodisplay_count)) -eq 0 ]; then
					log_info "参考目录中无 desktop 文件，跳过跨目录去重"
				else
					log_info "参考目录中存在 ${ref_visible_count} 个可见 + ${ref_nodisplay_count} 个 NoDisplay desktop 文件"
					cross_dedup_active=true

					# 校验参考 desktop 的 exec binary 是否存在于 binary/ 或 files_res/
					# 真实布局中 binary 可位于 opt/APP/app、usr/bin/app 等深度路径，故用足够大的 maxdepth
					if [ -n "${ref_exec_binary}" ] &&
						find "${TARGET_DIR}" "${REFERENCE_DIR}" -maxdepth 6 -type f -name "${ref_exec_binary}" 2>/dev/null | grep -q .; then
						log_info "参考 desktop 的 exec binary (${ref_exec_binary}) 存在，files_res/ 作为权威来源"
						cross_authoritative=true
					else
						log_warning "参考 desktop 的 exec binary (${ref_exec_binary}) 不存在于 binary/ 或 files_res/，回退保留 binary/ 的 desktop"
					fi
				fi
			else
				log_info "参考目录中无 desktop 文件，跳过跨目录去重"
			fi
		else
			log_info "参考目录中不存在 applications 目录，跳过参考分析"
		fi
	fi

	# 遍历所有 desktop 文件
	for desktop_file in "${files_array[@]}"; do
		# 提取 Exec 命令
		local exec_cmd
		exec_cmd=$(extract_exec_command "${desktop_file}")

		if [ -z "${exec_cmd}" ]; then
			log_warning "无法提取 Exec 命令: ${desktop_file}"
			continue
		fi

		# 判断 NoDisplay 状态，选择对应组
		local is_nd=false
		if is_nodisplay "${desktop_file}"; then
			is_nd=true
		fi

		# 选择同组的 ref Exec 数组
		local -a ref_execs_to_check=()
		if [ "${is_nd}" = true ]; then
			ref_execs_to_check=("${ref_execs_nodisplay[@]}")
		else
			ref_execs_to_check=("${ref_execs_visible[@]}")
		fi

		# 跨目录去重：Exec 精确匹配同组 ref
		if [ "${cross_dedup_active}" = true ] && [ "${cross_authoritative}" = true ]; then
			local matched=false
			for ref_exec in "${ref_execs_to_check[@]}"; do
				if [ "${exec_cmd}" = "${ref_exec}" ]; then
					matched=true
					break
				fi
			done
			if [ "${matched}" = true ]; then
				# 找到匹配的 ref 文件路径，删除前先合并 binary/ 缺失字段到 files_res/
				local matched_ref_file=""
				if [ "${is_nd}" = true ]; then
					matched_ref_file="${ref_file_nodisplay["${exec_cmd}"]}"
				else
					matched_ref_file="${ref_file_visible["${exec_cmd}"]}"
				fi
				if [ -n "${matched_ref_file}" ] && [ -f "${matched_ref_file}" ]; then
					merge_desktop_fields "${desktop_file}" "${matched_ref_file}"
				fi
				files_to_delete+=("${desktop_file}")
				STAT_DUPLICATE_FILES=$((STAT_DUPLICATE_FILES + 1))
				log_warning "files_res/ 权威，删除 binary/ 中重复 desktop (Exec 匹配): $(basename "${desktop_file}")"
				continue
			fi
		fi

		# 目录内去重：按 NoDisplay 组选择映射
		local current_map
		if [ "${is_nd}" = true ]; then
			current_map="exec_to_file_nodisplay"
		else
			current_map="exec_to_file_visible"
		fi

		local existing_file
		existing_file=$(eval echo "\"\${${current_map}[\"\${exec_cmd}\"]}\"" 2>/dev/null)
		if [ -z "${existing_file}" ]; then
			eval "${current_map}[\"\${exec_cmd}\"]=\"\${desktop_file}\""
			STAT_UNIQUE_FILES=$((STAT_UNIQUE_FILES + 1))
		else
			files_to_delete+=("${desktop_file}")
			STAT_DUPLICATE_FILES=$((STAT_DUPLICATE_FILES + 1))
			log_warning "发现重复 Exec 命令: $(basename "${desktop_file}") 与 $(basename "${existing_file}") 相同 (${exec_cmd})"
		fi
	done

	# 删除重复文件
	if [ ${#files_to_delete[@]} -gt 0 ]; then
		log_info "开始删除 ${#files_to_delete[@]} 个重复文件..."
		for file_to_delete in "${files_to_delete[@]}"; do
			rm -f "${file_to_delete}"
			if [ "${VERBOSE}" = "true" ]; then
				log_info "  已删除: $(basename "${file_to_delete}")"
			fi
		done
	fi

	# 输出统计
	echo ""
	log_success "Desktop 文件去重完成"
	log_info "  总文件数: ${STAT_TOTAL_FILES}"
	log_info "  跳过 (NoDisplay): ${STAT_SKIPPED_FILES}"
	log_info "  唯一文件: ${STAT_UNIQUE_FILES}"
	log_info "  删除重复: ${STAT_DUPLICATE_FILES}"
	log_info "  合并字段: ${STAT_MERGED_FIELDS}"

	if [ ${STAT_DUPLICATE_FILES} -gt 0 ]; then
		log_warning "已去除 ${STAT_DUPLICATE_FILES} 个重复 desktop 文件"
	fi
}

# 主函数
main() {
	parse_args "$@"
	dedup_desktop_files
}

# 执行主函数
main "$@"
