# 修复：binaryDir 含中文/非 ASCII 路径时 pak_linyaps 无法正常工作

## 背景

`examples/ppthelper-agent_1.0.8_amd64.deb` 内包含一个中文命名的二进制目录 `/opt/PPT遥控翻页/`。当 `handle_special_paths.sh` 对该路径做规范化时，应用目录会被重命名为不透明哈希 `bfa33cee`，丢失可读的 ASCII 前缀 "PPT"，导致玲珑包内应用目录命名被破坏。

`examples/com.hymake.nucleus_3.9.0_amd64.deb` 进一步暴露问题：其可执行文件位于纯中文目录 `bin/费用定额/` 下、二进制本身名为 `海迈云计价平台`。旧逻辑会把这些中文名全部哈希化为不可读的随机串，且入口 `rel_binary` 被破坏。

## 根因（旧方案）

`normalize_dirname()` / `normalize_filename()` 中使用：

```bash
normalized_name=$(echo "${normalized_name}" | sed 's/[^ -~]/_/g')
```

`[^ -~]` 字符区间依赖**进程当前 locale**。在 multibyte locale（如 `zh_CN.UTF-8`）下，`[ -~]` 按 locale 排序规则解释，会把 **ASCII 字母也一并匹配掉**。

实测：

| 输入 | 当前(UTF-8) `sed 's/[^ -~]/_/g'` | `LC_ALL=C sed 's/[^ -~]/_/g'` |
|------|------|------|
| `PPT遥控翻页` | `_______`（丢失 PPT） | `PPT____________`（保留 PPT） |

旧逻辑最终将所有非 ASCII 替换为 `_` 并附加 `md5sum` 哈希（如 `PPT遥控翻页` → `PPT_bfa33cee`），中文名不再可读，也无法定位入口二进制。

## 修复方案（已实施）

不再对非 ASCII（中文等）字符做哈希化/替换，而是**原样保留**。仅规范化真正会被 shell 误解析的 ASCII 字符（空格、逗号、开头 `-`、`#`、`$`），并在生成 wrapper 时对嵌入的入口路径做 shell 转义：

1. `normalize_dirname()` / `normalize_filename()`：移除 `[^ -~]` 非 ASCII 替换与哈希拼接；保留空格/逗号/`&#$`/开头 `-` 的替换及连续下划线清理。中文文件名原样输出。
2. `pak_linyaps.sh`（deb/appimage/tar 三份模板）新增 `shell_escape()` 辅助函数，转义 `\`、`"`、`` ` ``、`$`。生成 wrapper 时对 `rel_binary`（deb/tar）及 `lib/${app_prefix}/${wrapper_target}`（appimage）先转义再嵌入 `exec` 语句，保证含中文/括号/特殊字符的路径也能被 bash 安全加载。
3. `detect_potential_issues` 中保留非 ASCII **警告**（仅报告、不改名），便于知情。

## 涉及文件

| 文件 | 改动 |
|------|------|
| `skills/bin2linyaps.deb.project-gen/scripts/handle_special_paths.sh` | 移除非 ASCII 哈希化，保留原名 |
| `skills/bin2linyaps.appimage.transfer/scripts/handle_special_paths.sh` | 同上（3 份 MD5 一致，保持同步） |
| `skills/bin2linyaps.tar.transfer/scripts/handle_special_paths.sh` | 同上（3 份 MD5 一致，保持同步） |
| `skills/bin2linyaps.deb.project-gen/templates/pak_linyaps.sh` | 新增 `shell_escape()`，转义 wrapper 内入口路径 |
| `skills/bin2linyaps.appimage.transfer/templates/pak_linyaps.sh` | 同上 |
| `skills/bin2linyaps.tar.transfer/templates/pak_linyaps.sh` | 同上 |

## 回归测试

`skills/bin2linyaps.deb.project-gen/tests/test_handle_special_paths.sh`（10/10 通过）。

### 用例 A：单元级 normalize（含中文/非 ASCII）

- `PPT遥控翻页` → **原样保留** `PPT遥控翻页`（不再哈希化）—— **修复前必失败**（得到 `PPT_bfa33cee`）
- 纯中文 `遥控翻页` → `遥控翻页`
- 纯 ASCII `uTools` → 保持不变
- 含空格/括号/`&` 的路径 → 规范化后仍可读

### 用例 B：端到端，用真实 deb

- 定位仓库根下 `examples/ppthelper-agent_1.0.8_amd64.deb`
- `dpkg -x` 解包 → 调用真实 `handle_special_paths.sh --phase=paths`
- 断言：
  1. 应用目录保留原名：存在以 `PPT遥控翻页` 开头的目录（修复前为裸 `bfa33cee`）
  2. 可执行文件 `ppthelper-agent` 可被 `find -executable` 找到

### 用例 C：端到端，nucleus（纯中文入口）

- `examples/com.hymake.nucleus_3.9.0_amd64.deb`
- 断言 `bin/费用定额/` 目录与 `bin/费用定额/海迈云计价平台` 可执行文件均原样保留，且生成的 wrapper 能正常 `exec` 该中文二进制。

deb 文件缺失时自动跳过（skip），不报错。

## 验证步骤

1. 修复前运行测试：用例 A/B 失败（证明能捕获 bug）
2. 应用修复后运行测试：全部通过
3. 顺带运行 `test_pak_linyaps.sh`、`test_dedup_desktop_files.sh` 防回归

## 范围说明

- 仅改规范化逻辑（移除非 ASCII 哈希化）、pak_linyaps wrapper 转义、新增测试文件，不触碰其他逻辑。
- appimage/tar 的 `handle_special_paths.sh` 与 `pak_linyaps.sh` 做同款改动（保持 3 份 MD5 一致），测试聚焦 deb 实际用例。
