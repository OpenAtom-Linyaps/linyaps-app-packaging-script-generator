---
name: bin2linyaps.compat-testing
description: >
  自动执行玲珑打包全流程测试：YAML 校验 → 目录结构校验 → pak_linyaps.sh 构建 →
  运行时兼容性检测 → 生成 JSON 报告。接收任务 JSON，对每个 project 执行 5 步测试管线。
user-invocable: false
---

# bin2linyaps.compat-testing

## 功能说明

对已生成的玲珑打包工程执行 5 步自动化测试管线：

1. **YAML 校验** — `validate_linglong_yaml.py` 验证 `linglong.yaml` 语法、必需字段、version 格式
2. **结构校验** — `common-data-verify.py` 验证 desktop/icon 目录结构合规性
3. **构建测试** — 通过 `pak_linyaps.sh` 执行构建，验证输出 `.layer` 文件
4. **兼容性检测** — 优先 CompatChecker Python API，备用 `ll-builder run`
5. **报告合并** — 汇总前 4 步结果，生成每任务 JSON 报告 + 全局统计

## 目录约定

- 编排入口：`skills/bin2linyaps.compat-testing/scripts/run_tasks.sh`
- 前置检测：`skills/bin2linyaps.compat-testing/scripts/validate_projects.sh`
- YAML 校验：`skills/bin2linyaps.compat-testing/scripts/validate_linglong_yaml.py`
- 结构校验：`skills/bin2linyaps.compat-testing/scripts/common-data-verify.py`
- 兼容检测：`skills/bin2linyaps.compat-testing/scripts/demos/compat_checker.py`

## 输入

标准任务 JSON，`tasks[].type` 为 `binary` 或未指定：

```json
{
  "global": {
    "projects_root": "/path/to/projects",
    "output_dir": "./output/${tag}",
    "build_tmp_dir": "./build_cache",
    "src_dir": "./src"
  },
  "tasks": [
    {
      "pkgName": "com.example.app",
      "type": "binary",
      "src_url": "https://example.com/app_1.0_amd64.deb",
      "arch": "x86_64",
      "orig_version": "1.0.0"
    }
  ]
}
```

## 执行流程

### 前置检测（可选）

```bash
bash skills/bin2linyaps.compat-testing/scripts/validate_projects.sh \
  --task-file=<task.json> \
  --output=<output.json>
```

检查项：项目目录存在 → `pak_linyaps.sh` 可执行 → `linglong.yaml` 存在 → desktop ≥ 1 → 图标目录合规

### 全流程测试（5 步管线）

```bash
bash skills/bin2linyaps.compat-testing/scripts/run_tasks.sh <task.json>
```

对每个 task 依次执行：

| 步骤 | 操作 | 脚本/工具 | 产出 |
|------|------|-----------|------|
| 1 | YAML 校验 | `validate_linglong_yaml.py --input linglong.yaml --exec-name ... --json` | `reports/<pkg>/yaml_validation.json` |
| 2 | 结构校验 | `common-data-verify.py templates/files_res --json` | `reports/<pkg>/structure_validation.json` |
| 3 | 构建测试 | `pak_linyaps.sh --linyaps_arch=... --origin_version=... --src_path=...` | `reports/<pkg>/build.log` + `.layer` |
| 4 | 兼容检测 | CompatChecker API / `ll-builder run` | `reports/<pkg>/compat_result.json` |
| 5 | 报告合并 | 汇总前 4 步 JSON | `reports/<pkg>/report.json` + `reports/summary.json` |

### 单步骤独立调用（调试用）

```bash
# YAML 校验
python3 skills/bin2linyaps.compat-testing/scripts/validate_linglong_yaml.py \
  --input <project>/linglong.yaml \
  --exec-name "app %U" \
  --json --output report.json

# 结构校验
python3 skills/bin2linyaps.compat-testing/scripts/common-data-verify.py \
  <project>/templates/files_res \
  --json --output report.json

# 兼容检测
python3 -c "
import sys
sys.path.insert(0, 'skills/bin2linyaps.compat-testing/scripts')
from demos.compat_checker import CompatChecker
from pathlib import Path
checker = CompatChecker(build_dir=Path('<build_dir>'), enable_compat_check=True)
success, message = checker.check()
print(f'Status: {\"passed\" if success else \"failed\"}, Message: {message}')
"
```

## 约束

- 构建入口唯一性：所有构建操作必须通过 `pak_linyaps.sh` 执行，严禁自行调用 `ll-builder` 或修改 `linglong.yaml`
- 只读测试：不修改项目目录中的任何文件
- 版本字段保护：`validate_linglong_yaml.py` 会检查 `package.id`、`package.name`、`package.description` 是否含未解析变量（如 `${package_id}`），若报错说明工程初始化未正确填充
- 架构依赖：task JSON 中的 `arch` 须与 `skills/config/arch_mapping.json` 匹配

## 依赖

- `python3` — 校验脚本运行环境
- `curl` — 源文件下载
- `timeout` — 兼容性检测超时控制
- `ll-builder` — 玲珑构建工具（CompatChecker 备用）
- `dpkg` — Debian 包处理（`pak_linyaps.sh` 内部依赖）

## 输出格式

### 单任务报告 (`reports/<pkg>/report.json`)

```json
{
  "package_id": "com.example.app",
  "test_time": "2026-07-28T10:30:00Z",
  "overall_status": "passed",
  "tests": {
    "yaml_validation": { "step": "yaml_validation", "status": "passed" },
    "structure_validation": { "step": "structure_validation", "status": "passed" },
    "build_test": { "step": "build_test", "status": "passed", "duration_seconds": 45, "output_layer": "output/com.example.app-binary.layer" },
    "compat_check": { "step": "compat_check", "status": "passed", "exit_code": 124 }
  },
  "errors": [],
  "warnings": []
}
```

### 构建元数据 (`reports/<pkg>/build_meta.json`)

步骤 3（构建测试）完成后自动生成，供 `bin2linyaps.external-missing-deps-fetch` 上游流程使用：

```json
{
  "build_tmp_dir": "/path/to/build_cache/CI_ll_com.example.app",
  "project_dir": "/path/to/projects/CI_ll_com.example.app",
  "missing_deps_json": "/path/to/build_cache/CI_ll_com.example.app/missing_deps.json",
  "missing_deps_csv": null
}
```

字段说明：
- `build_tmp_dir`：`pak_linyaps.sh` 实际使用的构建临时目录（`ll-builder build` 执行位置）
- `project_dir`：玲珑工程目录
- `missing_deps_json`：若构建生成了 `missing_deps.json`，则为该文件路径；否则为 `null`
- `missing_deps_csv`：若构建生成了 `missing_deps.csv`，则为该文件路径；否则为 `null`

此文件是 `bin2linyaps.external-missing-deps-fetch` 的输入依据：`fetch_missing_deps.sh` 通过 `--build-tmp-dir` 从 `build_tmp_dir` 读取 `missing_deps.*`，并将修复写入 `templates/linglong.yaml`。

### 汇总报告 (`reports/summary.json`)

```json
{
  "test_time": "2026-07-28T10:30:00Z",
  "total": 5,
  "passed": 4,
  "failed": 1,
  "results": [
    { "pkgName": "com.example.app", "status": "passed" },
    { "pkgName": "com.failed.app", "status": "failed" }
  ]
}
```

## 测试失败处理

| 失败类型 | 处理方式 |
|---------|---------|
| YAML 格式错误 | 调用 `bin2linyaps.fix` skill 修复 |
| 资源结构问题 | 调用 `bin2linyaps.fix` skill 修复 |
| 构建失败 | 分析 `build.log`，提示用户检查 |
| 兼容性失败 | 保存错误日志，调用 `bin2linyaps.fix` skill |

## 返回码

- `0` — 全部任务通过
- `1` — 存在失败任务
