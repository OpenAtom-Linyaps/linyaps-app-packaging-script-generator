#!/bin/bash
# bin2linyaps.compat-testing 执行器 — 5 步测试管线
# 用法: ./run_tasks.sh <task.json>
# 依赖: agent-config.json, skills/config/arch_mapping.json, scripts/extract_version.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"
TASK_FILE="${1:?用法: $0 <task.json>}"
CONFIG_FILE="${REPO_ROOT}/agent-config.json"
ARCH_MAPPING_FILE="${REPO_ROOT}/skills/config/arch_mapping.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $*" >&2; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

check_python3() {
    if ! command -v python3 &>/dev/null; then
        log_err "需要 python3"
        exit 1
    fi
}

check_deps() {
    local missing=0
    for cmd in python3 curl timeout; do
        if ! command -v "$cmd" &>/dev/null; then
            log_err "缺少依赖: $cmd"
            missing=1
        fi
    done
    if [[ $missing -eq 1 ]]; then
        exit 1
    fi
}

parse_json() {
    python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)

g = data.get('global', {})
print('PROJECTS_ROOT=' + json.dumps(g.get('projects_root', '')))
print('OUTPUT_DIR=' + json.dumps(g.get('output_dir', './output')))
print('BUILD_TMP_DIR=' + json.dumps(g.get('build_tmp_dir', '')))
print('SRC_DIR=' + json.dumps(g.get('src_dir', './src')))

tasks = data.get('tasks', [])
print('TASK_COUNT=' + str(len(tasks)))
for i, t in enumerate(tasks):
    print(f'TASK_{i}_PKGNAME=' + json.dumps(t.get('pkgName', '')))
    print(f'TASK_{i}_SRC_URL=' + json.dumps(t.get('src_url', '')))
    print(f'TASK_{i}_ARCH=' + json.dumps(t.get('arch', '')))
    print(f'TASK_{i}_ORIG_VERSION=' + json.dumps(t.get('orig_version', '')))
" "$1"
}

json_strip() {
    local val="$1"
    val="${val//\"/}"
    echo "$val"
}

init_directories() {
    mkdir -p "$SRC_DIR" "$OUTPUT_DIR"
    if [[ -n "$BUILD_TMP_DIR" && "$BUILD_TMP_DIR" != '""' ]]; then
        mkdir -p "$BUILD_TMP_DIR"
    else
        BUILD_TMP_DIR="$(mktemp -d)"
    fi
}

find_project_dir() {
    local pkg_name="$1"
    local root="$2"
    local candidate="$root/CI_ll_${pkg_name}"
    if [[ -d "$candidate" && -f "$candidate/pak_linyaps.sh" ]]; then
        echo "$candidate"
        return
    fi
    candidate="$root/$pkg_name"
    if [[ -d "$candidate" && -f "$candidate/pak_linyaps.sh" ]]; then
        echo "$candidate"
        return
    fi
    local found
    found=$(find "$root" -maxdepth 2 -type d -name "*${pkg_name}*" 2>/dev/null | head -1)
    if [[ -n "$found" && -f "$found/pak_linyaps.sh" ]]; then
        echo "$found"
        return
    fi
    return 1
}

download_source() {
    local url="$1"
    local dest_dir="$2"
    local pkg_name="$3"
    local filename
    filename=$(basename "$url")
    if [[ "$url" == *"/latest/"* ]]; then
        local redirect_url
        redirect_url=$(curl -sIL "$url" 2>/dev/null | grep -i '^location:' | tail -1 | awk '{print $2}' | tr -d '\r')
        if [[ -n "$redirect_url" ]]; then
            url="$redirect_url"
            filename=$(basename "$url")
        fi
    fi
    local dest_path="$dest_dir/$filename"
    if [[ -f "$dest_path" ]]; then
        log_ok "源文件已存在: $dest_path"
        echo "$dest_path"
        return
    fi
    log_info "下载: $url"
    if curl -L --progress-bar -o "$dest_path" "$url" >/dev/null 2>&1; then
        log_ok "下载完成: $dest_path"
        echo "$dest_path"
    else
        log_err "下载失败: $url"
        return 1
    fi
}

extract_version() {
    local src_url="$1"
    local pkg_name="$2"
    "$REPO_ROOT/scripts/extract_version.sh" "$src_url" "$pkg_name" --regex-file "$CONFIG_FILE" 2>/dev/null || echo ""
}

supports_build_tmp_dir() {
    local script_path="$1"
    grep -q 'build_tmp_dir' "$script_path" 2>/dev/null
}

step1_validate_yaml() {
    local project_dir="$1"
    local exec_name="$2"
    local output_file="$3"

    if [[ ! -f "$project_dir/linglong.yaml" ]]; then
        log_err "linglong.yaml 不存在: $project_dir"
        echo '{"step":"yaml_validation","status":"failed","error":"linglong.yaml not found"}'
        return 1
    fi

    mkdir -p "$(dirname "$output_file")"

    if python3 "$SCRIPT_DIR/validate_linglong_yaml.py" \
        --input "$project_dir/linglong.yaml" \
        --exec-name "${exec_name:-}" \
        --json --output "$output_file" 2>/dev/null; then
        log_ok "步骤1 YAML校验 通过"
        cat "$output_file"
    else
        log_err "步骤1 YAML校验 失败"
        echo '{"step":"yaml_validation","status":"failed","error":"validate_linglong_yaml.py exited non-zero"}'
        return 1
    fi
}

step2_validate_structure() {
    local files_res_dir="$1"
    local output_file="$2"

    if [[ ! -d "$files_res_dir" ]]; then
        log_err "files_res 目录不存在: $files_res_dir"
        echo '{"step":"structure_validation","status":"failed","error":"files_res directory not found"}'
        return 1
    fi

    mkdir -p "$(dirname "$output_file")"

    if python3 "$SCRIPT_DIR/common-data-verify.py" \
        "$files_res_dir" \
        --json --output "$output_file" 2>/dev/null; then
        log_ok "步骤2 结构校验 通过"
        cat "$output_file"
    else
        log_err "步骤2 结构校验 失败"
        echo '{"step":"structure_validation","status":"failed","error":"common-data-verify.py exited non-zero"}'
        return 1
    fi
}

step3_build_test() {
    local project_dir="$1"
    local arch="$2"
    local orig_version="$3"
    local src_path="$4"
    local output_dir="$5"
    local build_tmp_dir="$6"
    local log_file="$7"

    mkdir -p "$(dirname "$log_file")"

    local pak_script="$project_dir/pak_linyaps.sh"
    if [[ ! -f "$pak_script" ]]; then
        log_err "pak_linyaps.sh 不存在: $project_dir"
        echo '{"step":"build_test","status":"failed","error":"pak_linyaps.sh not found"}'
        return 1
    fi

    chmod +x "$pak_script"

    local task_build_tmp="${build_tmp_dir}/$(basename "$project_dir")"
    mkdir -p "$task_build_tmp"

    local build_tmp_arg=""
    if supports_build_tmp_dir "$pak_script"; then
        build_tmp_arg="--build_tmp_dir=${task_build_tmp}"
    fi

    local start_time
    start_time=$(date +%s)

    if (cd "$project_dir" && bash ./pak_linyaps.sh \
        --linyaps_arch="${arch}" \
        --origin_version="${orig_version}" \
        --src_path="${src_path}" \
        --output_dir="${output_dir}" \
        ${build_tmp_arg} > "$log_file" 2>&1); then

        local end_time
        end_time=$(date +%s)
        local elapsed=$((end_time - start_time))

        local layer_file
        layer_file=$(find "$output_dir" -name "*.layer" -type f 2>/dev/null | head -1)

        log_ok "步骤3 构建测试 通过 (耗时 ${elapsed}s)"
        echo "{\"step\":\"build_test\",\"status\":\"passed\",\"duration_seconds\":${elapsed},\"output_layer\":\"${layer_file}\"}"
        return 0
    else
        local end_time
        end_time=$(date +%s)
        local elapsed=$((end_time - start_time))
        log_err "步骤3 构建测试 失败 (耗时 ${elapsed}s)"
        tail -20 "$log_file" | while IFS= read -r line; do log_err "  $line"; done
        echo "{\"step\":\"build_test\",\"status\":\"failed\",\"duration_seconds\":${elapsed},\"log_file\":\"${log_file}\"}"
        return 1
    fi
}

step4_compat_check() {
    local build_dir="$1"
    local output_file="$2"

    mkdir -p "$(dirname "$output_file")"

    if [[ -f "$SCRIPT_DIR/demos/compat_checker.py" ]]; then
        local result
        result=$(python3 -c "
import sys, json
sys.path.insert(0, '$SCRIPT_DIR')
from demos.compat_checker import CompatChecker
from pathlib import Path
checker = CompatChecker(build_dir=Path('${build_dir}'), enable_compat_check=True, timeout=30, verbose=False)
success, message = checker.check()
status = 'passed' if success else 'failed'
print(json.dumps({'step':'compat_check','status':status,'message':message}))
" 2>/dev/null) && {
            local compat_status
            compat_status=$(echo "$result" | python3 -c "import json,sys;print(json.load(sys.stdin).get('status','failed'))" 2>/dev/null)
            if [[ "$compat_status" == "passed" ]]; then
                log_ok "步骤4 兼容性检测 通过 (CompatChecker)"
            else
                log_err "步骤4 兼容性检测 失败 (CompatChecker)"
            fi
            echo "$result" > "$output_file"
            echo "$result"
            return 0
        }
        log_warn "CompatChecker 执行失败，尝试 ll-builder run 备用"
    fi

    if ! command -v ll-builder &>/dev/null; then
        log_err "兼容性检测: ll-builder 不可用"
        echo '{"step":"compat_check","status":"failed","error":"ll-builder not available"}'
        return 1
    fi

    local compat_log="${output_file%.json}.log"
    local exit_code=0
    timeout 30 ll-builder run --build-dir "$build_dir" > "$compat_log" 2>&1 || exit_code=$?

    if [[ $exit_code -eq 0 || $exit_code -eq 124 ]]; then
        log_ok "步骤4 兼容性检测 通过 (ll-builder run, exit=$exit_code)"
        echo "{\"step\":\"compat_check\",\"status\":\"passed\",\"exit_code\":${exit_code},\"timeout_seconds\":30}"
    else
        log_err "步骤4 兼容性检测 失败 (ll-builder run, exit=$exit_code)"
        echo "{\"step\":\"compat_check\",\"status\":\"failed\",\"exit_code\":${exit_code},\"log_file\":\"${compat_log}\"}"
        return 1
    fi
}

step5_merge_report() {
    local pkg_name="$1"
    local reports_dir="$2"
    local yaml_result="$3"
    local struct_result="$4"
    local build_result="$5"
    local compat_result="$6"

    local report_file="$reports_dir/report.json"
    mkdir -p "$(dirname "$report_file")"

    local overall="passed"
    for r in "$yaml_result" "$struct_result" "$build_result" "$compat_result"; do
        local s
        s=$(echo "$r" | python3 -c "import json,sys;print(json.loads(sys.stdin.read()).get('status','failed'))" 2>/dev/null || echo "failed")
        if [[ "$s" != "passed" ]]; then
            overall="failed"
        fi
    done

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    python3 -c "
import json, sys
report = {
    'package_id': '${pkg_name}',
    'test_time': '${timestamp}',
    'overall_status': '${overall}',
    'tests': {
        'yaml_validation': json.loads('''${yaml_result}'''),
        'structure_validation': json.loads('''${struct_result}'''),
        'build_test': json.loads('''${build_result}'''),
        'compat_check': json.loads('''${compat_result}''')
    },
    'errors': [],
    'warnings': []
}
with open('${report_file}', 'w') as f:
    json.dump(report, f, indent=2, ensure_ascii=False)
print(json.dumps(report))
" 2>/dev/null || {
        log_err "步骤5 报告合并 失败"
        return 1
    }

    log_ok "步骤5 报告已生成: $report_file"
    echo "$report_file"
}

run_task() {
    local idx="$1"
    local pkg_name_var="TASK_${idx}_PKGNAME"
    local src_url_var="TASK_${idx}_SRC_URL"
    local arch_var="TASK_${idx}_ARCH"
    local ver_var="TASK_${idx}_ORIG_VERSION"

    local pkg_name="${!pkg_name_var}"
    local src_url="${!src_url_var}"
    local arch="${!arch_var}"
    local orig_version="${!ver_var}"

    pkg_name=$(json_strip "$pkg_name")
    src_url=$(json_strip "$src_url")
    arch=$(json_strip "$arch")
    orig_version=$(json_strip "$orig_version")

    log_info "=========================================="
    log_info "任务 [$((idx+1))/$TASK_COUNT]: $pkg_name"
    log_info "=========================================="

    local task_reports_dir="$OUTPUT_DIR/reports/$pkg_name"
    mkdir -p "$task_reports_dir"

    # --- 版本提取 ---
    if [[ -z "$orig_version" ]]; then
        orig_version=$(extract_version "$src_url" "$pkg_name")
        if [[ -n "$orig_version" ]]; then
            log_info "从 URL 提取版本号: $orig_version"
        else
            log_err "无法从 URL 提取版本号"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            RESULTS+=("$pkg_name: 失败 (无法提取版本号)")
            return
        fi
    fi

    # --- 下载 ---
    local src_path
    src_path=$(download_source "$src_url" "$SRC_DIR" "$pkg_name") || {
        FAIL_COUNT=$((FAIL_COUNT + 1))
        RESULTS+=("$pkg_name: 失败 (下载失败)")
        return
    }

    # --- 查找项目目录 ---
    local project_dir
    project_dir=$(find_project_dir "$pkg_name" "$PROJECTS_ROOT") || {
        log_err "找不到项目目录: $pkg_name (在 $PROJECTS_ROOT 下)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        RESULTS+=("$pkg_name: 失败 (找不到项目目录)")
        return
    }
    log_ok "项目目录: $project_dir"

    # --- 提取 exec-name (从 desktop 文件) ---
    local exec_name=""
    local desktop_file
    desktop_file=$(find "$project_dir/templates/files_res/share/applications/" -name "*.desktop" 2>/dev/null | head -1)
    if [[ -n "$desktop_file" ]]; then
        exec_name=$(grep -E '^Exec=' "$desktop_file" 2>/dev/null | head -1 | sed 's/^Exec=//' | sed 's/%.//g' | xargs)
    fi

    # ========== 步骤1: YAML 校验 ==========
    log_info "--- 步骤1/5: YAML 校验 ---"
    local yaml_result
    yaml_result=$(step1_validate_yaml "$project_dir" "$exec_name" "$task_reports_dir/yaml_validation.json") || true
    yaml_result="${yaml_result:-{\"step\":\"yaml_validation\",\"status\":\"failed\",\"error\":\"step1 exception\"}}"

    # ========== 步骤2: 结构校验 ==========
    log_info "--- 步骤2/5: 结构校验 ---"
    local files_res_dir="$project_dir/templates/files_res"
    local struct_result
    struct_result=$(step2_validate_structure "$files_res_dir" "$task_reports_dir/structure_validation.json") || true
    struct_result="${struct_result:-{\"step\":\"structure_validation\",\"status\":\"failed\",\"error\":\"step2 exception\"}}"

    # ========== 步骤3: 构建测试 ==========
    log_info "--- 步骤3/5: 构建测试 ---"
    local build_result
    build_result=$(step3_build_test "$project_dir" "$arch" "$orig_version" "$src_path" "$OUTPUT_DIR" "$BUILD_TMP_DIR" "$task_reports_dir/build.log") || true
    build_result="${build_result:-{\"step\":\"build_test\",\"status\":\"failed\",\"error\":\"step3 exception\"}}"

    # ========== 步骤4: 兼容性检测 ==========
    log_info "--- 步骤4/5: 兼容性检测 ---"
    local task_build_dir="$BUILD_TMP_DIR/$(basename "$project_dir")"
    local compat_result
    compat_result=$(step4_compat_check "$task_build_dir" "$task_reports_dir/compat_result.json") || true
    compat_result="${compat_result:-{\"step\":\"compat_check\",\"status\":\"failed\",\"error\":\"step4 exception\"}}"

    # ========== 步骤5: 合并报告 ==========
    log_info "--- 步骤5/5: 合并报告 ---"
    step5_merge_report "$pkg_name" "$task_reports_dir" "$yaml_result" "$struct_result" "$build_result" "$compat_result" || true

    # --- 判断整体状态 ---
    local overall_status
    overall_status=$(python3 -c "
import json
for r in [${yaml_result}, ${struct_result}, ${build_result}, ${compat_result}]:
    if isinstance(r, str):
        try: r = json.loads(r)
        except: pass
    if isinstance(r, dict) and r.get('status') != 'passed':
        print('failed')
        sys.exit(0)
print('passed')
" 2>/dev/null || echo "failed")

    if [[ "$overall_status" == "passed" ]]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        RESULTS+=("$pkg_name: 成功 (全部5步通过)")
        log_ok "任务完成: $pkg_name ✓"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        RESULTS+=("$pkg_name: 失败 (存在未通过的步骤)")
        log_err "任务完成: $pkg_name ✗"
    fi
    echo ""
}

# ============================================================
# 主流程
# ============================================================
check_deps

if [[ ! -f "$TASK_FILE" ]]; then
    log_err "任务文件不存在: $TASK_FILE"
    exit 1
fi

eval "$(parse_json "$TASK_FILE")"

if [[ -z "$PROJECTS_ROOT" || "$PROJECTS_ROOT" == '""' ]]; then
    log_err "JSON 中缺少 global.projects_root"
    exit 1
fi

PROJECTS_ROOT="$(cd "$PROJECTS_ROOT" 2>/dev/null && pwd || echo "$PROJECTS_ROOT")"
OUTPUT_DIR="$(cd "$(dirname "$OUTPUT_DIR")" 2>/dev/null && pwd)/$(basename "$OUTPUT_DIR")" || OUTPUT_DIR="./output"
SRC_DIR="$(cd "$(dirname "$SRC_DIR")" 2>/dev/null && pwd)/$(basename "$SRC_DIR")" || SRC_DIR="./src"

OUTPUT_DIR=$(json_strip "$OUTPUT_DIR")
SRC_DIR=$(json_strip "$SRC_DIR")
BUILD_TMP_DIR=$(json_strip "$BUILD_TMP_DIR")

log_info "项目根目录: $PROJECTS_ROOT"
log_info "输出目录:   $OUTPUT_DIR"
log_info "源文件目录: $SRC_DIR"

init_directories

SUCCESS_COUNT=0
FAIL_COUNT=0
declare -a RESULTS=()

log_info "共 $TASK_COUNT 个兼容性测试任务"
echo ""

for ((i = 0; i < TASK_COUNT; i++)); do
    run_task "$i"
done

# --- 输出统计 ---
echo ""
log_info "=========================================="
log_info "兼容性测试结果统计"
log_info "=========================================="
log_info "总计: $TASK_COUNT | ${GREEN}通过: $SUCCESS_COUNT${NC} | ${RED}失败: $FAIL_COUNT${NC}"
echo ""
for r in "${RESULTS[@]}"; do
    if [[ "$r" == *"成功"* ]]; then
        echo -e "  ${GREEN}✓${NC} $r"
    else
        echo -e "  ${RED}✗${NC} $r"
    fi
done
echo ""

# --- 写入汇总 ---
SUMMARY_FILE="$OUTPUT_DIR/reports/summary.json"
mkdir -p "$(dirname "$SUMMARY_FILE")"

python3 -c "
import json, sys

results_list = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    pkg = line.split(':')[0].strip()
    status = 'passed' if '成功' in line else 'failed'
    results_list.append({'pkgName': pkg, 'status': status})

summary = {
    'test_time': '$(date -u +"%Y-%m-%dT%H:%M:%SZ")',
    'total': ${TASK_COUNT},
    'passed': ${SUCCESS_COUNT},
    'failed': ${FAIL_COUNT},
    'results': results_list
}
with open('${SUMMARY_FILE}', 'w') as f:
    json.dump(summary, f, indent=2, ensure_ascii=False)
" <<< "$(printf '%s\n' "${RESULTS[@]}")" 2>/dev/null || true
log_info "汇总报告: $SUMMARY_FILE"

if [[ $FAIL_COUNT -eq 0 ]]; then
    log_ok "全部兼容性测试通过！"
    exit 0
else
    log_err "$FAIL_COUNT 个任务失败，请检查报告"
    exit 1
fi
