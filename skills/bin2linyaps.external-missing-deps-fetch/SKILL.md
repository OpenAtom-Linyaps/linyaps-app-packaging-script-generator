---
name: bin2linyaps.external-missing-deps-fetch
description: >
  分析玲珑构建生成的缺失依赖报告(missing_deps.csv/json)，
  自动查找并补充外部依赖包到 linglong.yaml 模板的 buildext.apt.depends，
  同时生成 deb 下载 URL 配置与解压脚本。
user-invocable: false
---

# 外部缺失依赖获取

## 功能说明

分析玲珑构建过程中生成的缺失依赖报告（`missing_deps.json` 或 `missing_deps.csv`），对每个缺失的 `.so` 文件通过 `apt-file` 反向查找所属包名，将包名追加到 `templates/linglong.yaml` 的 `buildext.apt.depends` 中（保留 `${ll_version}` 等 envsubst 变量），同时生成外置配置文件 `missing_deps_urls.conf`。
项目初始化时，静态脚本 `scripts/download_missing_deps.sh` 会被复制到项目 `scripts/` 目录，
由 `pak_linyaps.sh` 在构建时调用，解析 `missing_deps_urls.conf` 并下载解压 deb 包。

## 关键约束

- **只修改 `<project_dir>/templates/linglong.yaml`**（含 envsubst 变量的源模板）
- **绝不修改 `build_tmp_dir` 中的任何文件**（`pak_linyaps.sh` 通过 `envsubst` 从模板生成的瞬态副本）
- `missing_deps.*` 由 `ll-builder build` 在 `build_tmp_dir` 中生成，脚本通过 `--build-tmp-dir` 参数读取
- **写入门禁**：`apt-file` 搜索到的包名，在追加进 `buildext.apt.depends` 前必须逐包通过 `apt-cache show` 核验其存在于当前 apt 仓库（以 stdout 出现 `Package:` 为准）；不存在的包一律剔除，禁止写入 `depends`

## 触发场景

- 玲珑 `ll-builder build` 构建完成但运行时缺少动态库依赖
- `missing_deps.json` 或 `missing_deps.csv` 已由 `bin2linyaps.compat-testing` 步骤 3（构建测试）生成（注意：compat-testing 为可选步骤，仅在提示词包含"兼容测试"时执行，此步骤随之跳过）
- 需要将外部系统库纳入玲珑打包工程的 `depends` 和下载流程

## 目录约定

- 主脚本：`scripts/fetch_missing_deps.sh`
- 静态下载脚本：`scripts/download_missing_deps.sh`（由项目初始化时复制到项目 `scripts/` 目录）
- 模板文件（待修改）：`<project_dir>/templates/linglong.yaml`
- 生成文件：`<project_dir>/missing_deps_urls.conf`

## 输入

```bash
bash skills/bin2linyaps.external-missing-deps-fetch/scripts/fetch_missing_deps.sh \
  --project-dir=<project_dir> \
  [--build-tmp-dir=<build_tmp_dir>]
```

参数：
- `--project-dir`：必须，指向 `CI_ll_xxx` 工程目录
- `--build-tmp-dir`：可选，指向 `pak_linyaps.sh` 构建时使用的临时目录（`ll-builder build` 在其中执行，生成 `missing_deps.*`）；未指定时回退搜索 `<project_dir>/missing_deps.*`

## 工作流程

| 步骤 | 操作 | 实现 |
|------|------|------|
| 1 | 参数解析与校验 | `--project-dir` 存且为目录 |
| 2 | 查找缺失依赖文件 | 优先 `--build-tmp-dir`，回退 `project_dir`；先 JSON 后 CSV |
| 3 | 提取去重 so 文件名 | `jq -r` (JSON) / `awk -F,` (CSV) → `sort -u` |
| 4 | apt-file 并行搜索包名 | `xargs -P $(nproc)` + `apt-file search -x` |
| 5 | **逐包核验 apt 仓库存在性** | 对 `apt-file` 结果逐包 `apt-cache show`，不存在的剔除 |
| 6 | 更新 `<project_dir>/templates/linglong.yaml` | `ruamel.yaml` 追加 `buildext.apt.depends`，保留 envsubst 变量 |
| 7 | 获取 deb 下载 URL | `apt-get download --print-uris` |
| 8 | 生成 `missing_deps_urls.conf` | 生成到 `<project_dir>/` |
| 9 | 输出摘要 | 包数、so 数、生成文件路径 |

## 输出产物

| 文件 | 路径 | 说明 |
|------|------|------|
| 更新后的 `templates/linglong.yaml` | `<project_dir>/templates/linglong.yaml` | `buildext.apt.depends` 追加了新包名，保留 `${ll_version}` 等变量 |
| `missing_deps_urls.conf` | `<project_dir>/missing_deps_urls.conf` | 外置 URL 配置，可人工编辑 |
| `download_missing_deps.sh` | 静态脚本，由项目初始化时复制到 `<project_dir>/scripts/` | 通用下载解压脚本，读取 conf 执行下载解压 |

## 错误处理

| 场景 | 行为 |
|------|------|
| `--project-dir` 目录不存在 | exit 1 |
| 无 `missing_deps` 文件 | exit 0（info，非错误） |
| `templates/linglong.yaml` 不存在 | exit 1，提示目标应为模板而非 build_tmp 副本 |
| apt-file 搜索无结果 | warning 到 stderr，跳过该 so |
| apt-file 命中但包不在当前 apt 仓库 | warning 到 stderr，剔除该包，不写入 depends |
| 包名已存在于 depends | 自动去重，不重复写入 |
| apt-get 获取 URL 失败 | warning 到 stderr，跳过该包 |
| 没有 `buildext` 或 `apt` 字段 | 自动创建 |

## 依赖工具

| 工具 | 用途 | 备注 |
|------|------|------|
| `jq` | 解析 missing_deps.json | |
| `awk` | 解析 missing_deps.csv | 回退方案 |
| `xargs` | 并行 apt-file 搜索 | `-P $(nproc)` |
| `apt-file` | so → 包名反向查找 | 需 `apt-file update` |
| `apt-cache` | 逐包核验包存在性 | 写入门禁，stdout 出现 `Package:` 为准 |
| `python3` + `ruamel.yaml` | 修改 linglong.yaml | 保留 YAML 格式和 envsubst 变量 |
| `apt-get` | 获取 deb 下载 URL | `download --print-uris` |
| `wget` | 下载 deb | 用于静态下载脚本 `download_missing_deps.sh` |
| `dpkg` | 解压 deb | 用于静态下载脚本 `download_missing_deps.sh` |

## 注意事项

1. **目标文件确认**：脚本只修改 `<project_dir>/templates/linglong.yaml`，该文件包含 `${ll_version}` 等 envsubst 变量。
2. **绝不修改 build_tmp 文件**：`build_tmp_dir/linglong.yaml` 是 `pak_linyaps.sh` 通过 `envsubst` 生成的瞬态副本，任何修改都会在下次构建时被覆盖。
3. `missing_deps.*` 由 `ll-builder build` 在 `build_tmp_dir` 中生成，需通过 `--build-tmp-dir` 参数传入。
4. 生成的 `missing_deps_urls.conf` 中的 URL 可人工编辑后重新运行 `download_missing_deps.sh`（位于项目 `scripts/` 目录下的静态脚本）。
5. `download_missing_deps.sh` 默认解压到 `<project_dir>/binary_dir`，可通过位置参数指定目标目录。
6. `download_missing_deps.sh` 是静态脚本，由项目初始化时复制到项目 `scripts/` 目录，不依赖 `fetch_missing_deps.sh` 是否执行过。用户手动创建 `missing_deps_urls.conf` 后，`pak_linyaps.sh` 可直接调用它下载解压。
7. 多次运行会自动去重，不会重复追加已存在的包名。
