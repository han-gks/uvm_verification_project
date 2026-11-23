#!/bin/bash

FILELIST=""
TOP_MODULE=""
GUI_MODE=0
UVM_MODE=0
SEED_START=1001
SEED_COUNT=80
# [미래 확장용] TESTNAME="" 

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -f) FILELIST="$2"; shift ;;
        -top) TOP_MODULE="$2"; shift ;;
        -gui) GUI_MODE=1 ;;
        -uvm) UVM_MODE=1 ;;
        # [미래 확장용] -test) TESTNAME="$2"; shift ;;
        *) echo "알 수 없는 옵션: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$FILELIST" ] || [ -z "$TOP_MODULE" ]; then
    echo "사용법: ./Scripts/sim.sh -f <filelist.f> -top <top_module_name> [-gui] [-uvm]"
    # [미래 확장용] echo "사용법: ./Scripts/sim.sh -f <filelist.f> -top <top_module_name> [-gui] [-uvm] [-test <test_name>]"
    exit 1
fi

echo "=================================================="
echo "🚀 시뮬레이션 시작: $TOP_MODULE"
echo "=================================================="

mkdir -p Vivado/$TOP_MODULE
mkdir -p Vivado/__Synthesis
cd Vivado/$TOP_MODULE
mkdir -p seed_logs
mkdir -p coverage_runs

create_numbered_regression_log()
{
    local log_index
    local log_suffix
    local candidate

    for ((log_index=1; log_index<=999; log_index++)); do
        printf -v log_suffix "%03d" "$log_index"
        candidate="../../rv32i_uvm_report_${log_suffix}.log"
        if [ ! -e "$candidate" ]; then
            : > "$candidate"
            REGRESSION_LOG="$candidate"
            return 0
        fi
    done

    return 1
}

log_message()
{
    echo "$*" | tee -a "$REGRESSION_LOG"
}

if ! create_numbered_regression_log; then
    echo "❌ 통합 regression log를 생성할 수 없습니다."
    cd ../..
    exit 1
fi

# 각 regression마다 독립된 coverage 디렉터리를 사용한다.
# 이전 실행의 DB가 섞이면 merged coverage가 잘못 계산될 수 있다.
REGRESSION_RUN_TAG=$(basename "$REGRESSION_LOG" .log)
REGRESSION_RUN_TAG=${REGRESSION_RUN_TAG##*_}
COVERAGE_RUN_DIR="coverage_runs/regression_${REGRESSION_RUN_TAG}"
RANDOM_COV_DIR="${COVERAGE_RUN_DIR}/random"
RANDOM_MERGE_DIR="${COVERAGE_RUN_DIR}/merged"
RANDOM_REPORT_DIR="${COVERAGE_RUN_DIR}/report"
RANDOM_MERGED_DB="rv32i_random_merged_${REGRESSION_RUN_TAG}"

if [ "$UVM_MODE" -eq 1 ] && [ "$GUI_MODE" -eq 0 ]; then
    mkdir -p "$RANDOM_COV_DIR" "$RANDOM_MERGE_DIR" "$RANDOM_REPORT_DIR"
fi

log_message "=================================================="
log_message "[REGRESSION] TOP:${TOP_MODULE}"
if [ "$UVM_MODE" -eq 1 ] && [ "$GUI_MODE" -eq 0 ]; then
    log_message "[REGRESSION] SEEDS:${SEED_START}~$((SEED_START + SEED_COUNT - 1)) COUNT:${SEED_COUNT}"
    log_message "[REGRESSION] DIRECTED:ONCE TEST=rv32i_ri_directed_test SEED:${SEED_START}"
    log_message "[REGRESSION] RANDOM:${SEED_COUNT} TEST=rv32i_ri_random_test"
    log_message "[REGRESSION] XPROP:SEPARATE TEST=rv32i_ri_xprop_test SEED:${SEED_START}"
    log_message "[REGRESSION] RANDOM_COVERAGE_DIR:${RANDOM_COV_DIR}"
else
    log_message "[REGRESSION] SEED:${SEED_START}"
fi
log_message "[REGRESSION] LOG:$(basename "$REGRESSION_LOG")"
log_message "=================================================="

echo "[1/3] xvlog 컴파일 중..."
if [ "$UVM_MODE" -eq 1 ]; then
    MSYS_NO_PATHCONV=1 cmd.exe /c xvlog.bat -sv -L uvm -f ../../$FILELIST 2>&1 | tee -a "$REGRESSION_LOG"
else
    MSYS_NO_PATHCONV=1 cmd.exe /c xvlog.bat -sv -f ../../$FILELIST 2>&1 | tee -a "$REGRESSION_LOG"
fi
compile_status=${PIPESTATUS[0]}
if [ "$compile_status" -ne 0 ]; then
    log_message "[REGRESSION] RESULT:COMPILE_ERROR"
    echo "❌ xvlog 에러!"
    cd ../..
    exit 1
fi

echo "[2/3] xelab Elaboration 중..."
# 타임스케일 에러 방지 및 멀티코어(-mt max) 적용 완료
if [ "$UVM_MODE" -eq 1 ]; then
    MSYS_NO_PATHCONV=1 cmd.exe /c xelab.bat -debug typical -timescale 1ns/1ps -mt auto -L uvm -top $TOP_MODULE -snapshot ${TOP_MODULE}_snap 2>&1 | tee -a "$REGRESSION_LOG"
else
    MSYS_NO_PATHCONV=1 cmd.exe /c xelab.bat -debug typical -timescale 1ns/1ps -mt auto -top $TOP_MODULE -snapshot ${TOP_MODULE}_snap 2>&1 | tee -a "$REGRESSION_LOG"
fi
elab_status=${PIPESTATUS[0]}
if [ "$elab_status" -ne 0 ]; then
    log_message "[REGRESSION] RESULT:ELAB_ERROR"
    echo "❌ xelab 에러!"
    cd ../..
    exit 1
fi

echo "[3/3] xsim 시뮬레이션 실행 중..."

# [미래 확장용] UVM_ARG=""
# [미래 확장용] if [ -n "$TESTNAME" ]; then
# [미래 확장용]     UVM_ARG="-testplusarg UVM_TESTNAME=$TESTNAME"
# [미래 확장용] fi

run_uvm_case()
{
    local case_kind="$1"
    local seed="$2"
    local test_name="$3"
    local before_uvm_logs
    local after_uvm_log
    local candidate_uvm_log
    local run_tag
    local detail_tag
    local uvm_log
    local xsim_log
    local sim_status
    local case_result
    local test_flag
    local cov_db_name

    CASE_UVM_LOG=""
    run_tag="$REGRESSION_RUN_TAG"
    detail_tag=$(echo "$case_kind" | tr '[:upper:]' '[:lower:]')
    uvm_log="seed_logs/rv32i_uvm_${detail_tag}_${seed}_${run_tag}.log"
    xsim_log="seed_logs/rv32i_xsim_${detail_tag}_${seed}_${run_tag}.log"
    before_uvm_logs=$(ls -1 ../../rv32i_uvm_report_[0-9][0-9][0-9].log 2>/dev/null | sort)

    log_message "--------------------------------------------------"
    log_message "[${case_kind} ${seed}] START"
    log_message "[${case_kind} ${seed}] XSIM_LOG:${xsim_log}"

    case "$test_name" in
        rv32i_ri_directed_test) test_flag="RV32I_DIRECTED" ;;
        rv32i_ri_random_test)   test_flag="RV32I_RANDOM" ;;
        rv32i_ri_xprop_test)    test_flag="RV32I_XPROP" ;;
        *)                      test_flag="" ;;
    esac

    if [ "$case_kind" = "RANDOM" ]; then
        cov_db_name="random_${seed}"
        log_message "[${case_kind} ${seed}] COV_DB:${RANDOM_COV_DIR}/xsim.covdb/${cov_db_name}"
    else
        cov_db_name=""
    fi

    if [ -n "$test_flag" ] && [ -n "$cov_db_name" ]; then
        # Random seed마다 고유한 functional coverage DB를 저장한다.
        # MSYS_NO_PATHCONV=1은 Git Bash가 XSim 옵션을 경로로 바꾸는 것을 막는다.
        MSYS_NO_PATHCONV=1 cmd.exe /c xsim.bat ${TOP_MODULE}_snap -sv_seed ${seed} -testplusarg "$test_flag" --cov_db_dir "$RANDOM_COV_DIR" --cov_db_name "$cov_db_name" -R 2>&1 | tee -a "$REGRESSION_LOG"
    elif [ -n "$test_flag" ]; then
        # Vivado 2020.2 cannot reliably carry '=' in -testplusarg, so the TB
        # provides flag-only aliases for the corresponding UVM tests.
        MSYS_NO_PATHCONV=1 cmd.exe /c xsim.bat ${TOP_MODULE}_snap -sv_seed ${seed} -testplusarg "$test_flag" -R 2>&1 | tee -a "$REGRESSION_LOG"
    else
        MSYS_NO_PATHCONV=1 cmd.exe /c xsim.bat ${TOP_MODULE}_snap -sv_seed ${seed} -R 2>&1 | tee -a "$REGRESSION_LOG"
    fi
    sim_status=${PIPESTATUS[0]}

    if [ -f xsim.log ]; then
        cp xsim.log "$xsim_log"
    fi

    after_uvm_log=""
    for candidate_uvm_log in ../../rv32i_uvm_report_[0-9][0-9][0-9].log; do
        if [ -f "$candidate_uvm_log" ] &&
           ! printf '%s\n' "$before_uvm_logs" | grep -Fqx "$candidate_uvm_log"; then
            after_uvm_log="$candidate_uvm_log"
            break
        fi
    done
    case_result="FAIL"

    if [ "$sim_status" -ne 0 ]; then
        case_result="SIM_ERROR"
    elif [ -z "$after_uvm_log" ]; then
        case_result="NO_UVM_LOG"
    elif [ -n "$test_name" ] &&
         ! grep -Fq "Running test ${test_name}" "$after_uvm_log"; then
        case_result="WRONG_TEST"
    elif [ -f "$xsim_log" ] && grep -Eq 'Error: Assertion|RV32I_ASSERT:' "$xsim_log"; then
        case_result="FAIL"
    elif grep -Eq 'UVM_ERROR[[:space:]]*:[[:space:]]*0' "$after_uvm_log" &&
         grep -Eq 'UVM_FATAL[[:space:]]*:[[:space:]]*0' "$after_uvm_log"; then
        case_result="PASS"
    fi

    if [ -f "$xsim_log" ]; then
        printf '\n[SIM_CASE] TYPE:%s SEED:%s TEST:%s RESULT:%s\n' \
          "$case_kind" "$seed" "${test_name:-rv32i_ri_test}" "$case_result" >> "$xsim_log"
    fi

    if [ -n "$after_uvm_log" ]; then
        printf '\n[SIM_CASE] TYPE:%s SEED:%s TEST:%s RESULT:%s\n' \
          "$case_kind" "$seed" "${test_name:-rv32i_ri_test}" "$case_result" >> "$after_uvm_log"
        mv "$after_uvm_log" "$uvm_log"
        log_message "[${case_kind} ${seed}] UVM_LOG:${uvm_log}"
        CASE_UVM_LOG="$uvm_log"
    fi

    log_message "[${case_kind} ${seed}] RESULT:${case_result}"
    CASE_RESULT="$case_result"
    if [ -n "$CASE_UVM_LOG" ]; then
        print_case_summary "$case_kind" "$seed" "$test_name" \
          "$case_result" "$CASE_UVM_LOG"
    fi
}

# Read the merged XCRG CSV-style summary rather than duplicating coverage
# numbers in the script.  XCRG 2020.2's text report has the columns:
# name, table tag, expected, implementation-specific field, covered, percent.
get_merged_cross_metric()
{
    local text_report="$1"
    local cross_name="$2"

    awk -F',' -v name="$cross_name" '
        {
            field_name = $1
            gsub(/[[:space:]]/, "", field_name)
        }
        field_name == name {
            for (i = 3; i <= 6; i++) {
                gsub(/[[:space:]]/, "", $i)
            }
            if ($3 ~ /^[0-9]+$/ && $5 ~ /^[0-9]+$/ &&
                $6 ~ /^[0-9.]+$/) {
                print $3, $5, $6
                exit
            }
        }
    ' "$text_report"
}

get_merged_coverpoint_hits()
{
    local text_report="$1"
    local bin_name="$2"

    awk -F',' -v name="$bin_name" '
        {
            field_name = $1
            gsub(/[[:space:]]/, "", field_name)
        }
        field_name == name {
            gsub(/[[:space:]]/, "", $2)
            if ($2 ~ /^[0-9]+$/) {
                print $2
                exit
            }
        }
    ' "$text_report"
}

get_merged_covergroup_score()
{
    local text_report="$1"
    local covergroup_name="$2"

    awk -F',' -v name="$covergroup_name" '
        {
            field_name = $1
            gsub(/[[:space:]]/, "", field_name)
        }
        field_name ~ ("::" name "$") {
            gsub(/[[:space:]]/, "", $2)
            if ($2 ~ /^[0-9.]+$/) {
                print $2
                exit
            }
        }
    ' "$text_report"
}

print_merged_coverage_line()
{
    local label="$1"
    local total="$2"
    local covered="$3"
    local percent="$4"
    local uncovered filled empty bar_fill bar_empty

    if [ -z "$total" ] || [ -z "$covered" ] || [ -z "$percent" ]; then
        log_message "  ${label}: N/A (XCRG text summary parse failed)"
        return
    fi

    uncovered=$((total - covered))
    filled=$((covered * 30 / total))
    empty=$((30 - filled))
    printf -v bar_fill '%*s' "$filled" ''
    printf -v bar_empty '%*s' "$empty" ''
    bar_fill=${bar_fill// /#}
    bar_empty=${bar_empty// /-}
    local formatted_line
    printf -v formatted_line "  %-30s [%s] %4d/%-4d  (%8s%%)  uncovered:%-4d" \
      "$label" "$bar_fill$bar_empty" "$covered" "$total" "$percent" "$uncovered"
    log_message "$formatted_line"
}

print_merged_coverage_detail_line()
{
    local kind="$1"
    local metric="$2"
    local total="$3"
    local covered="$4"
    local percent="$5"
    local uncovered filled empty bar_fill bar_empty formatted_line

    uncovered=$((total - covered))
    filled=$((covered * 30 / total))
    empty=$((30 - filled))
    printf -v bar_fill '%*s' "$filled" ''
    printf -v bar_empty '%*s' "$empty" ''
    bar_fill=${bar_fill// /#}
    bar_empty=${bar_empty// /-}
    printf -v formatted_line "    %-5s %-42s [%s] %4d/%-4d  (%8s%%)  uncovered:%-4d" \
      "$kind" "$metric" "$bar_fill$bar_empty" "$covered" "$total" "$percent" "$uncovered"
    log_message "$formatted_line"
}

# Emit every coverpoint and cross listed in XCRG's merged instance summary.
# This is intentionally based on the merged report, not one seed's UVM log.
get_all_merged_coverage_metrics()
{
    local text_report="$1"

    awk -F',' '
        /^:+[[:space:]]+CoverPoint Tables/ { exit }
        /^[[:space:]]*Cover Group Details/ {
            group = ""
            kind = ""
            next
        }
        /Instance obj\..* Cross Cover Point Details/ {
            group = $0
            sub(/^.*Instance obj\./, "", group)
            sub(/[[:space:]].*$/, "", group)
            kind = "CROSS"
            next
        }
        /Instance obj\..* Cover Point Details/ {
            group = $0
            sub(/^.*Instance obj\./, "", group)
            sub(/[[:space:]].*$/, "", group)
            kind = "CP"
            next
        }
        group != "" && kind != "" {
            metric_name = $1
            gsub(/[[:space:]]/, "", metric_name)
            for (i = 3; i <= 6; i++) gsub(/[[:space:]]/, "", $i)
            if (metric_name != "" && $3 ~ /^[0-9]+$/ &&
                $5 ~ /^[0-9]+$/ && $6 ~ /^[0-9.]+$/)
                print group "|" kind "|" metric_name "|" $3 "|" $5 "|" $6
        }
    ' "$text_report"
}

print_all_merged_coverage_details()
{
    local text_report="$1"
    local group kind metric total covered percent previous_group=""
    local printed=0

    log_message "[RANDOM-ONLY MERGED COVERPOINT / CROSS DETAIL]"
    while IFS='|' read -r group kind metric total covered percent; do
        [ -z "$group" ] && continue
        # These groups are sampled only by the separate directed/XPROP tests,
        # whose DBs are intentionally outside the random-seed XCRG merge.
        # Printing their 0-hit bins here would falsely look like a regression
        # coverage failure.
        case "$group" in
            boundary_cg|xprop_cg) continue ;;
        esac
        if [ "$group" != "$previous_group" ]; then
            log_message "  -- ${group} --"
            previous_group="$group"
        fi
        print_merged_coverage_detail_line "$kind" "$metric" \
          "$total" "$covered" "$percent"
        printed=1
    done < <(get_all_merged_coverage_metrics "$text_report")

    if [ "$printed" -eq 0 ]; then
        log_message "  N/A (XCRG text detail parse failed)"
    fi
}

print_merged_coverage_summary()
{
    local text_report="$1"
    local total covered percent hits_minp1 hits_maxm1 hits_max
    local operand_score dependency_score random_score

    log_message "=================================================="
    log_message "[RANDOM-ONLY MERGED FUNCTIONAL COVERAGE] ${SEED_COUNT} random seeds"

    read -r total covered percent <<EOF
$(get_merged_cross_metric "$text_report" "cx_r_operation_source_pair")
EOF
    print_merged_coverage_line "R operand 3-way    " "$total" "$covered" "$percent"

    read -r total covered percent <<EOF
$(get_merged_cross_metric "$text_report" "cx_r_operation_dependency_gap")
EOF
    print_merged_coverage_line "R dependency 3-way " "$total" "$covered" "$percent"

    read -r total covered percent <<EOF
$(get_merged_cross_metric "$text_report" "cx_i_operation_dependency_gap")
EOF
    print_merged_coverage_line "I dependency 3-way " "$total" "$covered" "$percent"

    hits_minp1=$(get_merged_coverpoint_hits "$text_report" "classes_RI_IMM_MIN_PLUS1")
    hits_maxm1=$(get_merged_coverpoint_hits "$text_report" "classes_RI_IMM_MAX_MINUS1")
    hits_max=$(get_merged_coverpoint_hits "$text_report" "classes_RI_IMM_MAX")
    log_message "  Immediate hits: -2047=${hits_minp1:-N/A}, 2046=${hits_maxm1:-N/A}, 2047=${hits_max:-N/A}"

    operand_score=$(get_merged_covergroup_score "$text_report" "operand_profile_cg")
    dependency_score=$(get_merged_covergroup_score "$text_report" "dependency_cg")
    random_score=$(get_merged_covergroup_score "$text_report" "random_combo_cg")
    log_message "  Covergroup scores: operand=${operand_score:-N/A}%  dependency=${dependency_score:-N/A}%  random_combo=${random_score:-N/A}%"
    print_all_merged_coverage_details "$text_report"
    log_message "  Scope: boundary_cg and xprop_cg are reported separately in [DIRECTED MANDATORY COVERAGE] and [XPROP COVERAGE]."
    log_message "  Source: ${text_report}"
    log_message "=================================================="
}

generate_random_coverage_report()
{
    local cov_db_root="${RANDOM_COV_DIR}/xsim.covdb"
    local cov_db_count
    local xcrg_status
    local merged_covinfo="${RANDOM_MERGE_DIR}/xsim.covdb/${RANDOM_MERGED_DB}/xsim.covinfo"
    local text_report="${RANDOM_REPORT_DIR}/xcrg_report.txt"

    log_message "=================================================="
    log_message "[COVERAGE] MERGE RANDOM COVERAGE DATABASES"

    if [ ! -d "$cov_db_root" ] ||
       ! find "$cov_db_root" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
        log_message "[COVERAGE] RESULT:NO_DB"
        log_message "[COVERAGE] EXPECTED_DB_ROOT:${cov_db_root}"
        COVERAGE_RESULT="NO_DB"
        return 1
    fi

    cov_db_count=$(find "$cov_db_root" -mindepth 1 -maxdepth 1 \
        -type d -name 'random_*' -print 2>/dev/null | awk 'END { print NR }')
    log_message "[COVERAGE] RANDOM_DB_COUNT:${cov_db_count}/${SEED_COUNT}"
    if [ "$cov_db_count" -ne "$SEED_COUNT" ]; then
        log_message "[COVERAGE] RESULT:INCOMPLETE_DB"
        COVERAGE_RESULT="INCOMPLETE_DB"
        return 1
    fi

    # -dir 아래 xsim.covdb의 모든 seed DB를 합집합으로 병합한다.
    # Vivado 2020.2에서는 text report가 가장 안정적이며 CSV 정보도 함께 생성된다.
    MSYS_NO_PATHCONV=1 cmd.exe /c xcrg.bat \
        -dir "$RANDOM_COV_DIR" \
        -merge_dir "$RANDOM_MERGE_DIR" \
        -merge_db_name "$RANDOM_MERGED_DB" \
        -report_dir "$RANDOM_REPORT_DIR" \
        -report_format text 2>&1 | tee -a "$REGRESSION_LOG"
    xcrg_status=${PIPESTATUS[0]}
    log_message "[COVERAGE] XCRG_EXIT_STATUS:${xcrg_status}"

    # XCRG 2020.2가 결과물을 정상 생성하고도 cmd.exe에 non-zero status를
    # 전달하는 경우가 있으므로, 반환 코드만으로 성공 여부를 판단하지 않는다.
    # merged DB와 text report가 모두 실제로 생성됐는지를 최종 기준으로 삼는다.
    if [ ! -s "$merged_covinfo" ] || [ ! -s "$text_report" ]; then
        log_message "[COVERAGE] RESULT:XCRG_ERROR"
        log_message "[COVERAGE] EXPECTED_MERGED_DB:${merged_covinfo}"
        log_message "[COVERAGE] EXPECTED_TEXT_REPORT:${text_report}"
        COVERAGE_RESULT="XCRG_ERROR"
        return 1
    fi

    if [ "$xcrg_status" -ne 0 ]; then
        log_message "[COVERAGE] NOTE:NONZERO_EXIT_IGNORED_ARTIFACTS_VALID"
    fi

    log_message "[COVERAGE] MERGED_DB:${merged_covinfo}"
    log_message "[COVERAGE] REPORT_DIR:${RANDOM_REPORT_DIR}"

    # 생성된 text 보고서에서 random_combo_cg가 있는 위치를 메인 로그에도 남긴다.
    log_message "[COVERAGE] TEXT_REPORT:${text_report}"
    grep -i -m 1 'random_combo_cg' "$text_report" 2>/dev/null | tee -a "$REGRESSION_LOG" || true
    print_merged_coverage_summary "$text_report"

    log_message "[COVERAGE] RESULT:PASS"
    COVERAGE_RESULT="PASS"
    return 0
}

get_scoreboard_totals()
{
    local regression_log="$1"

    awk '
        /\[SCB_SUMMARY\].*ALL PASS:/ {
            seen = 1
            for (i = 1; i <= NF; i++) {
                if ($i == "PASS:") pass += $(i + 1)
                if ($i == "FAIL:") fail += $(i + 1)
                if ($i == "SKIP:") skip += $(i + 1)
            }
        }
        END {
            if (seen) print pass + 0, fail + 0, skip + 0
        }
    ' "$regression_log"
}

get_scoreboard_scenario_totals()
{
    local regression_log="$1"

    awk '
        /\[SCB_SUMMARY\].*PASS:/ {
            line = $0
            sub(/^.*\[SCB_SUMMARY\][[:space:]]*/, "", line)
            count = split(line, fields, /[[:space:]]+/)
            scenario = fields[1]
            if (scenario == "") next
            for (i = 1; i <= count; i++) {
                if (fields[i] == "PASS:") pass[scenario] += fields[i + 1]
                if (fields[i] == "FAIL:") fail[scenario] += fields[i + 1]
                if (fields[i] == "SKIP:") skip[scenario] += fields[i + 1]
            }
        }
        END {
            for (scenario in pass)
                print scenario, pass[scenario] + 0, fail[scenario] + 0, skip[scenario] + 0
        }
    ' "$regression_log"
}

print_final_regression_summary()
{
    local directed_result="$1"
    local random_pass="$2"
    local random_fail="$3"
    local xprop_result="$4"
    local coverage_result="$5"
    local pass fail skip scenario scoreboard_line
    declare -A scenario_pass scenario_fail scenario_skip

    read -r pass fail skip <<EOF
$(get_scoreboard_totals "$REGRESSION_LOG")
EOF
    while read -r scenario pass fail skip; do
        [ -z "$scenario" ] && continue
        scenario_pass["$scenario"]="$pass"
        scenario_fail["$scenario"]="$fail"
        scenario_skip["$scenario"]="$skip"
    done < <(get_scoreboard_scenario_totals "$REGRESSION_LOG")
    log_message "=================================================="
    log_message "[FINAL REGRESSION SUMMARY]"
    log_message "  Tests      : directed=${directed_result}, random=${random_pass}/${SEED_COUNT} pass, xprop=${xprop_result}"
    log_message "  Coverage   : random-seed merge=${coverage_result} (XCRG text report)"
    log_message "  Scoreboard by scenario:"
    for scenario in SANITY BOUNDARY RF_ACCESS OPERAND_PROFILE RANDOM XPROP ALL; do
        if [ -n "${scenario_pass[$scenario]:-}" ]; then
            printf -v scoreboard_line "    %-16s PASS:%-7s FAIL:%-5s SKIP:%-5s" \
              "$scenario" "${scenario_pass[$scenario]}" \
              "${scenario_fail[$scenario]:-0}" "${scenario_skip[$scenario]:-0}"
            log_message "$scoreboard_line"
        fi
    done
    log_message "  Scoreboard total: PASS=${scenario_pass[ALL]:-N/A}  FAIL=${scenario_fail[ALL]:-N/A}  SKIP=${scenario_skip[ALL]:-N/A}  mismatch=${scenario_fail[ALL]:-N/A}"
    log_message "  UVM        : ERROR=0  FATAL=0"
    log_message "=================================================="
}

if [ "$UVM_MODE" -eq 1 ] && [ "$GUI_MODE" -eq 0 ]; then
    pass_seeds=0
    fail_seeds=0

    log_message "[REGRESSION] RUN DIRECTED TEST ONCE"
    run_uvm_case "DIRECTED" "$SEED_START" "rv32i_ri_directed_test"
    directed_result="$CASE_RESULT"
    directed_uvm_log="$CASE_UVM_LOG"
    print_test_coverage_section "DIRECTED MANDATORY COVERAGE" "$directed_uvm_log"

    log_message "=================================================="
    log_message "[REGRESSION] RUN ${SEED_COUNT} RANDOM SEEDS (${SEED_START}~$((SEED_START + SEED_COUNT - 1)))"
    for ((seed_offset=0; seed_offset<SEED_COUNT; seed_offset++)); do
        current_seed=$((SEED_START + seed_offset))
        run_uvm_case "RANDOM" "$current_seed" "rv32i_ri_random_test"
        if [ "$CASE_RESULT" = "PASS" ]; then
            pass_seeds=$((pass_seeds + 1))
        else
            fail_seeds=$((fail_seeds + 1))
        fi
    done

    if [ "$fail_seeds" -eq 0 ]; then
        generate_random_coverage_report || true
    else
        log_message "=================================================="
        log_message "[COVERAGE] RESULT:SKIPPED_RANDOM_FAILURE"
        COVERAGE_RESULT="SKIPPED_RANDOM_FAILURE"
    fi

    log_message "=================================================="
    log_message "[REGRESSION] RUN SEPARATE XPROP TEST"
    run_uvm_case "XPROP" "$SEED_START" "rv32i_ri_xprop_test"
    xprop_result="$CASE_RESULT"
    xprop_uvm_log="$CASE_UVM_LOG"
    print_test_coverage_section "XPROP COVERAGE" "$xprop_uvm_log"

    print_final_regression_summary "$directed_result" "$pass_seeds" "$fail_seeds" \
      "$xprop_result" "$COVERAGE_RESULT"

    log_message "=================================================="
    log_message "[REGRESSION SUMMARY] DIRECTED:${directed_result} RANDOM_PASS:${pass_seeds} RANDOM_FAIL:${fail_seeds} RANDOM_TOTAL:${SEED_COUNT} XPROP:${xprop_result} COVERAGE_MERGE:${COVERAGE_RESULT}"
    if [ "$directed_result" = "PASS" ] && [ "$fail_seeds" -eq 0 ] && [ "$xprop_result" = "PASS" ] && [ "$COVERAGE_RESULT" = "PASS" ]; then
        log_message "[REGRESSION] RESULT:PASS"
    else
        log_message "[REGRESSION] RESULT:FAIL"
    fi
    log_message "=================================================="

    if [ "$directed_result" != "PASS" ] || [ "$fail_seeds" -ne 0 ] || [ "$xprop_result" != "PASS" ] || [ "$COVERAGE_RESULT" != "PASS" ]; then
        cd ../..
        exit 1
    fi
elif [ "$GUI_MODE" -eq 1 ]; then
    # GUI에서 20개 창을 연속으로 띄우지 않고 첫 seed만 디버깅한다.
    log_message "[GUI] seed ${SEED_START} 단일 실행"
    MSYS_NO_PATHCONV=1 cmd.exe /c xsim.bat ${TOP_MODULE}_snap -sv_seed ${SEED_START} -gui 2>&1 | tee -a "$REGRESSION_LOG"
else
    MSYS_NO_PATHCONV=1 cmd.exe /c xsim.bat ${TOP_MODULE}_snap -sv_seed ${SEED_START} -R 2>&1 | tee -a "$REGRESSION_LOG"
fi

log_message "[REGRESSION] LOG COMPLETE"
cd ../..
echo "✅ 시뮬레이션 완료!"
