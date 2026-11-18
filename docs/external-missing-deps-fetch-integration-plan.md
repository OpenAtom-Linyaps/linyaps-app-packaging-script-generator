# Plan: 完善 bin2linyaps.external-missing-deps-fetch 集成说明（README + reference + SKILL.md 精简）

## 目标

为 `bin2linyaps.external-missing-deps-fetch` skill 同时服务 LLM 与人类：新建 `README.md`（人类入口）+ `reference/` 目录（分主题参考），将所有集成时序/fix 协作/pak_linyaps 集成/conf 格式内容移入；SKILL.md 精简为纯 LLM 契约（约束/输入/工作流程/错误处理），用链接引用 README/reference。**只改文档，不改任何脚本。**

## 变更范围

| 文件 | 操作 |
|------|------|
| `docs/external-missing-deps-fetch-integration-plan.md` | **新建**：本实施方案落盘，遵循 `docs/` 现有约定（步骤 0） |
| `skills/bin2linyaps.external-missing-deps-fetch/SKILL.md` | 修改：精简注意事项 + 目录约定小节新增 README/reference 条目 + 新增「相关文档」链接区 |
| `skills/bin2linyaps.external-missing-deps-fetch/README.md` | **新建**：人类入口，仿 `appimage.transfer/README.md` 风格 |
| `skills/bin2linyaps.external-missing-deps-fetch/reference/integration-timeline.md` | **新建**：端到端集成时序详述 |
| `skills/bin2linyaps.external-missing-deps-fetch/reference/pak_linyaps_integration.md` | **新建**：pak_linyaps.sh 集成细节 |
| `skills/bin2linyaps.external-missing-deps-fetch/reference/fix_collaboration.md` | **新建**：与 bin2linyaps.fix 的协作边界 |
| `skills/bin2linyaps.external-missing-deps-fetch/reference/missing_deps_urls_conf_format.md` | **新建**：missing_deps_urls.conf 格式规范 |

## 当前 SKILL.md 结构（已确认，244 行）

```
L1-8     frontmatter（user-invocable: false）
L10      # 外部缺失依赖获取
L12-21   ## 功能说明
L23-28   ## 关键约束
L30-34   ## 触发场景
L36-41   ## 目录约定
L43-53   ## 输入
L55-67   ## 工作流程（9 步表）
L69-75   ## 输出产物
L77-88   ## 错误处理
L90-102  ## 依赖工具
L104-112 ## 注意事项（7 条，第 4/5/6 条为 pak_linyaps 集成，分散）
```

## 关键事实（已确认，勿改）

### 现有调用链
```
compat-testing run_tasks.sh step3 (L196-255)
  └─ pak_linyaps.sh --build_tmp_dir=<tmp>（执行 ll-builder build）
       └─ ll-builder build 在 <tmp>/<basename(project_dir)>/ 内生成 missing_deps.json / missing_deps.csv
            └─ step3b (L441-466) 写 build_meta.json（reports/<pkg>/build_meta.json）
                 ├─ build_tmp_dir: <tmp>/<basename(project_dir)>
                 ├─ project_dir: <project_dir>
                 ├─ missing_deps_json: <path> 或 null
                 └─ missing_deps_csv: <path> 或 null

fetch_missing_deps.sh --project-dir=<proj> [--build-tmp-dir=<tmp>]
  ├─ 优先从 --build-tmp-dir 读 missing_deps.*，回退 <project_dir>/missing_deps.*
  ├─ apt-file 反查 so → 包名 (L101-109)
  ├─ apt-cache show 逐包核验（写入门禁，constraints §5）(L114-133)
  ├─ ruamel.yaml 追加 buildext.apt.depends（templates/linglong.yaml）(L144-177)
  ├─ apt-get download --print-uris 取 URL (L192-207)
  └─ 生成 <project_dir>/missing_deps_urls.conf（3 行注释头 + MISSING_DEPS_URLS 数组）(L210-222)

pak_linyaps.sh build_pak()
  ├─ deb.project-gen L1036-1048 / appimage.transfer L790-802 / tar.transfer L970-982:
  │    if [ -f ${project_root}/missing_deps_urls.conf ]; then
  │      scripts/download_missing_deps.sh "${binary_dir}"   # 非阻塞
  │    fi
  └─ handle_special_paths.sh --phase=libfix（deb L1053 / appimage L807 / tar L987，补 .so 软链）
```

### examples/missing_deps_urls.conf 确认格式
```bash
# 由 bin2linyaps.external-missing-deps-fetch 自动生成
# 位于 CI_ll_xxx/，与 pak_linyaps.sh 同级
# 可人工编辑：增删改 URL 行后重新运行 download_missing_deps.sh 即可
MISSING_DEPS_URLS=(
  "https://pools.uniontech.com/.../libqt4-xmlpatterns_4.8.7%2bdfsg.6-1%2bdde_amd64.deb"
)
```

### download_missing_deps.sh 关键行为（已确认，113 行）
- `source ${PROJECT_ROOT}/missing_deps_urls.conf` 加载 `MISSING_DEPS_URLS` 数组
- `DEB_CACHE=/tmp/lingyaps-debs`：缓存命中跳过下载
- `IMPORTANT_DIRS=(usr bin sbin lib lib32 lib64 libexec include share local)`：白名单复制
- `usr` 平铺进 `binary_dir`（`usr/bin` → `bin`），其余直接复制
- 不依赖 `fetch_missing_deps.sh` 是否执行过；用户手动创建 conf 即可直接调用

### fix skill 边界（已确认）
`bin2linyaps.fix/SKILL.md`（518 行）修复项：package_id（§0）、linglong.yaml 格式（§1）、base/runtime（§1.0）、desktop（§2）、图标（§3）、二进制权限（§4）。**无 missing_deps 分支**。external-missing-deps-fetch 与 fix 是并列关系，非调用关系。

### constraints §5 依赖核验（已确认）
`skills/bin2linyaps.constraints/SKILL.md` L40-42：写入 `buildext.apt.depends` 的依赖必须逐包 `apt-cache show` 核验通过。`fetch_missing_deps.sh` L114-133 实现此门禁。

## 变更步骤

### 步骤 0：将本实施方案落盘到 `docs/`

**文件**：`docs/external-missing-deps-fetch-integration-plan.md`（新建）

**操作**：将本计划文件（`local://external-missing-deps-fetch-integration-plan.md`）的完整内容复制到仓库 `docs/` 目录，供团队查阅。遵循 `docs/` 现有约定（`dispatch-random-tiebreak-plan.md`、`issue-69-agent-skills-repair-plan.md` 均为 `<descriptive-name>-plan.md` 命名的落盘实施方案）。

**内容**：与 `local://external-missing-deps-fetch-integration-plan.md` 完全一致（含目标/变更范围/关键事实/变更步骤/验证/假设）。落盘后本步骤完成，后续步骤 1-8 在 `skills/bin2linyaps.external-missing-deps-fetch/` 下执行。

**注意**：此步骤是计划执行的第一步；落盘的文档即本计划本身，不需额外改写。

### 步骤 1：新建 `reference/integration-timeline.md`

**文件**：`skills/bin2linyaps.external-missing-deps-fetch/reference/integration-timeline.md`

**内容**：端到端集成时序详述。包含：

1. **标题 + 一句话定位**：`# 端到端集成时序` + "本 skill 是 compat-testing → fetch → pak_linyaps 三阶段流水线的中间环节"

2. **mermaid 序列图**（完整时序，含 participant：compat-testing run_tasks.sh / pak_linyaps.sh / ll-builder build / fetch_missing_deps.sh / bin2linyaps.fix / download_missing_deps.sh）：
   - step3 首次构建 → ll-builder build 生成 missing_deps.json/csv
   - step3b 写 build_meta.json
   - 修复阶段：fetch_missing_deps.sh 分析+生成 conf（与 bin2linyaps.fix 并列，可任意序）
   - 重新构建：pak_linyaps build_pak 检测 conf → download_missing_deps.sh → handle_special_paths.sh libfix → ll-builder build

3. **阶段表**（5 行：① 首次构建 ② 元数据归集 ③ 依赖分析 ④ 结构修复（并列）⑤ 重新构建），列：阶段 / 执行者 / 关键产物 / 数据流向。每行含具体行号引用：
   - ① `compat-testing` step3（`run_tasks.sh` L196-255）调用 `pak_linyaps.sh --build_tmp_dir=<tmp>`；`ll-builder build` 在 `<tmp>/<basename(project_dir)>/` 内生成 `missing_deps.json` / `missing_deps.csv`
   - ② `compat-testing` step3b（`run_tasks.sh` L441-466）写 `reports/<pkg>/build_meta.json`，字段 `build_tmp_dir` / `project_dir` / `missing_deps_json` / `missing_deps_csv`
   - ③ `fetch_missing_deps.sh --project-dir=<proj> [--build-tmp-dir=<tmp>]`：apt-file 反查（L101-109）→ apt-cache 核验（L114-133）→ ruamel.yaml 追加 buildext.apt.depends（L144-177）→ apt-get download --print-uris（L192-207）→ 生成 missing_deps_urls.conf（L210-222）
   - ④ `bin2linyaps.fix`（fix_package_id.sh）：修复验证报告结构问题，与本 skill 并列
   - ⑤ `pak_linyaps.sh` `build_pak()` 第二次：download_missing_deps.sh（deb L1039-1048 / appimage L793-802 / tar L973-982）→ handle_special_paths.sh libfix（deb L1053 / appimage L807 / tar L987）→ ll-builder build

4. **数据流向说明**：③ 和 ④ 无数据依赖可任意序；⑤ 必须在 ③ 完成后（conf 已生成）才有意义

5. **关键产物路径表**：`missing_deps.json` / `missing_deps.csv`（`<build_tmp_dir>/`）、`build_meta.json`（`reports/<pkg>/`）、`missing_deps_urls.conf`（`<project_dir>/`，与 pak_linyaps.sh 同级）

### 步骤 2：新建 `reference/pak_linyaps_integration.md`

**文件**：`skills/bin2linyaps.external-missing-deps-fetch/reference/pak_linyaps_integration.md`

**内容**：pak_linyaps.sh 集成细节。包含：

1. **标题**：`# 与 pak_linyaps.sh 的集成`

2. **调用点**（含代码块 + 行号）：
   ```bash
   # pak_linyaps.sh build_pak() — deb.project-gen L1039-1048 / appimage.transfer L793-802 / tar.transfer L973-982
   if [ -f "${project_root}/missing_deps_urls.conf" ]; then
       echo "檢測到缺失依賴配置 (missing_deps_urls.conf)，執行下載解壓..."
       if "${project_root}/scripts/download_missing_deps.sh" "${binary_dir}"; then
           echo "外部缺失依賴下載解壓完成"
       else
           echo "警告: 外部缺失依賴下載解壓失敗，繼續構建流程" >&2
       fi
   else
       echo "未檢測到缺失依賴配置 (missing_deps_urls.conf)，跳過"
   fi

   # 之后立即执行 .so 软链修复（deb.project-gen L1053 / appimage.transfer L807 / tar.transfer L987）
   "${project_root}/scripts/handle_special_paths.sh" --phase=libfix "${binary_dir}"
   ```
   说明 3 个模板调用块完全相同。

3. **非阻塞语义**：`download_missing_deps.sh` 失败时仅输出警告到 stderr，不中断后续构建（`if/else` 包裹）；`ll-builder build` 仍会执行。

4. **libfix 衔接**：`handle_special_paths.sh --phase=libfix` 在 download **之后**执行，为 `binary_dir/lib/` 下非标准目录及多架构子目录的 ELF 共享库创建相对路径软链 + 补全 SONAME 级软链（如 `libtiff.so.5`）。**必须在 download 之后**，否则无法覆盖新引入的库。

5. **人工编辑 conf 后重跑**（含命令）：
   ```bash
   # 在项目目录（CI_ll_xxx/）下执行
   bash scripts/download_missing_deps.sh              # 默认解压到 binary_dir
   bash scripts/download_missing_deps.sh <target_dir> # 指定目标目录
   ```
   说明无需重新执行 fetch_missing_deps.sh。

6. **download_missing_deps.sh 行为细节**（含 `DEB_CACHE=/tmp/lingyaps-debs`、`IMPORTANT_DIRS` 白名单、`usr` 平铺机制、不依赖 fetch 是否执行过）

7. **写入门禁（constraints §5）引用**：`fetch_missing_deps.sh` L114-133 实现 constraints §5 的 `apt-cache show` 核验；不存在的包剔除，禁止写入 depends。

### 步骤 3：新建 `reference/fix_collaboration.md`

**文件**：`skills/bin2linyaps.external-missing-deps-fetch/reference/fix_collaboration.md`

**内容**：与 bin2linyaps.fix 的协作边界。包含：

1. **标题**：`# 与 bin2linyaps.fix 的协作`

2. **边界声明**：fix 与本 skill 是**并列关系**，非调用关系。

3. **对比表**（列：维度 / bin2linyaps.fix / 本 skill），行：
   - 修复对象：结构验证报告问题 / 运行时缺失动态库依赖
   - 修复内容：package_id（§0）、linglong.yaml 格式（§1）、base/runtime（§1.0）、desktop（§2）、图标（§3）、二进制权限（§4）/ `missing_deps.*` → apt-file 反查 → buildext.apt.depends 追加 + missing_deps_urls.conf 生成
   - 输入：验证报告（yaml_validation / structure_validation）/ build_meta.json 或 --build-tmp-dir 下的 missing_deps.*
   - 修改文件：templates/linglong.yaml（格式/base/runtime）、desktop、图标目录、二进制权限 / templates/linglong.yaml（仅 buildext.apt.depends 字段）、missing_deps_urls.conf

4. **并列关系说明**：
   - 二者无数据依赖，可任意顺序或并行执行
   - `for-multica/agent.md` 路径 A/B/C 共享构建步骤中两者并列，无先后约束
   - fix 当前不处理 missing_deps（其 fix_package() 无 missing_deps 分支）；若无结构问题 fix 无事可做，本 skill 仍可独立运行

5. **建议先 fix 后 fetch 的理由**：二者可能同时修改 templates/linglong.yaml（fix 修改格式/base/runtime字段，本 skill 修改 buildext.apt.depends 字段，不冲突）。若需保证一致性，建议先 fix 后 fetch——fix 的 ruamel.yaml dump 可能重排格式，本 skill 的 ruamel.yaml 追加在已格式化的文件上进行，避免格式被重排覆盖。

### 步骤 4：新建 `reference/missing_deps_urls_conf_format.md`

**文件**：`skills/bin2linyaps.external-missing-deps-fetch/reference/missing_deps_urls_conf_format.md`

**内容**：conf 格式规范。包含：

1. **标题**：`# missing_deps_urls.conf 格式规范`

2. **格式示例**（代码块）：
   ```bash
   # 由 bin2linyaps.external-missing-deps-fetch 自动生成
   # 位于 CI_ll_xxx/，与 pak_linyaps.sh 同级
   # 可人工编辑：增删改 URL 行后重新运行 download_missing_deps.sh 即可
   MISSING_DEPS_URLS=(
     "https://pools.uniontech.com/.../libqt4-xmlpatterns_4.8.7%2bdfsg.6-1%2bdde_amd64.deb"
   )
   ```

3. **格式规范表**（列：部分 / 说明 / 生成位置）：
   - 3 行注释头：固定内容，写死在 `fetch_missing_deps.sh` L214-216
   - `MISSING_DEPS_URLS=(...)`：bash 数组，每行一个 URL
   - URL 百分号编码：`+` 编码为 `%2b`（由 `apt-get download --print-uris` 输出，L192-207）

4. **加载机制**：`download_missing_deps.sh` 通过 `source ${PROJECT_ROOT}/missing_deps_urls.conf` 加载 `MISSING_DEPS_URLS` 数组

5. **人工编辑规则**：增删改 URL 行后重新运行 `download_missing_deps.sh` 即可，无需重新执行 `fetch_missing_deps.sh`；保持 3 行注释头 + 数组语法不变

6. **示例文件引用**：参见 `examples/missing_deps_urls.conf`（URL 指向 `pools.uniontech.com`）和 `skills/bin2linyaps.external-missing-deps-fetch/examples/missing_deps_urls.conf`（URL 指向 `ci.deepin.com/repo/deepin/deepin-community`，2 个 URL）

### 步骤 5：新建 `README.md`

**文件**：`skills/bin2linyaps.external-missing-deps-fetch/README.md`

**内容**：人类入口文档，仿 `appimage.transfer/README.md` 风格（概述/功能特性/目录结构/快速开始/脚本说明/工作流程/与 fix 的协作/与 pak_linyaps 的集成/设计决策/故障排除/相关链接）。包含：

1. **标题**：`# bin2linyaps.external-missing-deps-fetch 技能`

2. **概述**（2-3 句）：本 skill 用于分析玲珑构建产生的缺失依赖报告（`missing_deps.json/csv`），通过 apt-file 反查 + apt-cache 核验，将缺失依赖追加到 `linglong.yaml` 的 `buildext.apt.depends`，并生成 `missing_deps_urls.conf` 供 `pak_linyaps.sh` 下载解压。位于 compat-testing → fetch → pak_linyaps 三阶段流水线的中间环节。

3. **功能特性**（核心功能 4 条）：
   - 缺失依赖分析：读取 `missing_deps.json/csv`，apt-file 反查 so → 包名
   - 依赖核验门禁：逐包 apt-cache show 核验（constraints §5），不存在的包剔除
   - YAML 追加：ruamel.yaml 追加 buildext.apt.depends（去重）
   - URL 配置生成：apt-get download --print-uris 生成 missing_deps_urls.conf

4. **目录结构**（代码块，含 SKILL.md / README.md / reference/ / scripts/ / examples/）：
   ```
   bin2linyaps.external-missing-deps-fetch/
   ├── SKILL.md                      # LLM 契约（约束/输入/工作流程/错误处理）
   ├── README.md                     # 本文档（人类入口）
   ├── reference/                    # 参考文档
   │   ├── integration-timeline.md   # 端到端集成时序
   │   ├── pak_linyaps_integration.md # pak_linyaps.sh 集成细节
   │   ├── fix_collaboration.md      # 与 bin2linyaps.fix 的协作边界
   │   └── missing_deps_urls_conf_format.md # conf 格式规范
   ├── scripts/
   │   ├── fetch_missing_deps.sh     # 分析+生成脚本（244 行）
   │   └── download_missing_deps.sh  # 静态下载解压脚本（113 行）
   └── examples/
       └── missing_deps_urls.conf    # 示例配置
   ```

5. **快速开始**（2 个场景的命令）：
   - 标准流程：`fetch_missing_deps.sh --project-dir=<proj> --build-tmp-dir=<tmp>` → 重新构建
   - 人工编辑 conf 后重跑：`bash scripts/download_missing_deps.sh <binary_dir>`

6. **脚本说明**：
   - `fetch_missing_deps.sh`：用法 `./scripts/fetch_missing_deps.sh --project-dir=<proj> [--build-tmp-dir=<tmp>]`；流程 5 步（读 missing_deps.* → apt-file 反查 → apt-cache 核验 → ruamel.yaml 追加 → 生成 conf）
   - `download_missing_deps.sh`：用法 `./scripts/download_missing_deps.sh [<binary_dir>]`；流程（source conf → wget 下载到 DEB_CACHE → dpkg-deb 解压 → IMPORTANT_DIRS 白名单复制）；静态脚本，初始化时由 deb.project-gen 复制到工程

7. **工作流程**：引用 `reference/integration-timeline.md`，含精简阶段表（5 行）+ 链接

8. **与 bin2linyaps.fix 的协作**：引用 `reference/fix_collaboration.md`，含边界声明一句话 + 对比表精简版（4 行）+ 链接

9. **与 pak_linyaps.sh 的集成**：引用 `reference/pak_linyaps_integration.md`，含调用点代码块 + 非阻塞语义 + libfix 衔接 + 人工编辑重跑命令 + 链接

10. **设计决策**：
    - 非阻塞设计：download 失败不中断构建（if/else 包裹）
    - apt-cache 核验门禁：constraints §5 要求，防止写入不存在的包
    - usr 平铺：IMPORTANT_DIRS 白名单中 usr 平铺进 binary_dir，匹配玲珑 $prefix 结构
    - 静态 download 脚本：不依赖 fetch 是否执行，用户可手动创建 conf 直接调用

11. **故障排除**（表，列：问题 / 原因 / 解决方案）：
    - `missing_deps_urls.conf 未检测到`：未运行 fetch 或 conf 路径不在 project_root → 运行 fetch_missing_deps.sh
    - `apt-cache show 失败`：包名不存在于仓库 → 检查 apt 源，包被剔除是预期行为
    - `download 失败但构建继续`：非阻塞设计 → 查看 stderr 警告，检查 URL 可达性
    - `.so 软链缺失`：libfix 未覆盖 → 确认 handle_special_paths.sh 在 download 之后执行

12. **相关链接**：
    - [端到端集成时序](reference/integration-timeline.md)
    - [pak_linyaps.sh 集成细节](reference/pak_linyaps_integration.md)
    - [与 bin2linyaps.fix 的协作](reference/fix_collaboration.md)
    - [missing_deps_urls.conf 格式规范](reference/missing_deps_urls_conf_format.md)
    - [bin2linyaps.constraints §5 依赖核验](../bin2linyaps.constraints/SKILL.md)
    - [bin2linyaps.compat-testing build_meta.json](../bin2linyaps.compat-testing/SKILL.md)
    - [bin2linyaps.fix 技能](../bin2linyaps.fix/SKILL.md)

### 步骤 6：修改 `SKILL.md` — 目录约定小节新增 README/reference 条目

**文件**：`skills/bin2linyaps.external-missing-deps-fetch/SKILL.md`

**操作**：在 L36-41「目录约定」小节中，新增 README.md 和 reference/ 的条目。

**当前 L36-41 内容**（需先 read 确认确切行号）：
```markdown
## 目录约定

- `templates/linglong.yaml`：唯一修改目标（追加 `buildext.apt.depends`）
- `missing_deps_urls.conf`：生成产物，与 `pak_linyaps.sh` 同级
- `scripts/download_missing_deps.sh`：静态下载脚本，由 `deb.project-gen` 初始化时复制
```

**修改后**（新增 2 条）：
```markdown
## 目录约定

- `templates/linglong.yaml`：唯一修改目标（追加 `buildext.apt.depends`）
- `missing_deps_urls.conf`：生成产物，与 `pak_linyaps.sh` 同级
- `scripts/download_missing_deps.sh`：静态下载脚本，由 `deb.project-gen` 初始化时复制
- `README.md`：人类入口文档（集成时序/fix协作/pak_linyaps集成/conf格式），详见「相关文档」
- `reference/`：分主题参考文档，详见「相关文档」
```

### 步骤 7：修改 `SKILL.md` — 精简「注意事项」，移除已迁移条目

**文件**：`skills/bin2linyaps.external-missing-deps-fetch/SKILL.md`

**操作**：将 L104-112 的 7 条注意事项替换为 4 条（移除第 4/5/6 条，已迁移到 reference/）。

**原 7 条**：
1. 目标文件确认 → **保留**（新 1）
2. 绝不修改 build_tmp 文件 → **保留**（新 2）
3. missing_deps.* 由 ll-builder build 生成 → **保留**（新 3）
4. 生成的 conf 可人工编辑后重跑 → **移除**（已迁移到 `reference/pak_linyaps_integration.md`）
5. download 默认解压到 binary_dir → **移除**（已迁移到 `reference/pak_linyaps_integration.md`）
6. download 是静态脚本，初始化时复制 → **移除**（已迁移到 `reference/pak_linyaps_integration.md`）
7. 多次运行自动去重 → **保留**（新 4）

**替换后**：
```markdown
## 注意事项

1. **目标文件确认**：脚本只修改 `<project_dir>/templates/linglong.yaml`，该文件包含 `${ll_version}` 等 envsubst 变量。
2. **绝不修改 build_tmp 文件**：`build_tmp_dir/linglong.yaml` 是 `pak_linyaps.sh` 通过 `envsubst` 生成的瞬态副本，任何修改都会在下次构建时被覆盖。
3. `missing_deps.*` 由 `ll-builder build` 在 `build_tmp_dir` 中生成，需通过 `--build-tmp-dir` 参数传入。
4. 多次运行会自动去重，不会重复追加已存在的包名。
```

### 步骤 8：修改 `SKILL.md` — 在文件末尾新增「相关文档」链接区

**文件**：`skills/bin2linyaps.external-missing-deps-fetch/SKILL.md`

**操作**：在文件末尾（当前 L112 之后）新增「## 相关文档」小节。

**插入内容**：
```markdown

## 相关文档

- [README.md](README.md)：人类入口文档（概述/快速开始/脚本说明/工作流程/设计决策/故障排除）
- [端到端集成时序](reference/integration-timeline.md)：compat-testing → fetch → pak_linyaps 三阶段流水线时序
- [与 pak_linyaps.sh 的集成](reference/pak_linyaps_integration.md)：调用点/非阻塞语义/libfix 衔接/人工编辑重跑
- [与 bin2linyaps.fix 的协作](reference/fix_collaboration.md)：并列关系/边界声明/建议执行顺序
- [missing_deps_urls.conf 格式规范](reference/missing_deps_urls_conf_format.md)：注释头/数组/百分号编码/加载机制
```

## 验证

0. 读取新建的 `docs/external-missing-deps-fetch-integration-plan.md`，确认：内容与 `local://external-missing-deps-fetch-integration-plan.md` 完全一致（含步骤 0-8 全部内容）；文件命名遵循 `docs/` 约定（`<descriptive-name>-plan.md`）
1. 读取新建的 `README.md`，确认：
   - 结构仿 appimage.transfer/README.md（概述/功能特性/目录结构/快速开始/脚本说明/工作流程/协作/集成/设计决策/故障排除/相关链接）
   - 目录结构代码块含 SKILL.md / README.md / reference/（4 个文件）/ scripts/（2 个）/ examples/
   - 所有 reference/ 链接路径正确（相对路径）
2. 读取 4 个新建 `reference/*.md`，确认：
   - `integration-timeline.md`：mermaid 序列图语法正确（无未闭合 participant/message）；阶段表 5 行含具体行号；数据流向说明完整
   - `pak_linyaps_integration.md`：调用点代码块行号（deb L1039-1048 / appimage L793-802 / tar L973-982 / libfix L1053/L807/L987）与实际代码一致；非阻塞语义 + libfix 衔接 + 重跑命令 + download 行为细节完整
   - `fix_collaboration.md`：对比表 4 行；并列关系说明；建议先 fix 后 fetch 理由
   - `missing_deps_urls_conf_format.md`：格式示例 + 规范表（注释头 L214-216 / 数组 / %2b 编码）+ 加载机制 + 人工编辑规则 + 示例引用
3. 读取修改后的 `SKILL.md`，确认：
   - 目录约定新增 README.md + reference/ 条目
   - 注意事项从 7 条精简为 4 条（移除原 4/5/6）
   - 末尾新增「相关文档」链接区（5 条链接）
   - L1-102 的 LLM 契约部分（frontmatter/功能说明/关键约束/触发场景/输入/工作流程/输出产物/错误处理/依赖工具）未改动
4. `grep -r "missing_deps_urls.conf" skills/bin2linyaps.external-missing-deps-fetch/` 确认所有 conf 格式描述与 `examples/missing_deps_urls.conf` 实际文件（3 行注释头 + `MISSING_DEPS_URLS=(...)` 数组）一致

## 假设与应急措施

- **假设**：README.md 和 reference/ 目录路径在 SKILL.md 中用相对路径引用（`README.md` / `reference/xxx.md`），与仓库现有约定（appimage.transfer/README.md 引用 `../bin2linyaps.tar.transfer/`）一致。若 implementer 发现仓库有绝对路径约定，改为绝对路径。
- **假设**：reference/ 文件命名用 kebab-case（`integration-timeline.md` 而非 `integration_timeline.md`），与 `files_res_structure.md` 的 snake_case 不一致但更符合英文文档惯例。若 implementer 发现仓库 reference/ 统一用 snake_case，改为 `integration_timeline.md` 等。
- **contingency**：若 SKILL.md 实际行号与计划中记录的（L36-41 / L104-112）有偏移（文件可能被其他改动影响），implementer 先 `read` 确认确切行号再 edit。
