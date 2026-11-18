# dispatch 随机 tie-break 优化

## Context

`linyaps-binary-init-dispatch` skill 的 `dispatch_git_commit_success` action 当前候选选择机制(`dispatch.sh:48-69`)为:**idle 优先 + 找到第一个 idle 即 break;无 idle 时确定性取配置顺序第一个合法候选**。后果是只要 `linyaps-packer-1` 处于 idle 或作为 fallback,负载就总压在配置顺序靠前的 agent 上,packer-2 形同虚设。

目标:改为 **idle 优先 + 随机 tie-break**——先收集所有候选的 status,从 idle 候选中随机选一个;无 idle 时从全部合法候选中随机选一个。消除"总打第一个",同时保留空闲优先智能(不退化为选到 busy/running 而跳过空闲 agent)。并将本实现方案文档落盘到 repo `docs/` 供团队查阅。

随机源用 `$RANDOM % N`(N 为候选池大小),而非用户示例的 `echo $((RANDOM % 10 + 1))`:候选数是动态的(当前 2 个 packer,配置可横向扩展到 N),`% 10 + 1` 固定且会越界;`% ${#pool[@]}` 自适应、零额外进程、模偏差可忽略(N≤几)。不引入 `shuf`(额外进程,候选少时无收益)。

## Approach

### Step 1 — 重写 `dispatch.sh` 候选选择循环(替换 `:48-69`)

当前循环边遍历边决策(遇 idle 立即 break,否则记第一个候选为 fallback)。改为**两阶段**:先遍历收集,再从池中随机抽。

替换 `dispatch.sh:47-69`(`AGENT_NAME=""; AGENT_UUID=""; AGENT_STATUS=""` 起到 `done` 止)为:

```bash
AGENT_NAME=""; AGENT_UUID=""; AGENT_STATUS=""
idle_list=()    # 元素: name<TAB>uuid<TAB>status
valid_list=()   # 元素: name<TAB>uuid<TAB>status
for line in "${candidates[@]}"; do
  name="${line%%$'\t'*}"
  cfg_uuid="${line#*$'\t'}"
  [[ "$cfg_uuid" == "$line" ]] && cfg_uuid=""
  if is_valid_uuid "$cfg_uuid"; then
    uuid="$cfg_uuid"
  else
    uuid=$(resolve_agent "$name") || { echo "warning: resolve_agent failed for $name; continuing" >&2; continue; }
    is_valid_uuid "$uuid" || { echo "warning: invalid agent uuid for $name; continuing" >&2; continue; }
  fi
  status_json=""; status="unknown"
  if status_json=$(bash "$(dirname "$0")/check-agent-status.sh" ${WORKSPACE:+-w "$WORKSPACE"} -u "$uuid" -o json 2>/dev/null); then
    status=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("agent",{}).get("status","unknown"))' <<<"$status_json" 2>/dev/null) || status=unknown
  else
    echo "warning: unable to query status for $name; continuing" >&2
  fi
  valid_list+=("$name"$'\t'"$uuid"$'\t'"$status")
  [[ "$status" == idle ]] && idle_list+=("$name"$'\t'"$uuid"$'\t'"$status")
done
((${#valid_list[@]})) || blocked no_candidate
if ((${#idle_list[@]})); then
  pool=("${idle_list[@]}")
else
  pool=("${valid_list[@]}")
fi
idx=$((RANDOM % ${#pool[@]}))
chosen="${pool[$idx]}"
chosen_name="${chosen%%$'\t'*}"
chosen_rest="${chosen#*$'\t'}"      # uuid<TAB>status
chosen_uuid="${chosen_rest%%$'\t'*}"
chosen_status="${chosen_rest#*$'\t'}"
AGENT_NAME="$chosen_name"; AGENT_UUID="$chosen_uuid"; AGENT_STATUS="$chosen_status"
```

关键行为点:
- **全量遍历**:不再遇 idle break,所有候选都查 status,保证 idle 池完整,随机覆盖全部空闲 agent。
- **idle 优先**:`idle_list` 非空时只从 idle 池随机抽;空时降级到 `valid_list` 全体随机抽——保留空闲优先,不退化成无视状态。
- **合法候选定义不变**:`resolve_agent` 失败或 uuid 无效的候选 `continue` 跳过,不进 `valid_list`(与原逻辑一致)。
- **空池兜底**:`valid_list` 为空 → `blocked no_candidate`(原 `:70` 的 `[[ -n "$AGENT_UUID" ]] || blocked no_candidate` 保留作安全网,不删)。
- **随机索引安全**:`pool` 非空已由 `valid_list` 非空保证,`$((RANDOM % ${#pool[@]}))` 在 `#pool≥1` 时安全。
- **`AGENT_STATUS` 输出** = 选中候选的实际 status(idle/unknown/...),与原"输出实际选择时的状态"语义一致。
- `$RANDOM` 由 bash 按 PID/时间隐式播种;并发 dispatch 各自进程独立种子,无需显式播种。

### Step 2 — 同步 SKILL.md 选择逻辑描述

`SKILL.md` 三处描述确定性 fallback,需改为随机 tie-break:

1. **`:59`**(`执行逻辑` 步骤 2):
   - 现:`2. 对每个候选 agent 执行状态检查；\`idle\` 优先选择。\`busy\` / \`running\` 记录警告并保留候选，状态查询失败也记录警告并保留候选。`
   - 改:`2. 对每个候选 agent 执行状态检查并收集 status；\`idle\` 候选入 idle 池，全部合法候选入候选池。\`busy\` / \`running\` 记录警告并保留候选，状态查询失败也记录警告并保留候选。`

2. **`:60`**(步骤 3):
   - 现:`3. 若没有 idle 候选，确定性选择配置顺序中的第一个合法候选并继续 dispatch；输出 \`agent_status\` 为实际选择时的状态，未知状态使用 \`unknown\`。`
   - 改:`3. idle 池非空则从中随机选取一个；否则从全部合法候选池中随机选取一个并继续 dispatch。随机源为 \`$RANDOM % 池大小\`。输出 \`agent_status\` 为选中候选的实际状态，未知状态使用 \`unknown\`。`

3. **`:65`**(重复的步骤 5,选择逻辑总结):
   - 现:`5. \`idle\` 优先；busy/running 或状态查询失败可继续，按配置顺序确定性选择合法候选。UUID 或任务上下文不一致仍为 blocked。`
   - 改:`5. \`idle\` 优先；多个 idle 或无 idle 降级时均以 \`$RANDOM % 池大小\` 随机选取，消除配置顺序偏向。UUID 或任务上下文不一致仍为 blocked。`

### Step 3 — 落盘实现方案文档到 repo `docs/`

在 Step 1/2 改动完成后(working tree 已解锁写权限),将本实现方案文档持久化到 repo `docs/`,供团队查阅。

- 目标路径:`docs/dispatch-random-tiebreak-plan.md`(沿用 `docs/issue-69-agent-skills-repair-plan.md` 既有 kebab-case + `-plan.md` 命名约定)。
- 内容来源:本 plan 文件(`local://dispatch-random-tiebreak-plan.md`)全文,原样落盘,不二次改写。
- 写入方式:`write` 新建文件(working tree 此前不存在该文件,无冲突)。
- 若该路径已存在(几乎不可能,新文件):`write` 全量覆盖,先 `read` 确认无团队他人内容再覆盖。
- 这是文档落盘,非行为变更:不纳入 Verification 行为验证范围,仅校验文件存在且内容与 plan 一致。

## Critical files & anchors

- `for-multica/skills/linyaps-binary-init-dispatch/scripts/dispatch.sh` — `:47-69` 候选选择循环(Step 1 替换目标);`:46` `no_candidate` 兜底、`:70` AGENT_UUID 兜底保留。
- `for-multica/skills/linyaps-binary-init-dispatch/SKILL.md` — `:59-60` 执行逻辑步骤 2-3、`:65` 步骤 5 总结(Step 2 文案同步)。
- `docs/dispatch-random-tiebreak-plan.md` — Step 3 新建,实现方案文档落盘(命名对齐 `docs/issue-69-agent-skills-repair-plan.md`)。

无需新增脚本、无需改 `check-agent-status.sh`、无需改 `assignment` 配置 schema(纯运行时选择逻辑变更 + 文档落盘)。

## Verification

前提:工作目录 `for-multica/skills/linyaps-binary-init-dispatch/`;有可执行的 `multica` CLI 与真实 agent-config.json,或用 mock。

1. **语法检查**:`bash -n scripts/dispatch.sh` 必须无语法错误。

2. **随机性分布(核心新行为)** — 构造 2 候选均 idle 的场景,跑多次统计选中分布:
   ```bash
   export MULTICA_ISSUE_TASK_ID=<合法测试 UUID>
   # mock check-agent-status.sh 返回 idle,或指向真实空闲环境
   for i in $(seq 1 200); do
     bash scripts/dispatch.sh dispatch_git_commit_success \
       --workspace=linyaps --pkgName=t --arch=x86_64 \
       --project_dir=CI_t --workflow_type=bin2linyaps.deb.analyze \
       --config=<agent-config.json> --output=/tmp/out.json
     python3 -c 'import json;print(json.load(open("/tmp/out.json"))["target_agent"])'
   done | sort | uniq -c
   ```
   - 预期:两个 agent 各约 100 次(±15% 波动正常),**不再 100% 命中 packer-1**。这是改动前不可能出现的输出,直接证明随机 tie-break 生效。

3. **idle 优先保留** — 构造 packer-1=busy、packer-2=idle,跑 20 次:应 100% 选中 packer-2(idle 池仅它)。证明未退化为无视状态。

4. **无 idle 降级随机** — 两候选均 busy,跑 200 次:两 agent 各约 100 次,`agent_status` 均为 `busy`/`unknown`(实际状态),证明 fallback 路径也随机且 status 透传正确。

5. **空候选兜底不变** — config 无 `linyaps_packaging` capability 的 agent:输出 `{"blocked":"no_candidate"}`,exit 2。证明兜底未回归。

6. **单候选场景** — config 仅 1 个 packer:必选该候选(随机无意义但不得出错)。

7. **文档落盘(Step 3)** — `test -f docs/dispatch-random-tiebreak-plan.md && wc -l docs/dispatch-random-tiebreak-plan.md`:文件存在,行数与本 plan 一致(±0,全文原样复制)。

> 若无真实 multica 环境跑不通端到端,至少完成 1+2;1(语法)为硬性前置,2(随机分布)为改动核心证据。3-6 在有 mock/真实环境时补齐。7 为文档校验,独立于行为验证,Step 3 完成后即可执行。

## Assumptions & contingencies

- **假设**:候选数始终很少(个位数),`$RANDOM`(0-32767)`% N` 的模偏差可忽略,无需 `/dev/urandom` 或 `shuf`。若未来候选数显著增大(>几十)仍可直接用 `$RANDOM`,偏差仍可忽略;无需为此改方案。
- **假设**:`$RANDOM` 的隐式播种对负载均衡场景足够;不追求密码学随机性。
- **回退**:若 `$RANDOM` 在目标 bash 环境(bash 4+)有异常(几乎不可能),改用 `shuf -e "${pool[@]}" -n1` 作等价替换——但默认不引入,因当前方案零额外进程。
- **不改 `check-agent-status.sh`**:status 查询语义不变,仅消费 status 的选择逻辑变更。
