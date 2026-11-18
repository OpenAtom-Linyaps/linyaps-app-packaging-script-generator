# missing_deps_urls.conf 格式规范

## 格式示例

```bash
# 由 bin2linyaps.external-missing-deps-fetch 自动生成
# 位于 CI_ll_xxx/，与 pak_linyaps.sh 同级
# 可人工编辑：增删改 URL 行后重新运行 download_missing_deps.sh 即可
MISSING_DEPS_URLS=(
  "https://pools.uniontech.com/.../libqt4-xmlpatterns_4.8.7%2bdfsg.6-1%2bdde_amd64.deb"
)
```

## 格式规范表

| 部分 | 说明 | 生成位置 |
|------|------|----------|
| 3 行注释头 | 固定内容，标识生成来源、位置、可编辑提示 | 写死在 `fetch_missing_deps.sh` L214-216 |
| `MISSING_DEPS_URLS=(...)` | bash 数组，每行一个 URL（带引号） | `fetch_missing_deps.sh` L217-219 |
| URL 百分号编码 | `+` 编码为 `%2b`，` ` 编码为 `%20` 等 | 由 `apt-get download --print-uris` 输出（L192-207） |

## 加载机制

`download_missing_deps.sh` 通过 `source "${PROJECT_ROOT}/missing_deps_urls.conf"` 加载 `MISSING_DEPS_URLS` 数组（L20-21）。

加载前临时关闭 `set -u`（L18-21），避免 conf 未定义数组时中断。

## 人工编辑规则

- 增删改 URL 行后重新运行 `download_missing_deps.sh` 即可，无需重新执行 `fetch_missing_deps.sh`。
- 保持 3 行注释头 + `MISSING_DEPS_URLS=(...)` 数组语法不变。
- 每个 URL 用双引号包裹，单独一行。

## 示例文件引用

- [`examples/missing_deps_urls.conf`](../examples/missing_deps_urls.conf)：仓库内示例，URL 指向 `ci.deepin.com/repo/deepin/deepin-community`，含 2 个 URL。
- 项目初始化时该文件不自动复制；`missing_deps_urls.conf` 由 `fetch_missing_deps.sh` 运行时生成到项目根目录。
