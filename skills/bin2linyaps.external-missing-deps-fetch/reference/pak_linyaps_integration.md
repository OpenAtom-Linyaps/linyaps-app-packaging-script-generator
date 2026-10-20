# 与 pak_linyaps.sh 的集成

## 调用点

`pak_linyaps.sh` 的 `build_pak()` 函数在三个模板中包含完全相同的调用块：

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

三个模板（`deb.project-gen` / `appimage.transfer` / `tar.transfer`）的调用块完全相同，仅行号不同。

## 非阻塞语义

`download_missing_deps.sh` 失败时仅输出警告到 stderr，不中断后续构建。调用被 `if/else` 包裹：

- 成功 → `echo "外部缺失依賴下載解壓完成"`
- 失败 → `echo "警告..." >&2`，继续执行

无论 download 成功或失败，`ll-builder build` 仍会执行。

## libfix 衔接

`handle_special_paths.sh --phase=libfix` 在 download **之后**执行，为 `binary_dir/lib/` 下非标准目录及多架构子目录的 ELF 共享库创建相对路径软链，并补全 SONAME 级软链（如 `libtiff.so.5`）。

**必须在 download 之后**：download 引入的新库需要被 libfix 扫描到，否则无法覆盖新引入的库。

## 人工编辑 conf 后重跑

```bash
# 在项目目录（CI_ll_xxx/）下执行
bash scripts/download_missing_deps.sh              # 默认解压到 binary_dir
bash scripts/download_missing_deps.sh <target_dir> # 指定目标目录
```

无需重新执行 `fetch_missing_deps.sh`。增删改 `missing_deps_urls.conf` 中的 URL 行后直接重跑 `download_missing_deps.sh` 即可。

## download_missing_deps.sh 行为细节

| 要点 | 说明 |
|------|------|
| `DEB_CACHE=/tmp/lingyaps-debs` | 下载缓存目录，缓存命中时跳过下载 |
| `IMPORTANT_DIRS` 白名单 | `usr bin sbin lib lib32 lib64 libexec include share local`，仅复制白名单内顶层目录 |
| `usr` 平铺机制 | `usr/bin` → `binary_dir/bin`（平铺进 binary_dir），其余白名单目录直接复制 |
| 不依赖 fetch | 静态脚本，用户手动创建 `missing_deps_urls.conf` 后可直接调用 |
| deb 校验 | `dpkg-deb -I` 校验下载内容确为 deb，拦截返回 200 的 HTML 错误页 |
| URL 解码 | `python3 urllib.parse.unquote` 还原 `%2b`/`%20` 等百分号编码，得到干净缓存文件名 |

## 写入门禁（constraints §5）

`fetch_missing_deps.sh` L114-133 实现 `bin2linyaps.constraints` §5 的 `apt-cache show` 核验门禁：`apt-file` 搜索到的包名在追加进 `buildext.apt.depends` 前必须逐包通过 `apt-cache show` 核验（以 stdout 出现 `Package:` 为准）；不存在的包一律剔除，禁止写入 `depends`。

详见 [bin2linyaps.constraints §5 依赖核验](../../bin2linyaps.constraints/SKILL.md)。
