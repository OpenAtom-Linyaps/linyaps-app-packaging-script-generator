---
name: bin2linyaps.deb.project-gen
description: >
  根据deb包信息和CSV配置，生成完整的玲珑打包工程，包括 linglong.yaml 配置文件和 pak_linyaps.sh 打包脚本。
user-invocable: false
---

# 玲珑工程生成

## 功能说明

根据deb包信息和CSV配置，生成完整的玲珑打包工程，包括 `linglong.yaml` 配置文件和 `pak_linyaps.sh` 打包脚本。

> **约束**：本 skill 遵循 `bin2linyaps.constraints` SKILL（wrapper/command 契约、`${ll_version}` 版本契约、package_id 契约、base/runtime 白名单、依赖核验、模板完整性）。以下只保留本 skill 特有内容，不重复展开通用约束。

## 触发场景

- 需要为deb包创建玲珑打包工程
- 需要生成linglong.yaml配置文件
- 需要生成自动化打包脚本
- 批量创建多个应用的打包工程

## 批量初始化

使用 `batch_init.sh` 脚本可以批量创建多个应用的打包工程：

```bash
./scripts/batch_init.sh tasks.csv --projects_root=./projects      # CSV 批量初始化
./scripts/batch_init.sh task.json --projects_root=./projects      # JSON 批量初始化
./scripts/batch_init.sh tasks.csv --dry-run                       # 仅生成项目结构，不执行打包
```

**CSV 格式示例**：
```csv
包名,架构,版本,下载地址
com.example.app,x86_64,1.0.0,https://example.com/app.deb
```

**JSON 格式示例**：
```json
{
  "global": { "projects_root": "./projects" },
  "tasks": [
    { "pkgName": "com.example.app", "arch": "x86_64", "orig_version": "1.0.0", "src_url": "https://example.com/app.deb" }
  ]
}
```

批量初始化会为每个任务创建 `CI_ll_<pkgName>` 目录，包含：`linglong.yaml`、`pak_linyaps.sh`、`scripts/`、`config/`（含白名单）、`templates/files_res/`（空骨架）。

> **上下文效率**：生成工程后 agent **禁止整卷 read `CI_ll_<package_id>/` 全树**。只读 `linglong.yaml` + `scripts/` 目录 listing；`pak_linyaps.sh`（1127 行模板正文）只在构建时由脚本自身执行，init 阶段不进入 agent 上下文，仅 `grep '^ll_id=\|^binary_name='` 确认注入正确。

## 工作流程

### 1. 准备工程目录

工程目录命名规范：`CI_ll_<package_id>`（package_id 反向域名格式，必须非空）。

```bash
project_dir="CI_ll_${package_id}"
mkdir -p "${project_dir}/templates/files_res" "${project_dir}/scripts" "${project_dir}/config"

# 拷贝辅助脚本（handle_special_paths.sh 为 paths + libfix 双模式综合脚本）
cp "scripts/handle_special_paths.sh" "${project_dir}/scripts/" && chmod +x "${project_dir}/scripts/handle_special_paths.sh"
cp "scripts/dedup_desktop_files.sh" "${project_dir}/scripts/" && chmod +x "${project_dir}/scripts/dedup_desktop_files.sh"
cp "scripts/validate_bin_nesting.sh" "${project_dir}/scripts/" && chmod +x "${project_dir}/scripts/validate_bin_nesting.sh"
cp "scripts/download_missing_deps.sh" "${project_dir}/scripts/" && chmod +x "${project_dir}/scripts/download_missing_deps.sh"
# 存量部署提示：download_missing_deps.sh 是静态快照，随初始化复制进工程 scripts/。
# 若工程在本 skill 修复 usr/ 平铺（不再产生 binary_dir/usr/…）之前初始化，
# 其 scripts/ 内仍是旧脚本；需重新执行上面这条 cp 刷新，否则依赖的 bin/lib 仍会落到 /usr/usr/…。
if [ -f "scripts/analyze_entry_script.sh" ]; then
  cp "scripts/analyze_entry_script.sh" "${project_dir}/scripts/" && chmod +x "${project_dir}/scripts/analyze_entry_script.sh"
fi

# 拷贝白名单配置（本 skill 自带的 config/ 自包含副本）
cp "${skill_root}/config/base_runtime_whitelist.conf" "${project_dir}/config/"
# 注意：不创建 src/ 目录，deb文件路径由用户执行脚本时指定
```

**验证 package_id**：

```bash
"skills/bin2linyaps.fix/scripts/validate_package_id.sh" "${project_dir}"
"skills/bin2linyaps.fix/scripts/fix_package_id.sh" "${project_dir}" --new-id "${package_id}"   # 验证失败时
```

**package_id 格式规范**：反向域名格式（`com.example.app`），小写字母/数字/下划线/点，至少两个点分隔部分，最大 255 字符。

**deb 文件存储路径**：`<package_id>/xxx.deb`（工程内不含 deb，路径由用户执行时指定）。

### 2. 生成 linglong.yaml

基于 `templates/` 目录下的模板生成，使用 envsubst 变量替换：

- `templates/linglong.yaml`（`version: "${ll_version}"`、`package.version: ${ll_version}`、`command:` 空占位符、`base:""`/`runtime:""` 空占位符）
- `templates/files_res/`（空骨架，由 agent 按 `reference/files_res_structure.md` 填充）

```yaml
# templates/linglong.yaml 关键字段约定
version: "${ll_version}"
package:
  id: ${ll_id}          # 保留 ${ll_id} 变量，由 pak_linyaps.sh envsubst 替换
  name: "${app_name}"
  version: ${ll_version}
  kind: app
  architecture: ${ll_architecture}
  description: |
    ${description}
base: ""                 # 空占位符，由 build_pak() 通过 sed 延迟注入
runtime: ""              # 空占位符，由 build_pak() 通过 sed 延迟注入
buildext:
  apt:
    depends:
      - ${depends}
command:
  - "${command}"         # 空占位符，由 wrapper 机制动态设置
build: |
  cp -rf /project/binary/* ${prefix}/
  cp -rf /project/files_res/* ${prefix}/
  touch ${prefix}/.linyaps_genius
```

### 2.5. 验证 base/runtime 白名单（重要，阻止级别）

**在生成 pak_linyaps.sh 之前必须验证 base/runtime 组合**。不在白名单中的组合将阻止任务（exit 1）。

**白名单查找优先级（skill 自帶 config/ 自包含副本，全局為參考）**：
1. CLI `--whitelist` 指定的路径
2. 环境变量 `LINGLONG_WHITELIST_FILE`
3. 工程目录 `config/base_runtime_whitelist.conf`（由本 skill 从自带副本同步）
4. **本 skill 自带 `config/base_runtime_whitelist.conf`（自包含，`${skill_root}/config/`）** ⭐
5. 全局 `skills/config/base_runtime_whitelist.conf`（参考副本）

```bash
whitelist_file=""
if [ -n "${whitelist_file}" ] && [ -f "${whitelist_file}" ]; then
  : # 已指定
elif [ -n "${LINGLONG_WHITELIST_FILE}" ] && [ -f "${LINGLONG_WHITELIST_FILE}" ]; then
  whitelist_file="${LINGLONG_WHITELIST_FILE}"
elif [ -f "${project_dir}/config/base_runtime_whitelist.conf" ]; then
  whitelist_file="${project_dir}/config/base_runtime_whitelist.conf"
elif [ -f "${skill_root}/config/base_runtime_whitelist.conf" ]; then
  whitelist_file="${skill_root}/config/base_runtime_whitelist.conf"
fi

if [ -z "${whitelist_file}" ]; then
  echo "警告: 未找到白名單配置，跳過驗證" >&2
else
  found=0
  while IFS= read -r line; do
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
    read -r wl_base wl_runtime _ <<<"${line}"
    if [ "${wl_base}" = "${base_id}/${base_version}" ] && [ "${wl_runtime}" = "${runtime_id}/${runtime_version}" ]; then
      found=1; break
    fi
  done < "${whitelist_file}"
  if [ "${found}" -eq 0 ]; then
    echo "錯誤: base/runtime 組合不在白名單中，任務被阻止！" >&2
    echo "  當前組合: ${base_id}/${base_version} + ${runtime_id}/${runtime_version}" >&2
    echo "  请先在本 skill 白名单中添加（配置：${skill_root}/config/base_runtime_whitelist.conf）" >&2
    exit 1
  fi
  echo "白名單驗證通過: ${base_id}/${base_version} + ${runtime_id}/${runtime_version}"
fi
```

**白名单文件格式**：`<base_id>/<base_version> <runtime_id>/<runtime_version> <描述>`（runtime_id 可为 `-` 表示无需 runtime）。

**当前合规组合**：

| base | runtime | 适用场景 |
|------|---------|---------|
| `org.deepin.base/25.2.2` | `org.deepin.runtime.dtk/25.2.2` | Qt6/DTK6 应用（推荐默认） |
| `org.deepin.base/25.2.2` | `org.deepin.runtime.webengine/25.2.2` | Qt6 WebEngine 应用 |
| `org.deepin.base/23.1.0` | `org.deepin.runtime.dtk/23.1.0` | Qt5/DTK5 应用 |
| `org.deepin.base/25.2.2` | `-` | 纯 base 应用（无 runtime） |
| `org.deepin.base/23.1.0` | `-` | 纯 base 应用（无 runtime，23.1.0） |

**推荐维护本 skill 白名单**（`${skill_root}/config/base_runtime_whitelist.conf`，skill 自包含副本；同步更新全局 `skills/config/` 参考副本），生成时自动同步到工程目录。

### 3. 生成 pak_linyaps.sh

从 `templates/pak_linyaps.sh` **完整复制**（不得手写、简化或删除任何函数/脚本调用），生成后必须写入 `ll_id`：

```bash
cp "${skill_root}/templates/pak_linyaps.sh" "${project_dir}/"
chmod +x "${project_dir}/pak_linyaps.sh"

# 关键：将 ll_id="" 替换为实际包名（新版本通过该变量 envsubst 生成 id）
sed -i 's/^[[:space:]]*ll_id=""/ll_id="'"${package_id}"'"/' "${project_dir}/pak_linyaps.sh"

# 写入 binary_name（仅当 CSV/配置已提供非空值时），空值保持模板默认 ""
if [ -n "${binary_name}" ]; then
  sed -i 's|^[[:space:]]*binary_name=""|binary_name="'"${binary_name}"'"|' "${project_dir}/pak_linyaps.sh"
fi
```

**重要**：
- `ll_id` 由 `--package_id`（主入口）/ `--ll_id`（覆盖）统一管理，`init_global_data()` 缺省回退 `ll_id="${package_id}"`；生成的 `pak_linyaps.sh` 中 `ll_id` **必须非空**。
- `templates/linglong.yaml` 的 `package.id` 必须保留为 `${ll_id}` **变量**（不得硬编码），由 `pak_linyaps.sh` 构建时 envsubst 替换。
- `binary_name` 在 `init_global_data()` 内唯一声明，支持 `--binary_name=<name>` 运行时覆盖；空值时 `build_pak()` 自动从 desktop Exec 提取兜底。**禁止**在脚本顶部另插 `binary_name=...`（会造成双重声明、默认值覆盖失效）。

脚本签名参考 `templates/pak_linyaps.sh`（函数：`init_global_data` / `validate_version_format` / `generate_version_from_origin` / `build_dir_init` / `build_pak` / `main`；`build_pak` 依次调用 `handle_special_paths.sh --phase=paths`、`dedup_desktop_files.sh`、`validate_bin_nesting.sh`、`handle_special_paths.sh --phase=libfix`、wrapper 创建与 sed 更新 command，最后 `ll-builder build/export`）。

### 4. CSV 配置填充

从 CSV 读取配置并填充模板（`package_name`、`deb_path`、`architecture`、`base`、`runtime`、`push`），CSV 值优先于自动检测值。

## 模板变量说明

| 变量 | 来源 | 说明 |
|-----|------|------|
| `${package_id}` | deb包名转换 | 玲珑包ID，如 com.visualstudio.code |
| `${ll_id}` | package_id | 玲珑包ID（生成时注入 pak_linyaps.sh），envsubst 替换 package.id |
| `${app_name}` | deb Description | 应用名称 |
| `${ll_architecture}` | 架构映射 | x86_64/aarch64 |
| `${ll_version}` | 版本转换 | 玲珑格式版本 (x.x.x.x)，由 `convert_version_to_linglong()` 归一化 |
| `${base}` / `${runtime}` | — | 已废弃，模板用空占位符，由 build_pak() 通过 sed 延迟注入 |
| `${push}` | CSV配置 | 是否自动推送 |
| `${command}` | desktop Exec | 启动命令（⚠️ 占位符，由 wrapper 机制动态设置） |
| `${depends}` | deb Depends | 运行时依赖（需通过 apt-cache show 核验） |
| `${binary_name}` | CSV配置 | 二进制文件名（如 `utools`），用于创建 wrapper 脚本 |

**binary_path 最佳实践**：`binary_path` 已废弃，新版本自动保持 deb 原有目录结构（`/opt/uTools/` → `files/opt/uTools/`）；二进制软链自动创建在 `files/bin/`。

## 命令行参数说明

| 参数 | 必填 | 说明 |
|-----|------|------|
| `--src_path` | 是 | deb包完整路径 |
| `--output_dir` | 是 | 输出目录 |
| `--package_id` | 二选一 | 玲珑包 ID（反向域名格式），ll_id 的主要入口 |
| `--ll_id` | 二选一 | 玲珑包 ID，可覆盖 `--package_id` |
| `--ll_version` | 二选一 | 玲珑格式版本 (x.x.x.x) |
| `--origin_version` | 二选一 | 原始版本号（自动转换为玲珑格式） |
| `--linyaps_arch` | 否 | 目标架构 (x86_64/arm64)，默认当前系统架构 |
| `--build_tmp_dir` | 否 | 构建缓存目录，未指定时使用临时目录 |
| `--base_id` / `--base_version` | 否 | 基础运行时 ID/版本，默认白名单推荐组合 |
| `--runtime_id` / `--runtime_version` | 否 | 应用运行时 ID/版本；`--runtime_id=` 或 `--runtime_id=-` 禁用 runtime（纯 base 应用，删除 runtime 字段） |
| `--whitelist` | 否 | 白名单配置文件路径，未指定时按优先级自动查找 |
| `--build_extra_args` | 否 | 额外构建参数，追加到 `ll-builder build`（默认 `--skip-output-check`） |
| `--nested_script` | 否 | 嵌套脚本文件名（仅填文件名，路径自动拼接为 `${project_root}/<文件名>`），空值关闭 |

## Wrapper 机制说明

`pak_linyaps.sh` 在构建时自动创建 wrapper 脚本，确保应用正确启动：

1. 从 desktop 文件 Exec 字段自动提取 `binary_name`
2. 在 `binary/` 目录查找实际可执行文件
3. 在 `bin/` 目录创建 `${binary_name}.wrapper` 脚本
4. 自动将 `linglong.yaml` 的 `command` 字段更新为 wrapper 路径
5. 自动将 desktop 文件的 `Exec=` 字段更新为 wrapper 路径

**为什么需要 Wrapper**：解决 `dirname $0` 路径解析问题（软链会导致解析错误），通过 `cd + pwd` 解析绝对路径，自动化处理无需手动修改。

## 嵌套脚本支持（Nested Script）

某些应用需要从 wrapper 再调用一个用户提供的嵌套 bash 脚本（脚本内用 `${wrapper}` 代指 wrapper），形成 `command/desktop → 嵌套脚本 → wrapper → 实际二进制` 启动链。

- 嵌套脚本放置于工程根目录（与 `pak_linyaps.sh` 同级），开启开关：
  ```bash
  ./pak_linyaps.sh ... --nested_script=my_launcher.sh
  ```
- **回退策略**：脚本文件不存在 / 脚本内未找到 `${wrapper}` → 告警并回退到原 wrapper。开关未指定时行为不变。

## 输出目录结构

```
CI_ll_<package_id>/
├── pak_linyaps.sh              # 打包脚本
├── config/
│   └── base_runtime_whitelist.conf  # base/runtime 白名单（优先从全局 skills/config/ 拷贝）
├── scripts/
│   └── handle_special_paths.sh # 特殊路径处理（paths + libfix 双模式）
└── templates/
    ├── linglong.yaml           # 玲珑配置模板
    └── files_res/              # 资源文件骨架（由 agent 填充）
        └── share/
            ├── applications/
            ├── icons/hicolor/
            ├── mime/packages/
            └── pixmaps/
```

**注意**：工程初始化时不包含任何源文件（deb 路径由用户 `--src_path` 指定）；`templates/files_res/` 为空骨架，依 `reference/files_res_structure.md` 填充。

## 二进制软链处理

- `files/` 映射到容器内 `/usr/`；`files/bin/` → `/usr/bin/`（可执行软链），`files/share/` → `/usr/share/`，`files/lib/` → `/usr/lib/`
- deb 中非标准路径（如 `/opt/uTools/`）直接放到 `files/` 根目录下作为未归类目录
- 软链使用**相对路径**（如 `../uTools/utools`），确保容器内正确解析

```
deb 结构                    binary/ 结构              files/ 结构 (容器内 /usr/)
/opt/uTools/utools    →    uTools/utools       →    /usr/uTools/utools
/usr/bin/code         →    bin/code            →    /usr/bin/code
/usr/share/code/      →    share/code/         →    /usr/share/code/
```

## 生成后验证步骤（必做）

```bash
# 1. 验证 pak_linyaps.sh 中的 base/runtime 配置（--fix 自动修复）
"${skill_root}/scripts/validate_pak_script.sh" "${project_dir}"
"${skill_root}/scripts/validate_pak_script.sh" "${project_dir}" --fix

# 2. 验证 linglong.yaml 格式（含 base/runtime 格式）
#    注：version 被绝对化 / base/runtime 非法格式时报错会输出可执行的 sed 修复命令
"${skill_root}/../bin2linyaps.compat-testing/scripts/validate_linglong_yaml.py" \
  --input "${project_dir}/templates/linglong.yaml" \
  --exec-name "${binary_name}"
```

**自检清单（生成后确认）**：
- [ ] 脚本调用完整（`handle_special_paths.sh --phase=paths` + `--phase=libfix`、`dedup_desktop_files.sh`、`validate_bin_nesting.sh`）
- [ ] `build_dir_init()` 中**无** `export command=` 行（command 由 wrapper 机制 sed 设置）
- [ ] `build_dir_init()` 中**无** `export base_id=` / `export base=` 行（base/runtime 由 sed 延迟注入）
- [ ] 模板路径使用 `${project_root}/templates/linglong.yaml`、`${project_root}/templates/files_res`
- [ ] `base_id`/`runtime_id` 等使用默认值（`DEFAULT_*`）+ CLI 覆盖，**无** `base_id="${base_id}"` 自引用
- [ ] `validate_base_runtime_whitelist()` 已定义并调用；白名单文件已复制到工程 `config/`
- [ ] version 保持 `${ll_version}`（未绝对化）

## 特殊格式路径处理

- deb 解压后可能存在不符合 Linux 规范的路径（空格、括号、&、@、#、$、中文等）
- `pak_linyaps.sh` 使用 `find` + `IFS= read -r` 组合正确处理特殊字符路径，所有路径变量用双引号保护
- 验证：`./scripts/test_special_paths.sh`（`/tmp/test --keep` 保留调试目录），详见 `scripts/README_test_special_paths.md`

## 注意事项

1. 工程目录命名必须遵循 `CI_ll_<package_id>` 格式
2. `linglong.yaml` 中的变量使用 `${var}` 格式，由 `envsubst` 替换
3. `pak_linyaps.sh` 需要可执行权限（`chmod +x`）
4. 多架构支持通过 `--linyaps_arch` 参数指定
5. base/runtime 从 CSV 配置读取，支持不同架构使用不同版本
6. **deb文件路径由用户执行时指定，不存储在工程目录内**
7. **二进制命令使用相对路径，由 `pak_linyaps.sh` 处理软链**
8. 构建缓存目录可通过 `--build_tmp_dir` 指定，未指定时用系统临时目录；自定义目录不存在会自动创建
9. **files/ 映射到 /usr/**：非标准路径（如 `/opt/`）内容直接放到 `files/` 根目录
10. 通用构建约束见 `bin2linyaps.constraints` SKILL（wrapper/command、`${ll_version}`、package_id、base/runtime 白名单、依赖核验、模板完整性）
