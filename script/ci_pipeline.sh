#!/usr/bin/env bash
#
# ci_pipeline.sh — 下载代码，串联 build_and_pack_run.sh + run_ut.sh，输出耗时 JSON。
# Usage:
#   bash script/ci_pipeline.sh [OPTIONS]
#
# Options:
#   --py_version VER  python 版本 (default: cp311-cp311)
#   --repo URL        代码仓库   (default: https://gitcode.com/Ascend/memfabric_hybrid.git)
#   --branch NAME     分支       (default: main)
#   --build_mode MODE RELEASE|DEBUG|ASAN (default: RELEASE)
#   --ut_filter STR   gtest 过滤 (default: "")
#   --fast            UT 快速模式（增量 + 无覆盖率）
#   --output PATH     JSON 路径  (default: output/ci_report.json)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── 默认参数 ─────────────────────────────────────────────────────
REPO_URL="https://gitcode.com/Ascend/memfabric_hybrid.git"
BRANCH="main"
PY_VERSION="cp311-cp311"
BUILD_MODE="RELEASE"
UT_FILTER=""
FAST_UT="OFF"
REPORT_JSON=""

# ── 解析参数 ─────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)       REPO_URL="$2";    shift 2 ;;
    --branch)     BRANCH="$2";      shift 2 ;;
    --py_version) PY_VERSION="$2";  shift 2 ;;
    --build_mode) BUILD_MODE="$2";  shift 2 ;;
    --ut_filter)  UT_FILTER="$2";   shift 2 ;;
    --fast)       FAST_UT="ON";     shift ;;
    --output)     REPORT_JSON="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

REPORT_JSON="${REPORT_JSON:-${PROJECT_ROOT}/output/ci_report.json}"
mkdir -p "$(dirname "${REPORT_JSON}")"

# ── 配置 manylinux Python ─────────────────────────────────────────
export PYTHON_HOME=/opt/python/${PY_VERSION}
export PATH=/opt/python/${PY_VERSION}/bin:/usr/bin:$PATH

echo ">>> Python: ${PYTHON_HOME} ($(python3 --version 2>&1))"

# ── 安装依赖工具 ──────────────────────────────────────────────────
pip3 install --upgrade pip
pip3 install --upgrade setuptools wheel
pip3 install pybind11==3.0.1

# ── 时间计算工具 ──────────────────────────────────────────────────
get_ns() {
  if [[ -f /proc/uptime ]]; then
    awk '{printf "%.0f", $1 * 1000000000}' /proc/uptime
  else
    date +%s%N
  fi
}

elapsed() { echo "($2 - $1) / 1000000000" | bc -l 2>/dev/null \
  || python3 -c "print(round(($2 - $1) / 1e9, 3))"; }

# ── Step 1: 代码下载 + 三方依赖初始化 ─────────────────────────────
echo ">>> [1/3] Cloning ${REPO_URL} (branch=${BRANCH})"
NS_START=$(get_ns)

WORK_DIR="$(mktemp -d)"
git clone --branch "${BRANCH}" "${REPO_URL}" "${WORK_DIR}"
cd "${WORK_DIR}"
git submodule update --recursive --init

NS_END=$(get_ns)
DEPS_S=$(elapsed "${NS_START}" "${NS_END}")
echo ">>> 代码下载 + 三方依赖: ${DEPS_S}s"

# ── Step 2: 编译出包 ─────────────────────────────────────────────
echo ">>> [2/3] Building"
NS_START=$(get_ns)

bash "${WORK_DIR}/script/build_and_pack_run.sh" \
  --build_mode "${BUILD_MODE}" \
  --build_python ON \
  --xpu_type NPU \
  --build_test OFF \
  --build_hcom OFF

NS_END=$(get_ns)
BUILD_S=$(elapsed "${NS_START}" "${NS_END}")
echo ">>> 编译出包: ${BUILD_S}s"

# ── Step 3: 执行 UT ──────────────────────────────────────────────
echo ">>> [3/3] Running UT"
NS_START=$(get_ns)

UT_ARGS=()
[[ "${FAST_UT}" == "ON" ]] && UT_ARGS=(--fast)
[[ -n "${UT_FILTER}" ]] && UT_ARGS+=("${UT_FILTER}")

bash "${WORK_DIR}/script/run_ut.sh" "${UT_ARGS[@]}" || true

NS_END=$(get_ns)
UT_S=$(elapsed "${NS_START}" "${NS_END}")
echo ">>> 执行 UT: ${UT_S}s"

# ── 提取 Top10 最慢 case ─────────────────────────────────────────
GTEST_JSON="${WORK_DIR}/output/coverage/gtest_result.json"

TOP10=$(python3 -c "
import json
try:
    with open('${GTEST_JSON}') as f:
        data = json.load(f)
    cases = []
    for suite in data.get('tests', []):
        for tc in suite.get('tests', []):
            dur = tc.get('duration_ms', tc.get('time_sec', 0) * 1000)
            cases.append({'name': f\"{suite['name']}/{tc['name']}\", 'duration_ms': round(dur, 3)})
    cases.sort(key=lambda c: c['duration_ms'], reverse=True)
    print(json.dumps(cases[:10], indent=2))
except:
    print('[]')
" 2>/dev/null || echo "[]")

# ── 汇总 ──────────────────────────────────────────────────────────
TOTAL=$(echo "${DEPS_S} + ${BUILD_S} + ${UT_S}" | bc -l 2>/dev/null \
  || python3 -c "print(round(${DEPS_S} + ${BUILD_S} + ${UT_S}, 3))")

# ── 输出 JSON ─────────────────────────────────────────────────────
cat > "${REPORT_JSON}" << EOF
{
  "pipeline": "memfabric_hybrid CI",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "steps": {
    "code_download_and_deps": { "duration_sec": ${DEPS_S} },
    "build_and_pack": { "duration_sec": ${BUILD_S} },
    "unit_tests": { "duration_sec": ${UT_S} }
  },
  "total_duration_sec": ${TOTAL},
  "top_10_slowest_cases": ${TOP10}
}
EOF

echo ""
echo "============================================================"
echo "  Code download + deps : ${DEPS_S}s"
echo "  Build & pack         : ${BUILD_S}s"
echo "  Unit tests           : ${UT_S}s"
echo "  Total                : ${TOTAL}s"
echo "============================================================"
echo "  Report: ${REPORT_JSON}"
echo ""

# 清理临时目录
rm -rf "${WORK_DIR}"
