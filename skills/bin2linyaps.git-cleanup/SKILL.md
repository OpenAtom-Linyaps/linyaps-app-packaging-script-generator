---
name: bin2linyaps.git-cleanup
description: >
  提交玲珑打包工程到 git 仓库前清理构建缓存（linglong/、bins/、reports/、
  *.layer、*.uab、下载包等），并提供 pre-commit 守卫，阻止缓存被误提交。
user-invocable: false
---

# 玲珑工程提交前缓存清理

## 功能说明

在任何 git commit/push 之前清理 `CI_ll_*` 工程目录内的构建缓存与下载产物，
避免 `*.layer`、`linglong/`、`bins/`、`reports/`、`.linyaps-locks/` 等
缓存被意外推送到仓库。脚本仅作用于显式指定的具体目录，不按项目名扫描。

## 触发场景

- 提交工程到 git 仓库之前
- 需要清理单个 CI_ll 工程目录的构建缓存

## 使用方式

清理指定工程目录的缓存（直接传具体目录路径）：

```bash
"${skill_root}/scripts/clean_project_cache.sh" <project_dir>
```

预览将删除的内容（不实际删除）：

```bash
"${skill_root}/scripts/clean_project_cache.sh" <project_dir> --dry-run
```

提交前守卫（阻断含缓存的暂存变更）：

```bash
"${skill_root}/scripts/pre-commit-guard.sh" <project_dir>
```

- `<project_dir>` 必须为具体目录路径，例如
  `./projects/CI_ll_com.example.app`；仅允许指定目录，不提供
  `--all` / 项目名扫描等模式。

## 清理内容

在指定的 `<project_dir>` 内删除：

- 核心构建缓存：`linglong/`、`bins/`、`reports/`、`build_cache/`、
  `file_res/`、`*.layer`、`*.uab`
- 下载产物：`*.deb`、`*.tar.gz|bz2|xz|zst`、`*.tgz`、`*.zip`
  - `src/`、`source/` 仅在确认为下载/解压缓存时删除（以该层级存在
    真正的工程源文件判断，绝不删除真实源码）

保留：`linglong.yaml`、`pak_linyaps.sh`、`config/`、`scripts/`、`templates/`。

## pre-commit 守卫

`pre-commit-guard.sh` 在 `git add .` 后检查指定目录暂存列表，命中以下
模式即退出码 1（阻断提交）：

- `*.layer`、`*.uab`
- `/linglong/`、`/bins/`、`/reports/`、`/build_cache/`、`.linyaps-locks/`

可用 `--ignore-patterns=<regex>` 覆盖默认模式。

## 兜底检查（Fallback，由 LLM 执行）

确定性脚本无法覆盖全部场景（未知格式、新产生的缓存类型、脚本误留物等），
因此提交前追加一步由 LLM 判断的兜底扫描。请按以下步骤执行：

1. 用 `du` 扫描当前 session 对应的工程目录，定位可疑的大文件 / 大目录：
   ```bash
   # 各一级子目录体积（大到小）
   du -h --max-depth=1 <project_dir> | sort -h
   # 大文件（含深层，仅统计普通文件）
   find <project_dir> -type f -size +50M -exec du -h {} + | sort -h
   ```
2. 依据扫描结果识别可疑项，可疑特征包括：
   - 体积异常的缓存目录：`linglong/`、`bins/`、`reports/`、`build_cache/`、
     `file_res/`、`src/`、`source/`（未被 git 跟踪时的下载/解压物）
   - 大体积归档/产物：`*.layer`、`*.uab`、`*.deb`、`*.tar.*`、`*.tgz`、
     `*.zip`，以及任何体积 >100M 且不属于必要源文件的文件
   - 未被 `.gitignore` / `clean_project_cache.sh` 覆盖的新增缓存类型
3. 由 LLM 判断并执行：对确认的可疑项调用
   `clean_project_cache.sh <project_dir>`；对脚本未覆盖的新增缓存，直接
   `rm -rf` 前先在目录内确认它不是源码/必要文件，并可通过
   `git ls-files --error-unmatch -- <path>` 确认是否被 git 跟踪（已跟踪则绝不删除）。
4. 兜底清理后再次运行 `pre-commit-guard.sh <project_dir>` 确认无残留缓存暂存。

## 注意事项

1. 本 skill 只接受具体目录路径参数，拒绝 `--all` / 项目名匹配
2. 提交前必须先执行 `clean_project_cache.sh`，再执行 `pre-commit-guard.sh`
3. 脚本幂等：多次运行结果一致，不影响已提交的真实源文件
4. 兜底扫描由 LLM 判断：删除前必须确认对象未被 git 跟踪且非必要源码
