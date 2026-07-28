# `bin2linyaps.compat-testing` 重构方案

> 基于 `examples/linyaps-packaging-scripts-running-skill-v2026.7.9.1` 的 binary runner 模式

---

## 1. 问题分析

### 现状：`skills/bin2linyaps.compat-testing/`

```
skills/bin2linyaps.compat-testing/
├── SKILL.md                    ← 纯描述性文档，内含手动执行代码片段
└── scripts/
    ├── validate_linglong_yaml.py   ← ✅ 保留（YAML 校验）
    ├── common-data-verify.py       ← ✅ 保留（目录结构校验）
    └── demos/
        └── compat_checker.py       ← ✅ 保留（运行时兼容检测）
```

**致命缺陷：**
- **无 `run_tasks.sh`** — 没有任何脚本可以接收 task JSON、自动编排 5 步测试管线
- **无 `validate_projects.sh`** — 没有构建前预检机制
- **SKILL.md 是静态指令** — 仅告诉 LLM 手动逐条执行命令，无法被程序化触发
- **不与现有基础设施集成** — 不引用 `agent-config.json`、`arch_mapping.json`、`extract_version.sh`

### 参考：`examples/linyaps-packaging-scripts-running-skill-v2026.7.9.1/` 的 binary 模式

```
skills/linglong-binary-runner/
├── SKILL.md                    ← 明确输入格式 + 执行流程 + 约束
└── scripts/
    ├── run_tasks.sh             ← 核心编排：解析 JSON → 版本提取 → 架构验证 → 下载 → 打包
    └── validate_projects.sh     ← 前置检测：检查 pak_linyaps.sh 完整性
scripts/common.sh                ← 共享库：parse_json、log、download、arch_validate
skills/config/arch_mapping.json  ← 架构映射表
agent-config.json                ← 全局配置
```

**关键差异：** compat-testing 需要在 binary runner 的基础上**扩展**为 5 步测试管线（YAML 校验 → 结构校验 → 构建 → 兼容性检测 → 报告），而非只做构建。

### Agent 端问题

`agents/deb-linglong-packer.agent.md` 中 3 处 Step 5/Step 3 被引用为**手动步骤列表**，而非自动化脚本调用，导致：
- LLM 需要自行记住并执行 5 个步骤
- 步骤间无错误传播和状态管理
- 无统一报告输出格式

---

## 2. 修改范围

### 2.1 Skill 端（3 个文件）

| # | 文件 | 操作 | 说明 |
|---|------|------|------|
| 1 | `skills/bin2linyaps.compat-testing/SKILL.md` | **重写** | 参考 binary runner，定义 task JSON 输入和 5 步编排 |
| 2 | `skills/bin2linyaps.compat-testing/scripts/run_tasks.sh` | **新建** | 核心编排脚本 |
| 3 | `skills/bin2linyaps.compat-testing/scripts/validate_projects.sh` | **新建** | 前置检测脚本 |

### 2.2 Agent 端（1 个文件，6 处修改）

| # | 位置 | 修改内容 |
|---|------|---------|
| 1 | Skills 表（line 204） | 核心脚本列更新为 `run_tasks.sh`、`validate_projects.sh` |
| 2 | deb Step 5（lines 423-430） | 手动步骤 → 自动化调用 `run_tasks.sh` |
| 3 | tar Step 3（lines 483-490） | 同上 |
| 4 | AppImage Step 3（lines 537-544） | 同上 |
| 5 | 工具调用示例·common-data-verify（lines 676-679） | 替换为 `run_tasks.sh` 示例 |
| 6 | 工具调用示例·validate_linglong_yaml + compat_checker（lines 681-694） | 整合为"单步骤独立调用（调试用）" |

### 2.3 不修改的文件

| 文件 | 原因 |
|------|------|
| `scripts/validate_linglong_yaml.py` | 现有逻辑正确，步骤 1 直接复用 |
| `scripts/common-data-verify.py` | 现有逻辑正确，步骤 2 直接复用 |
| `scripts/demos/compat_checker.py` | 现有逻辑正确，步骤 4 直接复用 |

---

## 3. 详细设计方案

### 3.1 `SKILL.md` 新结构

```yaml
---
name: bin2linyaps.compat-testing
description: >
  自动执行玲珑打包全流程测试：YAML 校验 → 目录结构校验 → pak_linyaps.sh 构建 →
  运行时兼容性检测 → 生成 JSON 报告。接收任务 JSON，对每个 project 执行 5 步测试管线。
user-invocable: false
---
```

**章节：**
1. **功能说明** — 5 步测试管线概述
2. **输入格式** — task JSON schema（含 `global.*` 和 `tasks[].{pkgName, src_url, arch, orig_version}`）
3. **执行流程** — 每步详述（含调用的脚本/工具、参数、预期输出）
4. **约束** — 必须通过 `pak_linyaps.sh` 构建，禁止自行调用 `ll-builder`，只读不修改
5. **依赖** — `ll-builder`、`python3`、`timeout`、`curl`、`dpkg`
6. **输出格式** — 单任务报告 JSON schema（per-step pass/fail/timing）

### 3.2 `scripts/run_tasks.sh` 设计

```
#!/bin/bash
# 用法: bash run_tasks.sh <task.json>
# 依赖: agent-config.json, skills/config/arch_mapping.json, scripts/extract_version.sh

流程:
  1. 解析 task JSON → 提取 global 配置 + tasks 列表
     - 从 agent-config.json 读取 fallback 配置
     - 解析 ${tag} 占位符为实际日期

  2. 初始化目录: src_dir, output_dir, build_tmp_dir, reports_dir

  3. 对每个 task 循环:
     a. 版本提取（若 orig_version 为空 → extract_version.sh + agent-config.json rules）
     b. 架构验证（arch_mapping.json: token 扫描 + 正则匹配）
     c. 下载源文件（curl -L, 支持重定向, 跳过已存在）
     d. 查找项目目录（CI_ll_<pkgName> → <pkgName> → 模糊匹配）
     e. 检测 --build_tmp_dir 支持

     f. Step 1: validate_linglong_yaml.py
        - --input <project_dir>/linglong.yaml
        - --exec-name (从 desktop 提取)
        - --json --output <reports_dir>/<pkgName>/yaml_validation.json

     g. Step 2: common-data-verify.py
        - <project_dir>/templates/files_res
        - --json --output <reports_dir>/<pkgName>/structure_validation.json

     h. Step 3: pak_linyaps.sh（构建测试）
        - cd <project_dir> && ./pak_linyaps.sh \
            --linyaps_arch=<arch> \
            --origin_version=<version> \
            --src_path=<downloaded_file> \
            --output_dir=<output_dir> \
            [--build_tmp_dir=<build_tmp_dir>/<pkgName>]
        - 日志: <reports_dir>/<pkgName>/build.log
        - 成功标志: output_dir 中存在 *.layer 文件

     i. Step 4: 兼容性检测
        - 优先: CompatChecker（Python API）
        - 备用: timeout <N> ll-builder run
        - 结果: <reports_dir>/<pkgName>/compat_result.json

     j. Step 5: 合并报告
        - 汇总 4 个步骤的通过/失败/耗时
        - 写入 <reports_dir>/<pkgName>/report.json

  4. 输出最终统计（stdout + reports_dir/summary.json）

返回码: 0=全部通过, 1=存在失败
```

### 3.3 `scripts/validate_projects.sh` 设计

```
#!/bin/bash
# 用法: validate_projects.sh --task-file=<task.json> [--output=<result.json>]

对每个 pkgName:
  ✅ 项目目录存在（CI_ll_<pkgName> → <pkgName> → 模糊匹配）
  ✅ pak_linyaps.sh 存在且可执行
  ✅ linglong.yaml 存在
  ✅ templates/files_res/share/applications/*.desktop ≥ 1
  ✅ templates/files_res/share/icons/hicolor/ 结构合规

输出 JSON:
  {
    "validated_at": "...",
    "summary": { "total": N, "passed": M, "failed": K },
    "results": [
      { "pkgName": "...", "status": "PASS|FAIL|NOT_FOUND", "checks": {...} }
    ]
  }

返回码: 0=全部通过, 1=存在失败
```

### 3.4 Agent 端修改

#### Skills 表（line 204）

```
# 旧
| bin2linyaps.compat-testing | ... | `scripts/common-data-verify.py`, `scripts/validate_linglong_yaml.py` | `scripts/demos/compat_checker.py` |

# 新
| bin2linyaps.compat-testing | ... | `scripts/run_tasks.sh`（编排入口）, `scripts/validate_projects.sh`（前置检测） | `scripts/validate_linglong_yaml.py`, `scripts/common-data-verify.py`, `scripts/demos/compat_checker.py` |
```

#### Step 5/Step 3（三处统一替换）

```
# 旧
调用 `bin2linyaps.compat-testing` skill：
- 验证 linglong.yaml 格式
- **验证 package.id/name/description 不为空且不含未解析变量**
- 验证资源目录结构
- 执行打包测试
- 运行兼容性检测
- **输出**: 测试报告

# 新
调用 `bin2linyaps.compat-testing` skill 自动化执行：

1. **构造子任务 JSON**（从 agent-config 和当前项目信息组装）

2. **前置检测**（可选）：
   bash skills/bin2linyaps.compat-testing/scripts/validate_projects.sh \
     --task-file=<subtask.json>

3. **执行全流程测试**：
   bash skills/bin2linyaps.compat-testing/scripts/run_tasks.sh <subtask.json>

4. **读取报告**：解析各任务的 report.json
   - 全部 passed → 兼容性测试通过
   - 存在 failed → 调用 bin2linyaps.fix
   - **输出**: 测试报告（汇总 + 分步骤详情）
```

#### 工具调用示例（lines 676-694）

```
# 旧
### 调用common-data-verify ... dpkg-deb ...
### 调用validate_linglong_yaml ...
### 调用compat_checker ...
### 执行打包脚本（deb 版）...

# 新
### 执行兼容性全流程测试（推荐）
### 前置检测
### 单步骤独立调用（调试用）
```

---

## 4. 关键设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 共享库策略 | **不创建全局 `scripts/common.sh`** | compat-testing 自包含，直接引用 `agent-config.json`、`arch_mapping.json`、`extract_version.sh` |
| 现有 Python 脚本 | **不修改，直接调用** | 功能完善，已在 agent.md 中作为工具示例使用 |
| task JSON 格式 | **与参考示例对齐** | 确保与 `linyaps-packaging-runner` agent 格式兼容 |
| 报告粒度 | **分步骤独立记录** | 每个步骤有独立 JSON，方便 `bin2linyaps.fix` 定位问题 |
| 构建入口 | **仅通过 `pak_linyaps.sh`** | 与 binary runner 约束一致，禁止自行调用 `ll-builder` |
| 兼容性检测 | **优先 CompatChecker，备用 `ll-builder run`** | Python API 更可控，`timeout` 命令作为 fallback |

---

## 5. 执行顺序

```
Step 1: 新建 scripts/run_tasks.sh        ← 核心，最复杂
Step 2: 新建 scripts/validate_projects.sh ← 相对简单
Step 3: 重写 SKILL.md                    ← 与 run_tasks.sh 对齐
Step 4: 修改 agents/deb-linglong-packer.agent.md（6 处） ← 联调
```

---

## 6. 验证方式

1. **单元测试**：`tests/test_pak_linyaps.sh` 验证 `pak_linyaps.sh` 参数解析（已有）
2. **前置检测测试**：对已知项目目录运行 `validate_projects.sh`，验证预期通过/失败
3. **全流程测试**：对已知项目运行 `run_tasks.sh <task.json>`，验证 5 步均通过
4. **失败注入测试**：提供有问题的 `linglong.yaml`，验证步骤 1 正确报告失败
