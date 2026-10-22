# Desktop 文件字段合并：跨目录去重删除前合并 binary/ 字段到 files_res/

## Context

当前 `dedup_desktop_files.sh` 跨目录去重时，当 binary/ 的 desktop 文件与 files_res/ 的 Exec 匹配时，直接 `rm -f` 删除 binary/ 文件。binary/ 文件中的所有字段（`Name[zh_CN]`、`Name[zh_TW]`、`Comment`、`Categories`、`MimeType`、`Keywords` 等）全部丢失。

典型场景：files_res/ 模板只有 `Name=App` + `Name[zh_CN]=应用`（2 项本地化），而 binary/ 可能有 `Name[zh_TW]=應用`、`Name[ja]=アプリ`、`Comment[ja]=...` 等 >3 项本地化字段。删除后这些字段不可恢复。

## 合并规则

**files_res/ 权威 + binary/ 补充**：files_res/ 模板已有的字段值保留不变（模板权威），仅将 binary/ 中 files_res/ **缺失**的字段合并到 files_res/ 文件中，然后才删除 binary/ 文件。

### 合并字段范围

| 类别 | 字段 | 说明 |
|------|------|------|
| **本地化字段**（重点合并） | `Name[locale]`、`Comment[locale]`、`GenericName[locale]`、`Keywords[locale]` | 每个语言一个 key，不会冲突 |
| **非本地化字段**（仅当 files_res/ 缺失时补充） | `Comment`、`GenericName`、`Categories`、`MimeType`、`Keywords`、`Terminal`、`StartupNotify`、`StartupWMClass`、`Encoding` | 已存在则保留 files_res/ 值 |

**不合并的字段**：

- `Exec`：已由 pak_linyaps.sh 统一重写为 wrapper，两边一致
- `NoDisplay`：用于分组，files_res/ 值权威
- `Path`：后续由 `disable_desktop_path_key.sh` 注释掉
- `Type`：files_res/ 必填字段，应已存在
- `Icon`：files_res/ 模板权威（模板可能有专用图标）
- `Name`（无 locale）：files_res/ 权威

### 逐字段比较逻辑

1. **逐字段比较**：读取 binary/ 文件的每个字段 key（`=` 前的部分）
2. **files_res/ 已有 → 跳过**：如果 files_res/ 文件已有相同 key（包括 locale key），保留 files_res/ 值
3. **files_res/ 缺失 → 追加**：将 binary/ 的该字段追加到 files_res/ 文件末尾（`[Desktop Entry]` 段内）
4. **[Desktop Action] 段**：如果 binary/ 有 files_res/ 缺少的 `[Desktop Action xxx]` 段，整段追加；已有段内逐字段比较补充缺失 key

## Approach

### 新增函数：`merge_desktop_fields()`

在 `dedup_desktop_files.sh` 中 `dedup_desktop_files()` 之前新增 `merge_desktop_fields()` 函数：

```bash
# 将 source_desktop 的缺失字段合并到 target_desktop
# 规则：target 已有的 key 保留，仅追加 target 缺失的 key
merge_desktop_fields() {
    local source_desktop="$1"  # binary/ 文件（即将被删除）
    local target_desktop="$2"  # files_res/ 文件（保留）

    # 1. 提取 target 已有的所有 key（section|key 形式）
    local -A target_keys
    local current_section="[Desktop Entry]"
    while IFS= read -r line || [ -n "${line}" ]; do
        case "${line}" in
            \[*\]) current_section="${line}";;
            *=*) target_keys["${current_section}|${line%%=*}"]=1;;
        esac
    done < "${target_desktop}"

    # 2. 遍历 source 的字段，收集 target 缺失的
    current_section="[Desktop Entry]"
    local -a lines_to_append=()
    local in_missing_action_section=false

    while IFS= read -r line || [ -n "${line}" ]; do
        case "${line}" in
            \[*\])
                current_section="${line}"
                # [Desktop Action] 段：如果 target 没有这个 section，整段追加
                if [[ "${line}" == "[Desktop Action"* ]] && \
                   [ -z "${target_keys["${line}|"]+x}" ]; then
                    in_missing_action_section=true
                    lines_to_append+=("${line}")
                else
                    in_missing_action_section=false
                fi
                ;;
            *=*)
                if [ "${in_missing_action_section}" = true ]; then
                    lines_to_append+=("${line}")
                else
                    local key="${line%%=*}"
                    local full_key="${current_section}|${key}"
                    if [ -z "${target_keys["${full_key}"]+x}" ]; then
                        lines_to_append+=("${line}")
                    fi
                fi
                ;;
            "")
                if [ "${in_missing_action_section}" = true ]; then
                    lines_to_append+=("${line}")
                fi
                ;;
            *)
                # 注释行或其他：跳过
                ;;
        esac
    done < "${source_desktop}"

    # 3. 追加到 target 文件
    if [ ${#lines_to_append[@]} -gt 0 ]; then
        [ -n "$(tail -c1 "${target_desktop}")" ] && echo "" >> "${target_desktop}"
        local append_line
        for append_line in "${lines_to_append[@]}"; do
            echo "${append_line}" >> "${target_desktop}"
        done
        STAT_MERGED_FIELDS=$((STAT_MERGED_FIELDS + ${#lines_to_append[@]}))
        log_info "合并了 ${#lines_to_append[@]} 个字段: $(basename "${source_desktop}") -> $(basename "${target_desktop}")"
    fi
}
```

### ref 扫描增加 Exec → ref 文件路径关联数组

ref 扫描时新增 `ref_file_visible` / `ref_file_nodisplay` 关联数组（与 `ref_execs_visible[]` / `ref_execs_nodisplay[]` 平行），在 ref 循环中填充：

```bash
local -A ref_file_visible    # Exec -> ref 文件路径
local -A ref_file_nodisplay  # Exec -> ref 文件路径

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
    ...
done
```

### 跨目录去重命中时删除前先合并

```bash
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
```

### 统计输出

新增 `STAT_MERGED_FIELDS=0` 全局变量，合并时累加，最终报告中输出 `合并字段: N`。

## 边界情况处理

| 情况 | 处理 |
|------|------|
| binary/ 文件无字段可合并 | `lines_to_append` 为空，不修改 target，正常删除 |
| files_res/ 文件已包含所有 binary/ 字段 | 无字段追加，正常删除 |
| binary/ 有 `[Desktop Action]` 段而 files_res/ 没有 | 整段追加（section header + 其下所有字段） |
| binary/ 和 files_res/ 都有同名 `[Desktop Action]` 段 | files_res/ 段内已有 key 保留，binary/ 段内缺失 key 追加到该段末尾 |
| 文件编码/换行符不一致 | 按行读取，保持 UTF-8 LF |
| target 文件末尾无换行 | 追加前补一个空行 |

## 不改动的部分

- `pak_linyaps.sh`：无需修改，pipeline 顺序不变
- `disable_desktop_path_key.sh`：无需修改
- 跨目录去重的触发条件、Exec 匹配逻辑、NoDisplay 分组逻辑：不变
- 目录内去重（intra-dedup）：不涉及合并（同目录重复保留第一个）
- `cross_authoritative` 判定逻辑：不变

## Verification

```bash
bash skills/bin2linyaps.deb.project-gen/tests/test_dedup_desktop_files.sh
```

预期：所有 17 个测试通过（原有 12 个 + 新增 5 个合并测试，0 失败）。

关键新行为验证：

- `test_cross_merge_localized_names`：binary/ 有 `Name[zh_TW]`、`Name[ja]`、`Comment[ja]`，files_res/ 没有 → 合并后 files_res/ 包含这些字段
- `test_cross_merge_existing_field_preserved`：files_res/ 已有 `Comment=Template`，binary/ 有 `Comment=Binary` → 保留 `Comment=Template`
- `test_cross_merge_desktop_action_section`：binary/ 有 `[Desktop Action new-window]` 段，files_res/ 没有 → 整段追加
- `test_cross_merge_no_fields_to_merge`：两边内容完全一致 → 无追加，正常删除
- `test_cross_merge_no_binary_extra_fields`：binary/ 是 files_res/ 子集 → 无追加，正常删除

Demo 验证：

```bash
bash tests/demo_dedup_before_after.sh
```

合并后 origin `app.desktop` 应包含 `Name[zh_CN]=应用` + `Name[zh_TW]=應用` + `Name[ja]=アプリ` + `Comment[ja]=計算機`。
