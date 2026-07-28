---
name: bin2linyaps.external-missing-deps-fetch
description: >
  分析玲珑构建生成的缺失依赖报告(missing_deps.csv/json)，
  自动查找并补充外部依赖包到linglong.yaml的buildext.apt.depends，
  同时生成deb下载URL配置与解压脚本供打包流程使用。
user-invocable: false
---

# 外部缺失依赖获取

## 功能说明

分析玲珑构建过程中生成的缺失依赖报告（missing_deps.csv 或 missing_deps.json），对每个缺失的 `.so` 文件通过 `apt-file` 反向查找所属包名，将包名追加到 `linglong.yaml` 的 `buildext.apt.depends` 中，同时获取对应 deb 包的下载 URL，生成外置配置文件 `missing_deps_urls.conf` 和下载解压脚本 `download_missing_deps.sh`。

## 触发场景

- 玲珑 `ll-builder build` 构建完成但运行时缺少动态库依赖
- `missing_deps.json` 或 `missing_deps.csv` 已由自动化测试流程生成
- 需要将外部系统库纳入玲珑打包工程的 `depends` 和下载流程

## 工作流程

执行 `scripts/fetch_missing_deps.sh <project_dir>`：

### 1. 参数校验
检查项目目录是否存在。

### 2. 查找缺失依赖文件
- 优先读取 `missing_deps.json`（用 `jq` 解析）
- 回退读取 `missing_deps.csv`（用 `awk` 解析）

### 3. 提取并去重 so 文件名
- JSON：`jq -r '.[].dependency'` → `sort -u`
- CSV：`awk -F, 'NR>1{print $1}'` → `sort -u`

### 4. apt-file 搜索包名
对每个 so 文件执行 `apt-file search -x "/${so}$"`，用 `xargs -P $(nproc)` 并行搜索，提取所属包名并去重。

### 5. 更新 linglong.yaml
读取已有 `buildext.apt.depends` 列表，合并去重后写回。

### 6. 获取下载 URL
对每个新包执行 `apt-get download --print-uris <pkg>`，用 `awk` 提取 URL。

### 7. 生成 conf + 下载脚本
- `missing_deps_urls.conf`：URL 列表（可人工编辑）
- `download_missing_deps.sh`：读取 conf 下载并 `dpkg -x` 解压

### 8. 输出摘要
打印包数量、so 数量、生成文件路径。

## 输出产物

| 文件 | 路径 | 说明 |
|------|------|------|
| 更新后的 `linglong.yaml` | `<project_dir>/linglong.yaml` | `buildext.apt.depends` 追加了新包名 |
| `missing_deps_urls.conf` | `<project_dir>/missing_deps_urls.conf` | 外置 URL 配置，可人工编辑 |
| `download_missing_deps.sh` | `<project_dir>/download_missing_deps.sh` | 通用下载解压脚本 |

## 错误处理

| 场景 | 行为 |
|------|------|
| 项目目录不存在 | exit 1，错误信息 |
| 无 missing_deps 文件 | exit 1，提示上一流程未产生 |
| apt-file 搜索无结果 | warning 到 stderr，跳过该 so |
| 包名已存在于 depends | 自动去重，不重复写入 |
| apt-get 获取 URL 失败 | warning 到 stderr，跳过该包 |
| linglong.yaml 不存在 | exit 1 |
| 没有 `buildext.apt` 字段 | 自动创建 |
| 没有 `depends` 列表 | 自动创建 |

## 依赖工具

| 工具 | 用途 | 备注 |
|------|------|------|
| `jq` | 解析 missing_deps.json | |
| `awk` | 解析 missing_deps.csv | 回退方案 |
| `sort` / `uniq` | 去重 | |
| `xargs` | 并行 apt-file 搜索 | `-P $(nproc)` |
| `apt-file` | so → 包名反向查找 | 需 `apt-file update` |
| `python3` + `ruamel.yaml` | 修改 linglong.yaml | 保留 YAML 格式 |
| `apt-get` | 获取 deb 下载 URL | `download --print-uris` |
| `wget` | 下载 deb | 用于生成的脚本 |
| `dpkg` | 解压 deb | 用于生成的脚本 |

## 注意事项

1. 运行前需确保 `apt-file update` 已执行
2. 生成的 `missing_deps_urls.conf` 中的 URL 可人工编辑后重新运行 `download_missing_deps.sh`
3. `download_missing_deps.sh` 默认解压到 `<project_dir>/binary_dir`，可通过参数指定
4. 多次运行会自动去重，不会重复追加已存在的包名