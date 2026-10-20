# Plan: bin2linyaps.debug — 调试纠正 SKILL（二进制打包 agent 适配）

## 目标

为当前 agent（`linyaps-app-packaging-script-generator`，二进制打包：deb/tar/AppImage → 玲珑）新增调试纠正 skill `bin2linyaps.debug`，参照 `examples/debian-rules-to-linyaps-rules-dev/skills/src2linyaps.debug` 的五阶段工作流，适配为当前 agent 的二进制打包 skill 生态。关键集成点：当检测到缺失动态库且不可作为 runtime-depends 时，调用 `bin2linyaps.external-missing-deps-fetch` 补全。

## 变更范围

|文件|操作|
|---|---|
|`skills/bin2linyaps.debug/SKILL.md`|**新建**：调试纠正 skill 完整定义（五阶段工作流）|
|`skills/bin2linyaps.debug/ll-builder.command.reference.md`|**新建**：`ll-builder extract` 命令参考（从 reference 示例复制）|
|`agents/deb-linglong-packer.agent.md`|**修改**：skills 表新增 `bin2linyaps.debug` 行|
|`docs/bin2linyaps-debug-skill-plan.md`|**新建**：实施方案留档（代码改动前导出，内容与本计划一致）|

## 设计决策

### 决策1：`user-invocable: false`（遵循当前仓库约定）

当前仓库所有 skill 均 `user-invocable: false`（agent 间接调用），参考示例为 `user-invocable: true`。遵循当前仓库约定，新 skill 设为 `false`。

**理由**：`deb-linglong-packer.agent.md` L43 明确「各 skill `user-invocable: false`，只能经 agent 间接调用」；constraints SKILL §7 约束运行期不把 skill 当具名工具调用。

### 决策2：适配二进制打包 skill 生态（非源码打包）

参考示例是源码打包（debian rules → 玲珑），调用 `src2linyaps.debian.*` / `src2linyaps.source.*` skills。当前 agent 是二进制打包（deb/tar/AppImage → 玲珑），修复阶段调用当前仓库的 skills：

|诊断问题|参考示例调用的 skill|当前 agent 调用的 skill|
|---|---|---|
|结构验证问题|`src2linyaps.debian.build-res-generate`|`bin2linyaps.validate-structure` + `bin2linyaps.fix`|
|YAML 格式/base/runtime 错误|`src2linyaps.debian.build-res-generate`|`bin2linyaps.fix`|
|缺失动态库依赖|（参考示例无此场景）|**`bin2linyaps.external-missing-deps-fetch`**（核心集成点）|
|二次 YAML 校验|`validate-linglong-yaml.py`|`bin2linyaps.compat-testing` 的 `validate_linglong_yaml.py`|

### 决策3：缺失动态库检测 + external-missing-deps-fetch 集成

**检测入口**（阶段二分析）：
1. `missing_deps.json`/`missing_deps.csv` 存在（由 `compat-testing` step3 的 `ll-builder build` 生成，路径记录在 `reports/<pkg>/build_meta.json`）
2. 构建失败日志（`build.log`）中含 `cannot open shared object file` / `No such file or directory`（`.so` 相关）

**修复调度**（阶段三）：
- 缺失库**可作为 runtime-depends**（deb 包 `Depends` 中已声明的标准库）→ 交由 `bin2linyaps.fix` 修复（追加到 `buildext.apt.depends` 或 `runtime.depends`）
- 缺失库**不可作为 runtime-depends**（非标准包、私有 `.so`、第三方库）→ **调用 `bin2linyaps.external-missing-deps-fetch`**：
  ```bash
  "${skills_root}/bin2linyaps.external-missing-deps-fetch/scripts/fetch_missing_deps.sh" \
    --project-dir="<project_dir>" \
    --build-tmp-dir="<build_tmp_dir>"
  ```
  - `build_tmp_dir` 从 `reports/<pkg>/build_meta.json` 的 `build_tmp_dir` 字段获取
  - `fetch_missing_deps.sh` 执行：apt-file 反查 `.so` → 包名 → apt-cache 核验 → ruamel.yaml 追加 `buildext.apt.depends` → 生成 `missing_deps_urls.conf`
  - 约束：**绝不修改 `build_tmp_dir`**；只执行一次；遵循 constraints §5 依赖核验门禁

**并列关系**：`bin2linyaps.fix`（结构问题）与 `bin2linyaps.external-missing-deps-fetch`（缺失库）是并列关系，无数据依赖，可任意顺序或并行。建议先 fix 后 fetch（fix 的 ruamel.yaml dump 可能重排格式，fetch 在已格式化文件上追加避免冲突）。

### 决策4：构建工具选择（binary 分支为主）

参考示例支持 binary（pak_linyaps）和 source（ll-builder）两个分支。当前 agent 是二进制打包 agent，**项目目录必然有 `pak_linyaps.sh`**，所以 debug skill 的构建验证以 binary 分支为主。但保留 source 分支作为 fallback（项目目录无 `pak_linyaps.sh` 时），保持与参考示例一致。

### 决策5：Git 推送使用当前 agent 的 git-cleanup 模式（非 linyaps-git-workflow）

参考示例用 `linyaps-git-workflow` skill 的 `commit_and_push` action。当前 agent 无此 skill，使用 `for-multica/agent.md` 的 Git 提交模式（A7/B5/C5）：

```bash
# 1. 清理构建缓存
"${skills_root}/bin2linyaps.git-cleanup/scripts/clean_project_cache.sh" "<project_dir>"
# 2. 同步上游（若已绑定 git 仓库）
sync_upstream  # git fetch origin → stash → rebase → stash pop
# 3. 暂存
git add .
# 4. pre-commit 守卫
"${skills_root}/bin2linyaps.git-cleanup/scripts/pre-commit-guard.sh" "<project_dir>"
# 5. 提交
git commit -m "<commit_message>"
# 6. 推送
git push
```

commit message 规则（`for-multica/agent.md` A7/B5/C5）：单新增 `feat: add packaging for <pkg>`；单修改 `fix: update packaging for <pkg>`；无 `CI_ll_` 前缀 `chore: update packaging scripts`。

### 决策6：无 assign_packer（阶段五报告结果）

参考示例阶段五调用 `linyaps-src-init-dispatch` 的 `assign_packer`。当前 root agent 无 `linyaps-src-init-dispatch`（它在 `for-multica/skills/` 下，且当前 agent 的 `agent-config.json` 无 `assignment` 字段）。阶段五改为**输出修复报告**，不指派 packer。

**理由**：`for-multica/agent.md` 的指派步骤（A8/B6/C6）通过 `for-multica/skills/linyaps-binary-init-dispatch/scripts/dispatch.sh dispatch_git_commit_success` 实现，这是 for-multica 平台的机制，root agent 的 debug skill 不应直接调用。debug skill 的职责到 Git 推送为止，指派由 agent 主流程（若在 for-multica 上下文中运行）处理。

### 决策7：upstream 源文件获取（二进制包场景简化）

参考示例阶段四 4.1.0 通过 `linyaps-upstream-query` skill 获取源文件。当前 agent 是二进制打包，源文件是 deb/tar/AppImage 二进制包，获取方式：
- 用户指定 `src_path`（本地路径）→ 直接使用
- 用户指定 `src_url`（下载 URL）→ 直接使用
- 两者均无 → 从 `linglong.yaml` 的 `package.id` 推导包名，若 `agent-config.json` 有 `projects_root` 则在 `<projects_root>/` 下搜索对应的 deb/tar/AppImage 文件；找不到则跳过构建验证，标记 `build_verify="skipped"`

**不调用 `linyaps-upstream-query`**：该 skill 在 `for-multica/skills/` 下，属于 for-multica 平台机制；root agent 的 debug skill 不依赖它。

## 详细设计

### frontmatter

```yaml
---
name: bin2linyaps.debug
description: >
  【linyaps-app-packaging-script-generator / debug 节点】调试纠正 SKILL。
  调试已有玲珑构建工程：解压 layer → 对照分析 → 诊断问题 → 调用内部 skills 修复
  （结构问题交 bin2linyaps.fix，缺失动态库交 bin2linyaps.external-missing-deps-fetch）
  → 构建验证 + 运行验证 + 条件 Git 推送 → 输出修复报告。
  本体纯分析，修复通过调用内部 skills 完成。
user-invocable: false
---
```

### 目录约定

- 本 skill 无独立 scripts 目录；构建/运行验证由 LLM 直接执行 `ll-builder` / `pak_linyaps.sh` 命令。
- 构建工具选择：LLM 检测 `pak_linyaps.sh` 存在性选择 pak_linyaps（binary）或 ll-builder（source）。
- 内部资源（只读复用，路径相对于 WORKSPACE_ROOT）：
  - `skills/bin2linyaps.constraints/SKILL.md`（构建约束 + 运行期操作契约）
  - `skills/bin2linyaps.validate-structure/scripts/validate_project_structure.sh`
  - `skills/bin2linyaps.fix/scripts/fix_package_id.sh`、`validate_package_id.sh`
  - `skills/bin2linyaps.compat-testing/scripts/validate_linglong_yaml.py`
  - `skills/bin2linyaps.external-missing-deps-fetch/scripts/fetch_missing_deps.sh`
  - `skills/bin2linyaps.git-cleanup/scripts/clean_project_cache.sh`、`pre-commit-guard.sh`
  - `skills/config/base_runtime_whitelist.conf`、`skills/config/arch_mapping.json`

### 输入

|名称|类型|必填|描述|
|---|---|---|---|
|`layer_path`|string|是|已有构建工程打包出的 layer 文件|
|`problem_desc`|string|是|问题描述（构建失败/运行异常/缺失依赖等）|
|`project_path`|string|是|被纠正的工程目录（含 `linglong.yaml`，`CI_ll_<package_id>`）|
|`src_path`|string|否|用户指定的源文件路径（本地 deb/tar/AppImage 路径）|
|`src_url`|string|否|用户指定的源文件下载 URL|
|`agent_config_path`|string|否|agent 配置文件路径（默认 `WORKSPACE_ROOT/agent-config.json`）|
|`build_tmp_dir`|string|否|构建临时目录（含 `missing_deps.*`）；未指定时从 `reports/<pkg>/build_meta.json` 读取|

### 内部 skills 清单

|Skill|路径|用途（debug 修复时可调用场景）|
|---|---|---|
|`bin2linyaps.constraints`|`skills/bin2linyaps.constraints/`|构建约束 + 运行期操作契约（初始化读一次）|
|`bin2linyaps.validate-structure`|`skills/bin2linyaps.validate-structure/`|项目结构验证（`validate_project_structure.sh --json`）|
|`bin2linyaps.fix`|`skills/bin2linyaps.fix/`|修复结构验证问题（package_id、yaml 格式、base/runtime、desktop、图标、二进制权限）|
|`bin2linyaps.compat-testing`|`skills/bin2linyaps.compat-testing/`|YAML 校验（`validate_linglong_yaml.py`）|
|`bin2linyaps.external-missing-deps-fetch`|`skills/bin2linyaps.external-missing-deps-fetch/`|缺失动态库依赖分析 + apt-file 反查 + buildext.apt.depends 追加 + missing_deps_urls.conf 生成|
|`bin2linyaps.git-cleanup`|`skills/bin2linyaps.git-cleanup/`|Git 提交前缓存清理 + pre-commit 守卫|

### 工作流程（五阶段）

#### 阶段一 · 解压 layer

```bash
ll-builder extract <layer_path> <workdir>
```

- 参考：`skills/bin2linyaps.debug/ll-builder.command.reference.md`
- 解压后定位 `<workdir>/files`，即 `linglong.yaml` 声明的 `$PREFIX` 内容。

#### 阶段二 · 对照分析（纯分析，不改文件）

1. 读工程 `linglong.yaml`（package.id/name/version、command、build、buildext、modules）
2. 对照 `<workdir>/files/` 结构（bin/lib/share）+ `problem_desc`，判定问题类型：
   - **结构问题**：`linglong.yaml` 格式错误、base/runtime 不在白名单、package_id 不一致、desktop Icon 路径错误、图标目录结构不合规、二进制权限问题
   - **command 指向的可执行文件缺失**
   - **缺失动态库依赖**（核心检测点）：
     - 检查 `reports/<pkg>/build_meta.json` 的 `missing_deps_json`/`missing_deps_csv` 字段是否非 null
     - 检查 `build_tmp_dir` 下是否有 `missing_deps.json`/`missing_deps.csv`
     - 检查 `<workdir>/files/` 下 ELF 二进制的 `ldd` 输出是否有 `not found`
     - 检查 `problem_desc` 是否含 `cannot open shared object file` / `No such file or directory`（`.so` 相关）
   - **common res 缺失**：`share/applications/*.desktop`、`share/icons/hicolor/**`、`share/metainfo|appdata`、`share/locale`
   - **buildext 依赖缺失/多余**
3. 分类缺失动态库：
   - **可作为 runtime-depends**：标准 apt 包提供的 `.so`（如 `libgtk-3.so.0` → `libgtk-3-0`）→ 交由 `bin2linyaps.fix`
   - **不可作为 runtime-depends**：非标准包、私有 `.so`、第三方库 → **交由 `bin2linyaps.external-missing-deps-fetch`**
4. 输出结构化诊断清单（含问题类型 + 定位 + 依据 + 修复调度）

#### 阶段三 · 修复（调用具体内部 skills）

|诊断问题|调用的内部 skill|核心动作|
|---|---|---|
|结构验证问题|`bin2linyaps.fix`|`fix_package_id.sh`、`validate_package_id.sh` 修复|
|YAML 格式/base/runtime 错误|`bin2linyaps.fix`|修复 linglong.yaml 格式、base/runtime 白名单|
|desktop/图标/权限问题|`bin2linyaps.fix`|修复 Icon 路径、图标目录、二进制权限|
|缺失动态库（可作为 runtime-depends）|`bin2linyaps.fix`|追加到 `buildext.apt.depends` 或 `runtime.depends`|
|**缺失动态库（不可作为 runtime-depends）**|**`bin2linyaps.external-missing-deps-fetch`**|**`fetch_missing_deps.sh --project-dir=<dir> --build-tmp-dir=<tmp>`**|
|修复后二次校验|`bin2linyaps.validate-structure` + `bin2linyaps.compat-testing`|`validate_project_structure.sh --json` + `validate_linglong_yaml.py`|

**external-missing-deps-fetch 调用**：
```bash
# 从 build_meta.json 获取 build_tmp_dir（若未显式传入）
build_tmp_dir=$(jq -r '.build_tmp_dir // empty' "reports/<pkg>/build_meta.json")

# 调用 fetch_missing_deps.sh
"${skills_root}/bin2linyaps.external-missing-deps-fetch/scripts/fetch_missing_deps.sh" \
  --project-dir="<project_path>" \
  --build-tmp-dir="${build_tmp_dir}"
```

**约束**：
- `fetch_missing_deps.sh` 只修改 `<project_path>/templates/linglong.yaml`（追加 `buildext.apt.depends`），**绝不修改 `build_tmp_dir`**
- 只执行一次（constraints 要求）
- 遵循 constraints §5 依赖核验门禁：`apt-cache show` 核验不存在的包自动剔除
- `bin2linyaps.fix` 与 `bin2linyaps.external-missing-deps-fetch` 是并列关系，建议先 fix 后 fetch（避免 ruamel.yaml dump 格式冲突）

**修复后二次校验**：
```bash
# 结构验证
"${skills_root}/bin2linyaps.validate-structure/scripts/validate_project_structure.sh" \
  "<project_path>" --json

# YAML 校验
python3 "${skills_root}/bin2linyaps.compat-testing/scripts/validate_linglong_yaml.py" \
  --input "<project_path>/linglong.yaml" \
  --exec-name "<command_field>" --json
```
- 退出码 0 → 校验通过，继续阶段四
- 退出码非 0 → 按错误修复后重新校验，直至通过或判定无法修复

#### 阶段四 · 构建验证 + 运行验证 + 条件 Git 推送

##### 4.1 构建验证

**4.1.0 获取源文件**

优先级：用户指定 `src_path`/`src_url` > 从 `agent-config.json` 的 `projects_root` 搜索。

- 用户指定 `src_path`（本地 deb/tar/AppImage）→ 直接使用
- 用户指定 `src_url`（下载 URL）→ 直接使用
- 两者均无 → 从 `linglong.yaml` 的 `package.id` 推导包名，在 `<projects_root>/` 下搜索对应二进制包；找不到 → 跳过构建验证，`build_verify="skipped"`

**4.1.1 构建工具选择**

```bash
if [[ -f "<project_path>/pak_linyaps.sh" ]]; then
  build_tool="pak_linyaps"   # binary 类型（当前 agent 主要场景）
else
  build_tool="ll-builder"    # source 类型（fallback）
fi
```

**4.1.2 构建执行**

记录开始时间：
```bash
start_time=$(date +%s)
```

**binary 分支（`build_tool == "pak_linyaps"`）**：

LLM **必须先读取 `<project_path>/pak_linyaps.sh`** 理解参数，再构造调用命令。

```bash
for attempt in 1 2; do
  echo "== 构建尝试 $attempt/2 (pak_linyaps) =="
  timeout 1800 <pak_linyaps_command>  # LLM 读取脚本后构造的实际命令
  build_rc=$?

  # 退出码 124 消歧
  if [[ $build_rc -eq 124 ]]; then
    if pgrep -x ll-builder >/dev/null 2>&1 || pgrep -x fuse-overlayfs >/dev/null 2>&1 || pgrep -x erofsfuse >/dev/null 2>&1; then
      echo "== 构建仍在进行，继续等待 =="
      wait
      build_rc=$?
    else
      echo "== 构建进程已退出（超时无活跃进程），判定挂起 =="
    fi
  fi

  if [[ $build_rc -eq 0 ]]; then
    echo "== 构建成功 =="
    break
  fi

  [[ $attempt -lt 2 ]] && sleep 10 && echo "== 重试构建 =="
done

if [[ $build_rc -eq 0 ]]; then
  layer_file=$(find <output_dir> -maxdepth 1 -name "*_binary.layer" -type f -newermt "@$start_time" 2>/dev/null | head -1)
  if [[ -n "$layer_file" ]]; then
    build_verify="passed"
  else
    build_verify="failed"
  fi
else
  build_verify="failed"
fi
```

**source 分支（`build_tool == "ll-builder"`）**：

```bash
for attempt in 1 2; do
  echo "== 构建尝试 $attempt/2 =="
  timeout 1800 ll-builder build --skip-output-check --build-dir <project_path>
  build_rc=$?

  # 退出码 124 消歧（同上）
  if [[ $build_rc -eq 124 ]]; then
    if pgrep -x ll-builder >/dev/null 2>&1 || pgrep -x fuse-overlayfs >/dev/null 2>&1 || pgrep -x erofsfuse >/dev/null 2>&1; then
      wait
      build_rc=$?
    fi
  fi

  if [[ $build_rc -eq 0 ]]; then break; fi
  [[ $attempt -lt 2 ]] && sleep 10
done

if [[ $build_rc -ne 0 ]]; then
  build_verify="failed"
else
  timeout 1800 ll-builder export --layer --no-develop -z zstd --build-dir <project_path>
  export_rc=$?
  # 退出码 124 消歧（同上）
  if [[ $export_rc -eq 124 ]]; then
    if pgrep -x ll-builder >/dev/null 2>&1 || pgrep -x fuse-overlayfs >/dev/null 2>&1 || pgrep -x erofsfuse >/dev/null 2>&1; then
      wait; export_rc=$?
    fi
  fi
  if [[ $export_rc -eq 0 ]]; then
    layer_file=$(find <project_path> -maxdepth 1 -name "*.layer" -type f -newermt "@$start_time" 2>/dev/null | head -1)
    build_verify=$([[ -n "$layer_file" ]] && echo "passed" || echo "failed")
  else
    build_verify="failed"
  fi
fi
```

##### 4.2 运行验证

构建验证失败时跳过（`run_verify="skipped"`）。

**binary 分支**：LLM 读取 `linglong.yaml` 的 `command` 字段构造运行命令，从 `output_dir` 运行 layer。
```bash
if [[ "$build_verify" == "passed" ]]; then
  timeout 30 <run_command>
  run_rc=$?
  if [[ $run_rc -eq 0 || $run_rc -eq 124 ]]; then
    run_verify="passed"
  else
    run_verify="failed"
  fi
else
  run_verify="skipped"
fi
```

**source 分支**：
```bash
if [[ "$build_verify" == "passed" ]]; then
  timeout 30 ll-builder run --build-dir <project_path>
  run_rc=$?
  if [[ $run_rc -eq 0 || $run_rc -eq 124 ]]; then
    run_verify="passed"
  else
    run_verify="failed"
  fi
else
  run_verify="skipped"
fi
```

##### 4.3 条件 Git 推送

使用当前 agent 的 git-cleanup 模式（`for-multica/agent.md` A7/B5/C5 模式），非 `linyaps-git-workflow`。

**成功（`build_verify="passed"` 且 `run_verify` 为 `"passed"` 或 `"skipped"`）**：
```bash
# 1. 清理构建缓存
"${skills_root}/bin2linyaps.git-cleanup/scripts/clean_project_cache.sh" "<project_path>"
# 2. 同步上游（若已绑定 git 仓库且有 projects_repo）
#    sync_upstream: git fetch origin → stash -u → rebase → stash pop
# 3. 暂存
git add .
# 4. pre-commit 守卫
"${skills_root}/bin2linyaps.git-cleanup/scripts/pre-commit-guard.sh" "<project_path>"
# 5. 提交（commit message 按 for-multica 约定）
git commit -m "fix: update packaging for <pkg>"
# 6. 推送
git push
```

**失败（`build_verify="failed"` 或 `run_verify="failed"`）**：
```bash
# 1. 仍推送修复（先清理 + 守卫 + 提交 + 推送，同上）
"${skills_root}/bin2linyaps.git-cleanup/scripts/clean_project_cache.sh" "<project_path>"
git add .
"${skills_root}/bin2linyaps.git-cleanup/scripts/pre-commit-guard.sh" "<project_path>"
git commit -m "fix: update packaging for <pkg>"
git push
# 2. 记录警告（若在 for-multica 上下文且有 MULTICA_ISSUE_TASK_ID）
if [[ -n "${MULTICA_ISSUE_TASK_ID:-}" ]]; then
  multica issue comment add "$MULTICA_ISSUE_TASK_ID" \
    --content "⚠️ build/run verification failed: build=$build_verify run=$run_verify"
fi
```

**约束**：
- `clean_project_cache.sh` 必须在 `git add` 之前执行
- `pre-commit-guard.sh` 必须在 `git commit` 之前执行
- commit message：单修改 `fix: update packaging for <pkg>`；无 `CI_ll_` 前缀 `chore: update packaging scripts`
- `sync_upstream` 冲突时记 `blocked:rebase_conflict`，禁 push

#### 阶段五 · 输出修复报告

（无 assign_packer — 当前 agent 无 `linyaps-src-init-dispatch`）

修复报告：
- 诊断问题（问题类型 + 定位 + 依据）
- 缺失动态库分类（可作为 runtime-depends / 不可作为 runtime-depends）
- 调用的 skill + 改动 before/after
- `bin2linyaps.external-missing-deps-fetch` 执行结果（追加的 `buildext.apt.depends` + 生成的 `missing_deps_urls.conf`）
- 校验结果（结构验证 + YAML 校验）
- 构建验证结果（passed/failed/skipped + .layer 文件路径）
- 运行验证结果（passed/failed/skipped + 退出码）
- Git 推送结果（committed + commit_sha + 是否追加 multica 警告评论）

### 约束

1. **`files/` 即 `$PREFIX`**：解压出的 `<workdir>/files` 目录就是 `linglong.yaml` 声明的安装前缀。
2. **遵循 constraints SKILL**：wrapper/command 契约（禁止手动设 `command`）、version 契约（`${ll_version}`）、package_id 契约（`CI_ll_<id>`）、base/runtime 白名单、依赖核验（§5）、模板完整性、运行期操作契约（禁止 `cd`、禁止具名 skill 调用）。
3. **修复后必须校验**：任何改动必须通过 `validate_project_structure.sh` + `validate_linglong_yaml.py` 校验。
4. **清理临时目录**：临时解压目录处理完清理。
5. **仅调用仓库内 skills**：修复仅能调用 `skills/bin2linyaps.*` 下内部 skills。
6. **external-missing-deps-fetch 约束**：`fetch_missing_deps.sh` 只修改 `templates/linglong.yaml`，**绝不修改 `build_tmp_dir`**；只执行一次；`build_tmp_dir` 从 `build_meta.json` 或显式参数获取。
7. **构建验证重试限制**：`pak_linyaps.sh` / `ll-builder build` + `ll-builder export` 各最多 2 次尝试（含首次），超时 1800 秒/次。退出码 124 时必须检查 `ll-builder`/`fuse-overlayfs`/`erofsfuse` 进程活跃性，不得仅凭超时判失败。
8. **运行验证超时**：超时 30 秒；退出码 0/124 = 通过，其他非零 = 失败。
9. **Git 推送条件性**：构建+运行验证通过 → 正常推送；验证失败 → 仍推送但追加 multica 警告评论（若有 `MULTICA_ISSUE_TASK_ID`）。
10. **Git 推送用 git-cleanup 模式**：`clean_project_cache.sh` → `git add` → `pre-commit-guard.sh` → `git commit` → `git push`；不用 `linyaps-git-workflow`（当前仓库无此 skill）。

### 步骤0：导出实施方案到 `docs/bin2linyaps-debug-skill-plan.md`

在所有代码改动之前，将本实施方案复制到 `docs/bin2linyaps-debug-skill-plan.md`（`docs/` 目录已存在，存放同类实施方案，如 `external-missing-deps-fetch-integration-plan.md`、`issue-69-agent-skills-repair-plan.md`）。此步骤作为执行前留档，内容与本计划 `local://bin2linyaps-debug-skill-plan.md` 完全一致。命名遵循现有 `docs/` 约定（`<slug>-plan.md`）。

### 步骤1：新建 `skills/bin2linyaps.debug/ll-builder.command.reference.md`

从参考示例 `examples/debian-rules-to-linyaps-rules-dev/skills/src2linyaps.debug/ll-builder.command.reference.md` 复制（内容相同：`ll-builder extract` 命令参考）。

### 步骤2：新建 `skills/bin2linyaps.debug/SKILL.md`

按上述详细设计编写完整 SKILL.md，包含：
- frontmatter（`user-invocable: false`）
- 设计核心（纯分析 + 修复调用内部 skills + 无 assign_packer）
- 目录约定
- 输入表
- 内部 skills 清单表
- 工作流程（五阶段）
- 约束（10 条）
- 输出（修复报告）

### 步骤3：修改 `agents/deb-linglong-packer.agent.md`

在 skills 表（L45-57）新增一行：
```
| bin2linyaps.debug | `skills/bin2linyaps.debug/SKILL.md` | 调试 | 无（LLM 直接执行 ll-builder/pak_linyaps） |
```

## 验证检查清单

- [ ] 步骤0：导出实施方案到 `docs/bin2linyaps-debug-skill-plan.md`（代码改动前执行）
- [ ] `skills/bin2linyaps.debug/SKILL.md` frontmatter `user-invocable: false`
- [ ] 五阶段工作流完整：解压 layer → 分析 → 修复 → 构建验证+运行验证+条件Git推送 → 报告
- [ ] 阶段二缺失动态库检测：`build_meta.json` + `missing_deps.*` + `ldd` + `problem_desc`
- [ ] 阶段三修复表含 `bin2linyaps.external-missing-deps-fetch` 行（不可作为 runtime-depends 的缺失库）
- [ ] `fetch_missing_deps.sh` 调用含 `--project-dir` + `--build-tmp-dir`（从 `build_meta.json` 获取）
- [ ] `fetch_missing_deps.sh` 约束：只改 `templates/linglong.yaml`、绝不改 `build_tmp_dir`、只执行一次
- [ ] 阶段四构建工具选择：`pak_linyaps.sh` 存在 → binary；否则 → source
- [ ] binary 分支：LLM 先读 `pak_linyaps.sh` 再构造命令；重试 ≤2，超时 1800s，退出码 124 消歧
- [ ] source 分支：`ll-builder build --skip-output-check` + `ll-builder export --layer --no-develop -z zstd`
- [ ] 运行验证：超时 30s，退出码 0/124 = 通过
- [ ] Git 推送用 git-cleanup 模式（`clean_project_cache.sh` → `git add` → `pre-commit-guard.sh` → `git commit` → `git push`）
- [ ] 阶段五输出修复报告，无 assign_packer
- [ ] `agents/deb-linglong-packer.agent.md` skills 表新增 `bin2linyaps.debug` 行
- [ ] `ll-builder.command.reference.md` 从参考示例复制

## 假设

1. `ll-builder` 命令在当前环境可用（参考示例假设相同）。
2. `reports/<pkg>/build_meta.json` 由 `compat-testing` step3b 生成（若 compat-testing 未执行，`build_tmp_dir` 需用户显式提供）。
3. `multica` 命令仅在 for-multica 上下文可用；root agent 上下文无 `MULTICA_ISSUE_TASK_ID` 时跳过 multica comment。
4. `projects_repo` 为空时（root agent 默认配置），Git 推送步骤跳过（无远程仓库可推）。
