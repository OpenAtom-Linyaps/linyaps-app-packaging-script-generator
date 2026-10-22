# Desktop 文件去重修复：NoDisplay 分组去重 + pak_linyaps.sh Exec 重写恢复

## Context

打包流程中 desktop 文件处理有两个 Bug：(1) `dedup_desktop_files.sh` 跨目录去重时，当 `files_res/` 权威则 blanket 删除 `binary/` 下所有非 NoDisplay 桌面文件，而非仅删除 Exec 匹配的；(2) `pak_linyaps.sh` 将所有桌面文件 Exec 无条件重写为 wrapper。同时需实现 NoDisplay 分组去重：NoDisplay=true 与非 NoDisplay 文件分属不同组，互不比较；同组内 Exec 完全一致才视为重复。此规则同时适用于目录内去重和跨目录去重。

## Desktop 处理最新逻辑（完整说明）

### 处理阶段顺序

```
pak_linyaps.sh build_pak()
  ├─ 1. Exec 重写（928-995行）：遍历所有 desktop，按优先级判定是否将 Exec 替换为 wrapper
  ├─ 2. 跨目录去重：dedup_desktop_files.sh binary/ --reference-dir files_res/
  └─ 3. 目录内去重：dedup_desktop_files.sh files_res/
```

### 阶段1：Exec 重写（pak_linyaps.sh）

遍历 `binary/` 和 `files_res/` 下所有 `.desktop` 文件，对每个文件的 `Exec=` 行：

1. 提取 `exec_value`（去 `env VAR=val` 前缀后的完整值）、`exec_bin_name`（第一个 token 的 basename）、`exec_args`（剩余参数）
2. **优先级1**：`echo "${exec_value}" | grep -qF "${binary_name}"` → 子串匹配则 `do_replace=true`
   - 覆盖 VSCodium 场景：`binary_name=vscodium`，`exec=/usr/share/vscodium/bin/codon %U` → 路径含 `vscodium` → 匹配
3. **优先级2**：若优先级1未匹配，且 `binary_name_is_original=true`（来自 CSV 配置非兜底重赋值），且 `find "${binary_dir}" -type f -name "${exec_bin_name}"` 有结果 → `do_replace=true`
4. 两个优先级都未匹配 → `do_replace=false`，Exec 行原样保留
5. `do_replace=true` 时：新 Exec = `${exec_target}` + 保留的 args（风险脚本过滤非 freedesktop 参数）

### 阶段2 & 3：去重（dedup_desktop_files.sh）

**核心规则：NoDisplay 分组**
- 每个桌面文件属于两个组之一：`visible`（非 NoDisplay）或 `nodisplay`（NoDisplay=true）
- 去重比较只在同组内进行：visible 只与 visible 比，nodisplay 只与 nodisplay 比
- 同组内完整 Exec 值（路径+参数，trim 后）完全一致才视为重复

**目录内去重**（单目录，无 `--reference-dir`）：
- 两个关联数组：`exec_to_file_visible` 和 `exec_to_file_nodisplay`
- 遍历目录下所有 desktop 文件：
  1. 提取 `exec_cmd`（完整 Exec 值）
  2. 判断 NoDisplay 状态选择对应映射
  3. 若映射中已有此 `exec_cmd` → 当前文件标记删除（重复）
  4. 若映射中无此 `exec_cmd` → 记入映射，保留

**跨目录去重**（target=binary/, reference=files_res/）：
- 扫描参考目录（files_res/）所有 desktop，收集完整 Exec 到两个数组：`ref_execs_visible[]` 和 `ref_execs_nodisplay[]`
- 从第一个 ref 文件提取 `ref_exec_binary`，用 `find -maxdepth 6` 校验该 binary 是否存在于 target 或 reference 目录 → 决定 `cross_authoritative`
- 遍历 target（binary/）所有 desktop 文件：
  1. 提取当前文件的 `exec_cmd` 和 NoDisplay 状态
  2. 选择同组的 ref Exec 数组（visible→`ref_execs_visible[]`，nodisplay→`ref_execs_nodisplay[]`）
  3. 若 `cross_dedup_active && cross_authoritative`，且当前 `exec_cmd` 与同组 ref 数组中某个值完全一致 → 删除当前文件
  4. 否则进入目录内去重逻辑（用同组映射判重）

**示例**：
```
files_res/ (ref):          binary/ (target):
  app.desktop              a.desktop  NoDisplay=true  Exec=/usr/bin/app %U
  NoDisplay=false          b.desktop  NoDisplay=false Exec=/usr/bin/app %U
  Exec=/usr/bin/app %U     c.desktop  NoDisplay=false Exec=/usr/bin/app %U
                           d.desktop  NoDisplay=false Exec=/usr/bin/other

结果：
  a.desktop: nodisplay 组，ref 无 nodisplay Exec → 无匹配 → 保留
  b.desktop: visible 组，ref 有相同 Exec → 删除
  c.desktop: visible 组，与 b.desktop 同组同 Exec → 目录内去重删除
  d.desktop: visible 组，Exec=/usr/bin/other 与 ref 不匹配 → 保留
```

## Approach

### 步骤1：修复 dedup_desktop_files.sh

**1a. 头部注释（18-23行）**：更新描述——跨目录仅删除 Exec 匹配的同组文件；NoDisplay 参与自身组去重。

**1b. is_nodisplay 注释（139行）**：改为"NoDisplay=true 文件参与自身组的去重"。

**1c. 双映射（233-236行）**：
```bash
local -A exec_to_file_visible
local -A exec_to_file_nodisplay
local -a files_to_delete
```

**1d. ref 扫描（254-270行）**：移除 NoDisplay 跳过；收集所有 ref 的完整 Exec：
- `ref_execs_visible=()` + `ref_execs_nodisplay=()` 普通数组
- 每个 ref 文件：提取 Exec，按 NoDisplay 状态 append 到对应数组
- `ref_exec_binary` 从第一个 ref 文件获取（任意组），用于 cross_authoritative 校验
- 统计 `ref_visible_count` 和 `ref_nodisplay_count`

**1e. cross_authoritative 条件（272-287行）**：`(ref_visible_count + ref_nodisplay_count) == 0` 时才跳过；否则 `cross_dedup_active=true`，`ref_exec_binary` 存在性校验逻辑不变。

**1f. 主循环（296-345行）**：移除 NoDisplay 无条件跳过块（298-305行）；移除 blanket 删除块（307-313行）；新逻辑：
```bash
for desktop_file in "${files_array[@]}"; do
    local exec_cmd
    exec_cmd=$(extract_exec_command "${desktop_file}")
    if [ -z "${exec_cmd}" ]; then
        log_warning "无法提取 Exec 命令: ${desktop_file}"
        continue
    fi
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
    if [ -z "${!current_map[${exec_cmd}]}" ]; then
        eval "${current_map}[\"\${exec_cmd}\"]=\"\${desktop_file}\""
        STAT_UNIQUE_FILES=$((STAT_UNIQUE_FILES + 1))
    else
        files_to_delete+=("${desktop_file}")
        STAT_DUPLICATE_FILES=$((STAT_DUPLICATE_FILES + 1))
        local existing_file="${!current_map[${exec_cmd}]}"
        log_warning "发现重复 Exec 命令: $(basename "${desktop_file}") 与 $(basename "${existing_file}") 相同 (${exec_cmd})"
    fi
done
```

**1g. 统计（363行）**：保留 `STAT_SKIPPED_FILES` 输出行（值始终 0，不再有跳过）。

### 步骤2：修复 pak_linyaps.sh（952-957行）

替换无条件 `do_replace=true`（空格缩进注释+tab缩进local行）为优先级匹配（全 tab 缩进）：
```bash
					local do_replace=false

					# 优先级1: Exec 行包含 binary_name → 替换为 wrapper
					if echo "${exec_value}" | grep -qF "${binary_name}"; then
						do_replace=true
					fi

					# 优先级2: binary_name 来自 CSV 原始配置且 exec_bin_name 也存在于 binary_dir → 强制替换
					if [ "${do_replace}" = false ] && [ "${binary_name_is_original}" = true ]; then
						if find "${binary_dir}" -type f -name "${exec_bin_name}" 2>/dev/null | grep -q .; then
							do_replace=true
						fi
					fi
```

### 步骤3：更新测试

**3a. test_intra_dir_nodisplay_kept（127-144行）**：更新名称为 `test_intra_dir_nodisplay_different_group`，更新 log_info/断言消息为"不同 NoDisplay 组不去重"。行为不变（NoDisplay 与非 NoDisplay 同 Exec，不同组 → 均保留）。

**3b. test_cross_nodisplay_always_kept（250-271行）**：更新名称为 `test_cross_nodisplay_group_isolation`，更新消息。行为不变（NoDisplay target 无 NoDisplay ref → 保留；非 NoDisplay target 有同组 ref → 删除）。

**3c. 新增 test_intra_dir_nodisplay_dedup_within_group**：两个 NoDisplay=true desktop，同 Exec `/usr/bin/handler %U` → 去重为 1。验证 NoDisplay 组内去重生效。

**3d. 新增 test_cross_authoritative_preserves_non_matching_exec**：
- ref: `app.desktop` Exec=`/usr/bin/app1`
- target: `a.desktop` Exec=`/usr/bin/app1`（应删）, `b.desktop` Exec=`/usr/bin/app2`（应保留）
- binary `app1` 存在于 target → cross_authoritative=true
- 验证仅 Exec 匹配的删除

**3e. main()（339-348行）**：注册两个新测试。

### 步骤4：导出实施方案到 docs/

创建 `docs/bin2linyaps-deb-desktop-dedup-fix-plan.md`，内容为本方案的完整描述，供团队查阅。格式遵循 `docs/` 现有惯例（参见 `docs/dispatch-random-tiebreak-plan.md`）：标题 + Context + Approach（含代码片段）+ Verification。文件内容直接取自本计划文件的 Context + Desktop 处理最新逻辑 + Approach + Verification 各节。

## Critical files & anchors

1. `skills/bin2linyaps.deb.project-gen/scripts/dedup_desktop_files.sh` — `dedup_desktop_files()` 233-369行：双映射、ref 扫描、主循环重构
2. `skills/bin2linyaps.deb.project-gen/templates/pak_linyaps.sh` — 952-957行：do_replace 优先级匹配恢复
3. `skills/bin2linyaps.deb.project-gen/tests/test_dedup_desktop_files.sh` — 测试更新与新增
4. `is_nodisplay()` 140-153行：返回 0=true/1=false，复用不改动
5. `extract_exec_command()` 157-177行：返回完整 Exec 值，复用不改动

## Verification

```bash
cd /media/ut005422/Data-2/linyaps-project/ai-labs/repos.git/repo.gitlab/linyaps-app-packaging-script-generator.master
bash skills/bin2linyaps.deb.project-gen/tests/test_dedup_desktop_files.sh
```

预期：所有测试通过（原有 10 个 + 新增 2 个 = 12 个 assertions，0 失败）。

关键新行为验证：
- `test_intra_dir_nodisplay_dedup_within_group`：两个 NoDisplay=true 同 Exec → 1 个文件保留
- `test_cross_authoritative_preserves_non_matching_exec`：Exec 不匹配的文件保留，Exec 匹配的删除
- `test_cross_nodisplay_group_isolation`：NoDisplay target 在无 NoDisplay ref 时保留，非 NoDisplay target 在有同组 ref 时删除

docs 导出验证：`ls docs/bin2linyaps-deb-desktop-dedup-fix-plan.md` 文件存在。

## Assumptions

- `binary_name_is_original` 变量在 Exec 重写循环外已声明（773行 true / 810行 false），循环内可读。
- `binary_dir`、`binary_name`、`exec_target`、`has_risk` 在循环外已设置。
- 跨目录去重时 ref 的 NoDisplay 文件也参与收集（不再跳过），但其 Exec 仅与 target 的 NoDisplay 文件比较。
