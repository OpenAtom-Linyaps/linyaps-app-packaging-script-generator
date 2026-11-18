# 跨 Skill 同步：dedup_desktop_files.sh + pak_linyaps.sh Exec 替换

## Context

`deb.project-gen` 工作区有两项未提交修复：
1. `dedup_desktop_files.sh`：新增 `merge_desktop_fields()` 字段合并 + NoDisplay 分组去重（379→570 行）
2. `pak_linyaps.sh` Exec 替换：从无条件替换改为两优先级 `do_replace`（Exec 含 binary_name → 替换；exec_bin_name 存在于 binary_dir 且 binary_name 来自原始配置 → 强制替换；否则不替换）

`tar.transfer` 和 `appimage.transfer` 均落后。需同步这两项修复，使三个 skill 的 desktop 处理行为一致。

## Approach

### Step 1: 同步 dedup_desktop_files.sh（直接覆盖）

直接 `cp` deb 版到 tar 和 appimage。该脚本纯 desktop 文件处理，与 srcType 无关。同步后三副本 0 diff。

### Step 2-3: tar.transfer pak_linyaps.sh

**变量语义适配**：tar 的 binary_name 自动提取发生在进入 `if [ -n "${binary_name}" ]` 块之前。

- 删除 `is_custom_binary_name`（原注释块 + 赋值），改为 `local binary_name_is_original=true`
- 在 `extract_binary_name_from_desktop` 赋值后设 `binary_name_is_original=false`
  - 用户指定 binary_name → `true`；自动提取 → `false`。与 deb 语义一致
- 替换 Exec 替换双分支（客製化模式 / 自動偵測模式）为两优先级 `do_replace`

### Step 4-5: appimage.transfer pak_linyaps.sh

**变量声明**：appimage 入口检测链（binary_name → AppRun → AppRun.wrapped → resolve_exec_command.sh）与 deb/tar 不同。

```bash
local binary_name_is_original=false
if [ -n "${binary_name}" ]; then
    binary_name_is_original=true
fi
```

appimage 的 fallback 路径将结果存入 `wrapper_target` 而非 `binary_name`，故 `binary_name_is_original` 不需在 fallback 中设 false。

**优先级1 双匹配 + 空字符串守卫**：

appimage 入口可能来自 AppRun 而非 binary_name，Exec 行可能包含 `AppRun` 而非 binary_name。优先级1 同时匹配 `binary_name` 和 `wrapper_target`：

```bash
if [ -n "${binary_name}" ] && echo "${exec_value}" | grep -qF "${binary_name}"; then
    do_replace=true
elif [ -n "${wrapper_target}" ] && echo "${exec_value}" | grep -qF "${wrapper_target}"; then
    do_replace=true
fi
```

**空字符串防护**：`wrapper_target` 为空且 `binary_name` 也为空时，`grep -qF ""` 会匹配所有行。两分支 `-n` 守卫确保空值时跳过匹配。

变量对应关系：`exec_target`=`${app_prefix}.wrapper`、`has_risk`、`binary_dir`=`${build_tmp_dir}/binary/` 均在 appimage 中已定义。

### Step 6: SKILL.md 文档更新

tar.transfer/SKILL.md 和 appimage.transfer/SKILL.md 的職責邊界表中 Exec 描述统一改为「兩優先級匹配替換為 wrapper」。

## Verification

- **V1**：三副本 dedup_desktop_files.sh `diff` 均 0 输出
- **V2**：`bash -n` 两份 pak_linyaps.sh 无错误
- **V3**：throwaway 脚本验证选择性替换（优先级1 匹配 / 两优先级均不匹配 / 优先级2 匹配）
- **V4**：appimage 优先级1 双匹配验证（`wrapper_target=AppRun` + `binary_name=""`）
- **V5**：dedup 调用方式未变（仅脚本内容更新，调用参数一致）

权威来源：本计划文件 `local://cross-skill-sync-plan.md` 和 deb 参考实现 `skills/bin2linyaps.deb.project-gen/templates/pak_linyaps.sh`。
