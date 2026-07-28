# 为 pak_linyaps 添加软链处理能力 — 实施方案

## 参考来源

`linyaps-pica-helper.sh` L567 `nonStrDirLibsScanAndFix()` 函数中的软链处理逻辑。

## 目标

在 `skills/bin2linyaps.deb.project-gen`、`skills/bin2linyaps.tar.transfer`、`skills/bin2linyaps.appimage.transfer` 三个 skill 的 `pak_linyaps.sh` 中，通过外部脚本新增对非标准目录 `.so` 文件的软链处理能力。

## 步骤 1：创建外部脚本

在三个 skill 的 `scripts/` 目录下各创建一份 `fix_nonstd_lib_symlinks.sh`（内容相同）：

| 目标路径 |
|---------|
| `skills/bin2linyaps.deb.project-gen/scripts/fix_nonstd_lib_symlinks.sh` |
| `skills/bin2linyaps.tar.transfer/scripts/fix_nonstd_lib_symlinks.sh` |
| `skills/bin2linyaps.appimage.transfer/scripts/fix_nonstd_lib_symlinks.sh` |

### 脚本核心逻辑

1. 接收 `binary_dir` 参数
2. 扫描 `binary_dir` 下所有 `*.so*` 文件（含软链），排除已在 `binary_dir/lib/` 下的文件
3. 对每个文件：
   - 解析真实路径（`readlink -f` 跟随软链）
   - 仅处理 ELF 共享库（`file` 命令检测）
   - 用 `realpath --relative-to` 计算相对路径
   - 在 `binary_dir/lib/` 下创建相对路径软链
4. 处理版本化命名：若原始库名（如 `libfoo.so`）未找到但版本化文件（如 `libfoo.so.1.0.0`）存在，额外创建 `libfoo.so → libfoo.so.1.0.0` 软链
5. 跳过损坏软链、非 ELF 文件、已存在的正确软链

## 步骤 2：修改三个 `pak_linyaps.sh`

在 `build_pak()` 函数的 `validate_bin_nesting.sh` 调用之后、`touch .linyaps_genius` 之前，统一插入：

```bash
# 修复非标准目录的 .so 软链接
"${project_root}/scripts/fix_nonstd_lib_symlinks.sh" "${binary_dir}"
```

### 具体插入位置

| 文件 | 插入位置（行号） |
|------|----------------|
| deb `pak_linyaps.sh` | L775 之后（`validate_bin_nesting.sh` 之后） |
| tar `pak_linyaps.sh` | L793 之后（`validate_bin_nesting.sh` 之后） |
| appimage `pak_linyaps.sh` | L634 之后（`validate_bin_nesting.sh` 之后） |

## 关键设计决策

- **相对路径软链**：与参考代码一致，使用 `realpath --relative-to` 保证软链在容器内可解析
- **扫描范围**：`-type f -o -type l` 同时覆盖普通文件和已有软链，完整扫描
- **ELF 过滤**：`file` 命令检测 `ELF.*shared object`，避免非库文件被误处理
- **幂等性**：已存在的正确软链跳过，多次运行安全

## 验证方式

- 运行 `test_pak_linyaps.sh` 确认 deb 版现有测试不受影响
- 手动验证：在一个包含非标准目录 `.so` 的 binary 目录上运行脚本，检查 `lib/` 下是否正确创建了相对路径软链