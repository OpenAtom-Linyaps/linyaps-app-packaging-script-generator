# pak_linyaps：跳过特殊路径处理选项

## 背景

`handle_special_paths.sh --phase=paths` 会把文件名/目录名中含空格、逗号、括号、`& # $`、开头 `-` 的名称统一替换为 `_`（规范化）。部分二进制/依赖**内部硬编码了这些不规范原始文件名**（例如按字面名称通过 `dlopen`/配置文件加载插件模块），改名会导致运行时无法识别。

因此为 `pak_linyaps` 增加一个显式 opt-in 选项 `--skip_special_paths` 以禁用该规范化——即 disable fallback——同时仍执行必需的路径层级放置（`/usr` 内容 → 根、`/opt` 内容 → 根、`.so` 软链修复）。默认保持开启规范化，不传该选项时行为不变。

## 新增选项 `--skip_special_paths`

- 默认 `false`，显式 opt-in，接受 `true`/`1`（任意非空 `=value` 即视为 true，与 `auto_clean`/`auto_push` 一致）。
- 置为 `true` 时保留原始文件名/目录名，跳过 paths 阶段的改名规范化。

## 脚本旗标 `--skip_normalize`

`handle_special_paths.sh --phase=paths <src> <dest> --skip_normalize` 跳过 `normalize_dirname` / `normalize_filename` 的改名，原样保留原始名。

- 该旗标只影响 paths 阶段；libfix 阶段（`.so` 软链补全）不受影响。
- 跳过规范化**仍保留结构放置**：`/usr` → 根、`/opt` → 根、软链修复均照常执行，仅保留文件名字面拼写。
- **不做** `--phase=paths` 的完全旁路——那会把内容残留在 `binary/usr/...` 破坏布局。

## 作用范围

- deb 与 tar 两个 pak 模板：`skills/bin2linyaps.deb.project-gen/templates/pak_linyaps.sh`、`skills/bin2linyaps.tar.transfer/templates/pak_linyaps.sh`。
- appimage 分支不受影响：其 pak 模板对 `handle_special_paths.sh` 的唯一调用是 `--phase=libfix`，从不运行 paths 阶段；且 `extract_appimage.sh` 仅原样解压、本身无文件名标准化——appimage 默认即保留原始文件名，无规范化可跳过，故不加 pak 选项。
- `handle_special_paths.sh` 的 3 份副本（deb.project-gen、tar.transfer、appimage.transfer）保持字节一致，统一应用脚本修改。

## 用法示例

经 `pak_linyaps` 启用：

```bash
pak_linyaps.sh ... --skip_special_paths=true
```

直接调用脚本：

```bash
handle_special_paths.sh --phase=paths <src_dir> <dest_dir> --skip_normalize
```

## 默认行为不变

不传该选项时，规范化照常执行：空格、逗号、括号、`& # $`、开头 `-` 等特殊字符仍统一替换为 `_`。
