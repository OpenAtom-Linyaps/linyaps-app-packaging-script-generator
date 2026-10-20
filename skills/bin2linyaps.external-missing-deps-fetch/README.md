# bin2linyaps.external-missing-deps-fetch 技能

## 概述

本 skill 用于分析玲珑构建产生的缺失依赖报告（`missing_deps.json/csv`），通过 apt-file 反查 + apt-cache 核验，将缺失依赖追加到 `linglong.yaml` 的 `buildext.apt.depends`，并生成 `missing_deps_urls.conf` 供 `pak_linyaps.sh` 下载解压。位于 compat-testing → fetch → pak_linyaps 三阶段流水线的中间环节。

## 功能特性

### 核心功能

1. **缺失依赖分析**：读取 `missing_deps.json/csv`，通过 `apt-file` 反查 `.so` → 包名
2. **依赖核验门禁**：逐包 `apt-cache show` 核验（[constraints §5](../bin2linyaps.constraints/SKILL.md)），不存在的包剔除
3. **YAML 追加**：`ruamel.yaml` 追加 `buildext.apt.depends`（去重），保留 `${ll_version}` 等 envsubst 变量
4. **URL 配置生成**：`apt-get download --print-uris` 获取 URL，生成 `missing_deps_urls.conf`

## 目录结构

```
bin2linyaps.external-missing-deps-fetch/
├── SKILL.md                                # LLM 契约（约束/输入/工作流程/错误处理）
├── README.md                               # 本文档（人类入口）
├── reference/                              # 参考文档
│   ├── integration-timeline.md             # 端到端集成时序
│   ├── pak_linyaps_integration.md          # pak_linyaps.sh 集成细节
│   └── missing_deps_urls_conf_format.md    # conf 格式规范
├── scripts/
│   ├── fetch_missing_deps.sh               # 分析+生成脚本（244 行）
│   └── download_missing_deps.sh            # 静态下载解压脚本（113 行）
└── examples/
    └── missing_deps_urls.conf              # 示例配置
```

## 快速开始

### 场景 1：标准流程

```bash
# 1. 分析缺失依赖，追加到 linglong.yaml 并生成 conf
bash skills/bin2linyaps.external-missing-deps-fetch/scripts/fetch_missing_deps.sh \
  --project-dir=<project_dir> \
  --build-tmp-dir=<build_tmp_dir>

# 2. 重新构建（pak_linyaps.sh 自动检测 conf 并下载解压）
bash <project_dir>/templates/pak_linyaps.sh ...
```

### 场景 2：人工编辑 conf 后重跑

```bash
# 编辑 missing_deps_urls.conf 后，直接重跑下载解压
cd <project_dir>
bash scripts/download_missing_deps.sh              # 默认解压到 binary_dir
bash scripts/download_missing_deps.sh <target_dir> # 指定目标目录
```

## 脚本说明

### fetch_missing_deps.sh

**用法**：
```bash
./scripts/fetch_missing_deps.sh --project-dir=<proj> [--build-tmp-dir=<tmp>]
```

**流程**（5 步）：

1. 查找 `missing_deps.*`（优先 `--build-tmp-dir`，回退 `project_dir`；先 JSON 后 CSV）
2. 提取去重 `.so` 文件名 → `apt-file` 并行反查包名（L101-109）
3. 逐包 `apt-cache show` 核验存在性，剔除不存在的包（L114-133）
4. `ruamel.yaml` 追加 `buildext.apt.depends`（L144-177）
5. `apt-get download --print-uris` 获取 URL → 生成 `missing_deps_urls.conf`（L192-222）

### download_missing_deps.sh

**用法**：
```bash
./scripts/download_missing_deps.sh [<binary_dir>]
```

`source` 加载 `missing_deps_urls.conf` → `wget` 下载到 `DEB_CACHE` → `dpkg-deb` 解压 → `IMPORTANT_DIRS` 白名单复制到 `binary_dir`（`usr` 平铺）。静态脚本，初始化时由 `deb.project-gen` 复制，不依赖 fetch 是否执行。详见 [pak_linyaps.sh 集成细节](reference/pak_linyaps_integration.md) 行为细节表。

## 工作流程

详见 [端到端集成时序](reference/integration-timeline.md)。

| 阶段 | 执行者 | 关键产物 |
|------|--------|----------|
| ① 首次构建 | compat-testing step3 → pak_linyaps.sh → ll-builder build | `missing_deps.json/csv` |
| ② 元数据归集 | compat-testing step3b | `build_meta.json` |
| ③ 依赖分析 | fetch_missing_deps.sh | 更新的 `linglong.yaml` + `missing_deps_urls.conf` |
| ④ 结构修复（并列） | bin2linyaps.fix | 修复后的结构文件 |
| ⑤ 重新构建 | pak_linyaps.sh build_pak() | 最终玲珑包 |

## 与 bin2linyaps.fix 的协作

fix 与本 skill 是**并列关系**，非调用关系。二者无数据依赖，可任意顺序或并行执行；`bin2linyaps.fix` 修复结构验证问题，本 skill 修复运行时缺失动态库依赖。

| 维度 | bin2linyaps.fix | 本 skill |
|------|-----------------|----------|
| 修复对象 | 结构验证报告问题 | 运行时缺失动态库依赖 |
| 输入 | 验证报告 | `missing_deps.*` |
| 修改文件 | linglong.yaml/desktop/图标/权限 | linglong.yaml + conf |
| 修改字段 | 格式/base/runtime | `buildext.apt.depends` |

## 与 pak_linyaps.sh 的集成

详见 [pak_linyaps.sh 集成细节](reference/pak_linyaps_integration.md)。

`pak_linyaps.sh` `build_pak()` 检测 `missing_deps_urls.conf` 存在时，调用 `download_missing_deps.sh` 下载解压（非阻塞），之后执行 `handle_special_paths.sh --phase=libfix` 补 `.so` 软链。

## 设计决策

1. **非阻塞设计**：download 失败不中断构建（`if/else` 包裹），`ll-builder build` 仍会执行。
2. **apt-cache 核验门禁**：[constraints §5](../bin2linyaps.constraints/SKILL.md) 要求，防止写入 apt 仓库中不存在的包。
3. **usr 平铺**：`IMPORTANT_DIRS` 白名单中 `usr` 平铺进 `binary_dir`（`usr/bin` → `bin`），匹配玲珑 `$prefix` 结构。
4. **静态 download 脚本**：不依赖 fetch 是否执行，用户可手动创建 conf 直接调用。

## 故障排除

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| `missing_deps_urls.conf 未检测到` | 未运行 fetch 或 conf 路径不在 project_root | 运行 `fetch_missing_deps.sh` |
| `apt-cache show 失败` | 包名不存在于仓库 | 检查 apt 源，包被剔除是预期行为 |
| `download 失败但构建继续` | 非阻塞设计 | 查看 stderr 警告，检查 URL 可达性 |
| `.so 软链缺失` | libfix 未覆盖 | 确认 `handle_special_paths.sh` 在 download 之后执行 |

## 相关链接

- [端到端集成时序](reference/integration-timeline.md)
- [pak_linyaps.sh 集成细节](reference/pak_linyaps_integration.md)
- [missing_deps_urls.conf 格式规范](reference/missing_deps_urls_conf_format.md)
- [bin2linyaps.constraints §5 依赖核验](../bin2linyaps.constraints/SKILL.md)
- [bin2linyaps.compat-testing build_meta.json](../bin2linyaps.compat-testing/SKILL.md)
- [bin2linyaps.fix 技能](../bin2linyaps.fix/SKILL.md)
