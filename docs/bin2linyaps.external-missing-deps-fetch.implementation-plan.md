# bin2linyaps.external-missing-deps-fetch 实现计划

## 目录结构

```
skills/bin2linyaps.external-missing-deps-fetch/
  SKILL.md          # Skill 定义与编排文档
  scripts/
    fetch_missing_deps.sh   # 主脚本: 解析→搜索→更新yaml→生成conf
    download_missing_deps.sh # 静态下载脚本: 解析conf→下载→解压
```

## 产物清单

执行后向项目目录（`CI_ll_xxx`）输出以下文件（与 `linglong.yaml` 同级）：

| 文件 | 说明 |
|------|------|
| `missing_deps_urls.conf` | 外置URL配置文件，可人工编辑 |

下载解压由静态脚本 `scripts/download_missing_deps.sh` 完成（项目初始化时复制到项目 `scripts/` 目录）。

## SKILL.md 结构

**YAML frontmatter:**
```yaml
---
name: bin2linyaps.external-missing-deps-fetch
description: >
  分析玲珑构建生成的缺失依赖报告(missing_deps.csv/json)，
  自动查找并补充外部依赖包到linglong.yaml的buildext.apt.depends，
  同时生成deb下载URL配置与解压脚本供打包流程使用。
user-invocable: false
---
```

**正文章节：**
1. `# 外部缺失依赖获取`
2. `## 功能说明`
3. `## 触发场景`
4. `## 参考实现`
5. `## 输入`
6. `## 工作流程` — 7 个步骤，引用 `scripts/fetch_missing_deps.sh`
7. `## 输出`
8. `## 依赖工具`
9. `## 注意事项`

---

## `scripts/fetch_missing_deps.sh` 详细设计

### 用法
```bash
./fetch_missing_deps.sh <project_dir>
```

### 步骤

| 步骤 | 操作 | 实现方案 |
|------|------|----------|
| **1. 参数校验** | 检查 `$1` 是否存在、是否为目录 | `[ -d "$1" ]` |
| **2. 查找缺失依赖文件** | 优先 JSON 回退 CSV | `test -f missing_deps.json` → jq；否则 CSV → awk |
| **3. 提取去重 so 文件名** | 取 dependency 列，去重排序 | `jq -r '.[].dependency' \| sort -u` 或 `awk -F, 'NR>1{print $1}' \| sort -u` |
| **4. apt-file 搜索包名** | 对每个 so 模糊匹配所属包 | `apt-file search -x "/${so}$" \| cut -d: -f1 \| sort -u`，`xargs -P $(nproc)` 并行 |
| **5. 更新 linglong.yaml** | 追加 `buildext.apt.depends` | `yq eval` 读已有列表 → 合并去重 → 写回 |
| **6. 获取下载 URL** | dry-run 获取完整 deb URL | `apt-get download --print-uris <pkg> \| awk -F"'" '{print $2}'` |
| **7. 生成 conf** | 写入 `missing_deps_urls.conf` | shell 模板，URL 列表写入 conf |
| **8. 输出摘要** | 打印结果 | 包数、so数、生成文件路径 |

---

## 关键文件格式

### `missing_deps_urls.conf`

```bash
# 由 bin2linyaps.external-missing-deps-fetch 自动生成，位于 CI_ll_xxx/
# 可人工编辑：增删改 URL 行后重新运行 download_missing_deps.sh 即可
MISSING_DEPS_URLS=(
  "https://ci.deepin.com/repo/deepin/deepin-community/stable/pool/community/s/sl/sl_5.02-1_amd64.deb"
  "https://ci.deepin.com/repo/deepin/deepin-community/stable/pool/main/z/zlib1g/zlib1g_1.3.dfsg+really1.3.2-1deepin2_amd64.deb"
)
```

### `download_missing_deps.sh`（静态脚本）

由项目初始化时复制到项目 `scripts/` 目录，不依赖 `fetch_missing_deps.sh` 是否执行过：

```bash
#!/bin/bash
# 通用下载解压脚本，解析项目根目录的 missing_deps_urls.conf
# 用法: ./download_missing_deps.sh [binary_dir 路径]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF_FILE="${PROJECT_ROOT}/missing_deps_urls.conf"
BINARY_DIR="${1:-${PROJECT_ROOT}/binary_dir}"

if [ ! -f "$CONF_FILE" ]; then
  echo "INFO: 未找到 missing_deps_urls.conf，无需下载"
  exit 0
fi

source "$CONF_FILE"

if [ ${#MISSING_DEPS_URLS[@]} -eq 0 ]; then
  echo "INFO: 没有需要下载的依赖包"
  exit 0
fi

DEB_CACHE="/tmp/lingyaps-debs"
mkdir -p "$BINARY_DIR" "$DEB_CACHE"

for url in "${MISSING_DEPS_URLS[@]}"; do
  deb_file="$DEB_CACHE/$(basename "$url")"
  echo "下载: $url"
  wget -q "$url" -O "$deb_file" || { echo "WARN: 下载失败: $url"; continue; }
  echo "解压: $deb_file → $BINARY_DIR"
  dpkg -x "$deb_file" "$BINARY_DIR" || { echo "WARN: 解压失败: $deb_file"; continue; }
  rm -f "$deb_file"
done

echo "完成: 已下载并解压 ${#MISSING_DEPS_URLS[@]} 个依赖包到 $BINARY_DIR"
```

### linglong.yaml 更新示例

```yaml
buildext:
  apt:
    depends:
    - ca-certificates
    - libcairo2              # 原有
    - libexample.so 的提供包   # ← 追加的新包
```

---

## 依赖工具

| 工具 | 用途 | 备注 |
|------|------|------|
| `jq` | 解析 missing_deps.json | performance 优先 |
| `awk` | 解析 missing_deps.csv | 回退方案 |
| `sort` / `uniq` | so 文件名去重 | |
| `xargs` | 并行 apt-file 搜索 | `-P $(nproc)` |
| `apt-file` | so → pkg 反向查找 | 需提前 `apt-file update` |
| `yq` | 修改 linglong.yaml | |
| `apt-get` | 获取 deb 下载 URL | `download --print-uris` dry-run |
| `wget` | 下载 deb | 在静态下载脚本中使用 |
| `dpkg` | 解压 deb | `dpkg -x` |

---

## 错误处理策略

| 场景 | 行为 |
|------|------|
| 项目目录不存在 | exit 1，错误信息 |
| 无 missing_deps 文件 | exit 1，提示上一流程未产生 |
| apt-file 搜索无结果 | warning 到 stderr，跳过该 so |
| 包名已存在于 depends | 自动去重，不重复写入 |
| apt-get 获取 URL 失败 | warning 到 stderr，跳过该包 |
| linglong.yaml 不存在 | exit 1 |
| 没有 `buildext` 或 `apt` 字段 | 自动创建 |

---

## 验证方式

1. 复制 `examples/missing_deps.example.json` 到临时 `CI_ll_test/missing_deps.json`
2. 创建 `CI_ll_test/linglong.yaml`（含基本结构）
3. 运行 `./scripts/fetch_missing_deps.sh CI_ll_test`
4. 检查:
   - `linglong.yaml` 是否追加了 `buildext.apt.depends`
   - `missing_deps_urls.conf` 是否包含有效 URL
   - URL 去重是否正确