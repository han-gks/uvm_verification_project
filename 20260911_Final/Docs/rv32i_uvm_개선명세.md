# RV32I R/I-type UVM 검증환경 개선 명세

작업 지시서. 아래 T1~T10을 순서대로 구현한다.

> **구현 상태 (2026-09-13)**: T1~T9와 선택 항목 T10 구현 완료.
> 최종 회귀는 directed 1회, random seed 1001~1020, XPROP 1회가 모두
> 통과했다. 통합 결과는 `rv32i_uvm_report_021.log`에 기록되어 있다.

---

## 0. 환경 및 제약조건

구현 전 반드시 숙지할 것.

| 항목 | 내용 |
|---|---|
| 시뮬레이터 | Vivado xsim (**VCS 사용 불가**) |
| 코드 커버리지 | **수집 불가** — `-cm` 옵션 사용 못 함 |
| 외부 골든모델 | **없음** (Spike/Sail 붙이지 않음) |
| 검증 스코프 | RV32I의 **R-type / I-type만**. S/B/U/J/JR은 범위 밖 |
| TB 구조 | `tb_rv32i_uvm.sv` 단일 파일 UVM + 별도 probe/assertion 파일 |

### 대상 파일

```
tb_rv32i_uvm.sv           # UVM 전체 (시퀀스/드라이버/모니터/스코어보드/커버리지/테스트)
rv32i_probe_if.sv         # 관측용 인터페이스 (수동)
rv32i_core_probe.sv       # DUT 내부신호 → probe_if 브릿지 + assertion 인스턴스
rv32i_core_assertions.sv  # SVA 체커 + 사이클레벨 참조모델
```

### 절대 깨뜨리면 안 되는 것 (회귀 위험)

1. `RI_SETUP` / `RI_TARGET` / `RI_READBACK` 역할 태깅 체계 — 커버리지 오염 방지의 핵심
2. 드라이버가 `program_ap`로 프로그램 이미지를 스코어보드에 직접 전달하는 구조 — 참조모델 독립성의 근거
3. `emit_readback`(`ADDI rd,rd,0`) 메커니즘 — 레지스터 파일을 hierarchical reference로 훔쳐보지 않고 저장상태를 검증
4. 기존 directed 시퀀스(sanity/boundary/rf_access/operand_profile)가 만드는 커버리지 100% 달성

---

## T1. Cover Property 추가 【최우선】

**대상**: `rv32i_core_assertions.sv`

### 문제

현재 어설션이 전부 `assert`이고 `cover`가 **하나도 없다**. SVA는 antecedent가 한 번도 성립하지 않으면 그냥 통과한다(vacuous pass). 따라서 로그에 PASS가 찍혀도 "체크가 성공했다"인지 "체크가 발동조차 안 했다"인지 구분이 불가능하다.

VCS 코드커버리지를 못 쓰는 환경이므로, **`cover property`가 FSM/branch 커버리지의 유일한 대체수단**이다.

### 구현

`rv32i_core_assertions.sv` 파일 끝(`endmodule` 직전)에 아래 블록을 추가한다.

```systemverilog
  // =================================================================
  // COVER PROPERTIES
  // 코드커버리지를 수집할 수 없는 환경에서 FSM 상태/전이 도달 여부와
  // 각 어설션의 antecedent 발동 여부를 정량적으로 확인한다.
  // =================================================================

  // --- FSM 상태 도달 (state coverage 대체) ---
  c_state_fetch: cover property (
    @(posedge clk) disable iff (!rst_n) state == CPU_FETCH);
  c_state_decode: cover property (
    @(posedge clk) disable iff (!rst_n) state == CPU_DECODE);
  c_state_execute: cover property (
    @(posedge clk) disable iff (!rst_n) state == CPU_EXECUTE);
  c_state_memory: cover property (
    @(posedge clk) disable iff (!rst_n) state == CPU_MEMORY);
  c_state_writeback: cover property (
    @(posedge clk) disable iff (!rst_n) state == CPU_WRITEBACK);

  // --- FSM 전이 (transition coverage 대체) ---
  c_trans_fetch_decode: cover property (
    @(posedge clk) disable iff (!rst_n)
    (state == CPU_FETCH) ##1 (state == CPU_DECODE));
  c_trans_decode_execute: cover property (
    @(posedge clk) disable iff (!rst_n)
    (state == CPU_DECODE) ##1 (state == CPU_EXECUTE));
  c_trans_execute_fetch: cover property (
    @(posedge clk) disable iff (!rst_n)
    (state == CPU_EXECUTE) ##1 (state == CPU_FETCH));

  // --- 어설션 antecedent 발동 확인 (vacuous pass 탐지) ---
  c_rtype_executed: cover property (
    @(posedge clk) disable iff (!rst_n)
    state == CPU_EXECUTE && is_legal_rtype(instr));
  c_itype_executed: cover property (
    @(posedge clk) disable iff (!rst_n)
    state == CPU_EXECUTE && is_legal_itype(instr));
  c_rtype_x_source: cover property (
    @(posedge clk) disable iff (!rst_n)
    state == CPU_EXECUTE && is_legal_rtype(instr) &&
    $isunknown({idex_rs1, idex_rs2}));
  c_itype_x_source: cover property (
    @(posedge clk) disable iff (!rst_n)
    state == CPU_EXECUTE && is_legal_itype(instr) && $isunknown(idex_rs1));
  c_rs1_is_x0: cover property (
    @(posedge clk) disable iff (!rst_n) instr[19:15] == 5'd0);
  c_rs2_is_x0: cover property (
    @(posedge clk) disable iff (!rst_n)
    is_rtype(instr) && instr[24:20] == 5'd0);
  c_rd_is_x0: cover property (
    @(posedge clk) disable iff (!rst_n)
    state == CPU_EXECUTE && is_ri(instr) && instr[11:7] == 5'd0);

  // --- 리셋 동작 ---
  c_reset_asserted: cover property (
    @(posedge clk) !rst_n);
  c_reset_release: cover property (
    @(posedge clk) (!rst_n) ##1 (rst_n));
```

### 예상 결과와 해석

- `c_state_memory`, `c_state_writeback`은 **0회로 찍히는 것이 정상**이다. R/I-type만 자극하므로 이 두 상태에 도달하지 않는다. 이 결과 자체가 "현재 검증범위에서 미도달 상태"를 정량적으로 증명하는 데이터이므로, 검증 보고서에 그대로 기록한다.
- `c_rtype_x_source`, `c_itype_x_source`는 clean 테스트에서 0회, xprop 테스트에서만 히트해야 한다.
- 나머지는 전부 1회 이상 히트해야 한다. 0회면 해당 어설션이 vacuous pass 상태라는 뜻이므로 자극을 보강한다.

### 완료 기준

xsim 로그에서 각 cover property의 히트 카운트를 확인할 수 있고, 위 예상과 일치한다.

> **구현 메모**: Vivado xsim 2020.2는 `cover property`를 파싱하지만
> `[XSIM 43-4127]` 경고와 함께 실행을 무시한다. 표준 property는 향후
> simulator 호환성을 위해 유지하고, 같은 event를 세는 `RV32I_COVER`
> 호환 카운터를 추가했다. Directed 결과는 MEMORY/WRITEBACK과 X-source가
> 0회였고, XPROP 결과는 R-type X-source 4회, I-type X-source 1회였다.

---

## T2. 누락 어설션 추가

**대상**: `rv32i_core_assertions.sv`

### 문제

1. 멀티사이클 설계에서 가장 중요한 불변식인 **"커밋 상태 이전에 PC가 움직이면 안 된다"**를 검증하는 어설션이 없다.
2. EXECUTE 밖에서 `rf_we`가 뜨는 스퓨리어스 쓰기를 잡지 못한다.
3. 불법 인코딩이 유입되면 `is_legal_rtype`/`is_legal_itype` 게이팅 때문에 **모든 제어·결과 어설션이 조용히 스킵**된다. 이 사각지대를 감지할 방법이 없다.

### 구현

기존 어설션들 뒤에 추가한다.

```systemverilog
  // EXECUTE 이전 상태에서는 레지스터 쓰기가 일어나면 안 된다.
  a_no_write_outside_execute: assert property (
    @(posedge clk) disable iff (!rst_n)
      state inside {CPU_FETCH, CPU_DECODE} |-> !rf_we
  ) else $error("RV32I_ASSERT: rf_we asserted outside EXECUTE");

  // 멀티사이클 핵심 불변식: 커밋 상태 전에 PC가 전진하면 명령어와 상태가
  // 어긋나 제어신호가 다음 명령어 기준으로 잘못 생성된다.
  a_pc_stable_before_commit: assert property (
    @(posedge clk) disable iff (!rst_n)
      state inside {CPU_FETCH, CPU_DECODE} |=> $stable(pc)
  ) else $error("RV32I_ASSERT: PC advanced before the committing state");

  // 검증 가정의 명시적 선언.
  // 이 TB는 합법 R/I 인코딩만 자극한다고 가정한다. 불법 인코딩이 EXECUTE에
  // 도달하면 is_legal_* 게이팅 때문에 모든 체크가 vacuous pass 되므로,
  // 사각지대에 빠지기 전에 즉시 보고한다.
  a_assume_legal_encoding: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_EXECUTE && is_ri(instr)
      |-> (is_legal_rtype(instr) || is_legal_itype(instr))
  ) else $error("RV32I_ASSERT: TB assumption violated - illegal R/I encoding reached EXECUTE");
```

### 주의

`a_no_write_outside_execute`는 DUT의 `control_unit`이 `rf_we`를 EXECUTE case에서만 세팅한다는 전제다. 구현 후 기존 테스트가 전부 통과하는지 먼저 확인하고, 실패하면 DUT 쪽 문제일 수 있으므로 보고할 것.

### 완료 기준

3개 어설션 추가 후 기존 회귀 전부 통과.

---

## T3. 참조모델을 10비트 룩업으로 교체 【중요】

**대상**: `rv32i_core_assertions.sv`, `tb_rv32i_uvm.sv`(스코어보드), `rv32_pkg`

### 문제 — 공유된 오해 (shared assumption)

DUT와 두 개의 참조모델이 **완전히 동일한 축약 표현**을 쓰고 있다.

```systemverilog
// DUT: control_unit.sv
alu_control = {instr_code[30], funct3};

// 참조모델 1: tb_rv32i_uvm.sv의 execute_rtype()
3'b000: return instr[30] ? src1 - src2 : src1 + src2;

// 참조모델 2: rv32i_core_assertions.sv의 ref_rtype_alu_control()
3'b000: ref_rtype_alu_control = instruction[30] ? ALU_SUB : ALU_ADD;
```

세 곳 모두 `instr[31:25]` 중 **bit 30 하나만 보고 나머지 6비트를 무시**한다. 이 축약 자체가 스펙과 어긋나는 부분이 있으면 셋이 나란히 틀리고 스코어보드는 영원히 PASS를 찍는다. 외부 골든모델이 없는 환경에서 이 문제를 깨는 가장 저렴한 방법은 **참조모델의 표현 방식을 DUT와 다르게 만드는 것**이다.

### 구현

#### 3-1. `rv32_pkg`에 ALU_ILLEGAL 추가

먼저 `rv32_pkg`의 기존 ALU 인코딩을 확인한다. DUT가 `{instr[30], funct3}`를 쓰므로 다음이 사용 중이다.

```
ADD=4'b0000  SLL=4'b0001  SLT=4'b0010  SLTU=4'b0011
XOR=4'b0100  SRL=4'b0101  OR =4'b0110  AND =4'b0111
SUB=4'b1000  SRA=4'b1101
```

미사용 값 중 `4'b1111`을 `ALU_ILLEGAL`로 추가한다. **기존 값과 충돌하지 않는지 반드시 확인할 것.**

```systemverilog
localparam logic [3:0] ALU_ILLEGAL = 4'b1111;
```

#### 3-2. 어설션 파일에 full-funct7 참조모델 추가

`ref_rtype_alu_control`을 **삭제하지 말고**, 아래를 추가한 뒤 어설션이 새 함수를 쓰도록 교체한다. (기존 함수는 비교/디버깅용으로 남겨둔다.)

```systemverilog
  // RISC-V 스펙 표를 {funct7, funct3} 10비트로 직접 옮긴 참조 디코더.
  // DUT는 bit 30만 보고 나머지 funct7을 무시하므로, 이 함수는 합법
  // 인코딩에서 DUT와 일치하고 불법 인코딩에서만 갈라진다.
  function automatic logic [3:0] ref_rtype_alu_control_full(
    input logic [31:0] instruction
  );
    begin
      case ({instruction[31:25], instruction[14:12]})
        10'b0000000_000: ref_rtype_alu_control_full = ALU_ADD;
        10'b0100000_000: ref_rtype_alu_control_full = ALU_SUB;
        10'b0000000_001: ref_rtype_alu_control_full = ALU_SLL;
        10'b0000000_010: ref_rtype_alu_control_full = ALU_SLT;
        10'b0000000_011: ref_rtype_alu_control_full = ALU_SLTU;
        10'b0000000_100: ref_rtype_alu_control_full = ALU_XOR;
        10'b0000000_101: ref_rtype_alu_control_full = ALU_SRL;
        10'b0100000_101: ref_rtype_alu_control_full = ALU_SRA;
        10'b0000000_110: ref_rtype_alu_control_full = ALU_OR;
        10'b0000000_111: ref_rtype_alu_control_full = ALU_AND;
        default:         ref_rtype_alu_control_full = ALU_ILLEGAL;
      endcase
    end
  endfunction

  // I-type: shift 계열만 funct7 제약이 있다.
  function automatic logic [3:0] ref_itype_alu_control_full(
    input logic [31:0] instruction
  );
    begin
      case (instruction[14:12])
        3'b000: ref_itype_alu_control_full = ALU_ADD;
        3'b010: ref_itype_alu_control_full = ALU_SLT;
        3'b011: ref_itype_alu_control_full = ALU_SLTU;
        3'b100: ref_itype_alu_control_full = ALU_XOR;
        3'b110: ref_itype_alu_control_full = ALU_OR;
        3'b111: ref_itype_alu_control_full = ALU_AND;
        // RV32I: shamt는 5비트이므로 instr[25]는 반드시 0.
        3'b001: ref_itype_alu_control_full =
                  (instruction[31:25] == 7'b0000000) ? ALU_SLL : ALU_ILLEGAL;
        3'b101: ref_itype_alu_control_full =
                  (instruction[31:25] == 7'b0000000) ? ALU_SRL :
                  (instruction[31:25] == 7'b0100000) ? ALU_SRA : ALU_ILLEGAL;
        default: ref_itype_alu_control_full = ALU_ILLEGAL;
      endcase
    end
  endfunction
```

`a_rtype_control` / `a_itype_control` 어설션에서 `ref_rtype_alu_control(instr)` → `ref_rtype_alu_control_full(instr)`로 교체한다.

#### 3-3. 스코어보드 참조모델도 동일 방식으로 교체

`tb_rv32i_uvm.sv`의 `execute_rtype` / `execute_itype`도 같은 원칙을 적용한다. 연산 선택을 10비트 케이스로 먼저 판정하고, 판정 결과에 따라 값을 계산하는 2단 구조로 바꾼다.

```systemverilog
  function automatic logic [31:0] execute_rtype(
    input logic [31:0] instr,
    input logic [31:0] src1,
    input logic [31:0] src2
  );
    case ({instr[31:25], instr[14:12]})
      10'b0000000_000: return src1 + src2;
      10'b0100000_000: return src1 - src2;
      10'b0000000_001: return src1 << src2[4:0];
      10'b0000000_010: return ($signed(src1) < $signed(src2)) ? 32'd1 : 32'd0;
      10'b0000000_011: return (src1 < src2) ? 32'd1 : 32'd0;
      10'b0000000_100: return src1 ^ src2;
      10'b0000000_101: return src1 >> src2[4:0];
      10'b0100000_101: return $signed(src1) >>> src2[4:0];
      10'b0000000_110: return src1 | src2;
      10'b0000000_111: return src1 & src2;
      default: begin
        `uvm_error("SCB_ENCODING",
          $sformatf("Illegal R-type encoding: funct7=%07b funct3=%03b",
                    instr[31:25], instr[14:12]))
        return 32'd0;
      end
    endcase
  endfunction
```

`execute_itype`도 동일하게 shift 계열의 `instr[31:25]` 검사를 추가한다.

> **주의**: `$signed(...) >>> ...`를 삼항연산자 안에 넣으면 피연산자 부호가 unsigned로 강제되는 문제가 있다. 기존 코드에 `[FIX]` 주석으로 이미 `if/else`로 분리해둔 부분이 있으니, **그 수정을 유지**하고 절대 삼항연산자로 되돌리지 말 것.

### 완료 기준

- 기존 directed/random 회귀 전부 통과 (합법 인코딩에서는 결과가 동일해야 함)
- 의도적으로 `funct7=7'b0000001, funct3=3'b000`(M-extension MUL 인코딩) 명령어를 하나 넣었을 때 `SCB_ENCODING` 에러가 발생함을 확인

---

## T4. Directed / Random 테스트 분리 【시간 5배 절약】

**대상**: `tb_rv32i_uvm.sv` (테스트 클래스 섹션)

### 문제

`rv32i_ri_test`가 sanity → boundary → rf_access → operand_profile → random을 **한 테스트 안에서 전부** 실행한다. 앞의 4개는 `$urandom`을 전혀 쓰지 않는 **완전 결정론적 시퀀스**다.

따라서 시드를 20개 돌리면, 결정론적 자극을 20번 그대로 재생하게 된다. `emit_binary_case` 하나가 `load_constant`(7개) × 2 + 타겟 + 리드백 = **16개 명령어**를 만들고, boundary 시퀀스에만 이런 케이스가 150개 이상 있으므로 **시뮬레이션 시간의 대부분이 중복 재생에 소모**된다.

### 구현

기존 `rv32i_ri_test`는 **그대로 두고**(하위호환), 아래 두 테스트를 추가한다.

```systemverilog
// Directed 전용. 완전 결정론적이므로 시드 1개만 실행하면 충분하다.
// 커버리지 게이트(check_phase의 99.99% 강제)는 이 테스트가 책임진다.
class rv32i_ri_directed_test extends uvm_test;
  `uvm_component_utils(rv32i_ri_directed_test)

  rv32i_env                         env;
  rv32i_ri_sanity_sequence          sanity_seq;
  rv32i_ri_boundary_sequence        boundary_seq;
  rv32i_ri_rf_access_sequence       rf_access_seq;
  rv32i_ri_operand_profile_sequence operand_profile_seq;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = rv32i_env::type_id::create("env", this);
    sanity_seq   = rv32i_ri_sanity_sequence::type_id::create("sanity_seq");
    boundary_seq = rv32i_ri_boundary_sequence::type_id::create("boundary_seq");
    rf_access_seq = rv32i_ri_rf_access_sequence::type_id::create("rf_access_seq");
    operand_profile_seq =
      rv32i_ri_operand_profile_sequence::type_id::create("operand_profile_seq");
  endfunction

  // end_of_elaboration_phase는 기존 rv32i_ri_test와 동일하게 복사

  virtual task run_one(rv32i_ri_base_sequence seq);
    seq.start(env.imem_agent.sqr);
    env.scb.wait_for_commits(seq.instruction_count);
  endtask

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    run_one(sanity_seq);
    run_one(boundary_seq);
    run_one(rf_access_seq);
    run_one(operand_profile_seq);
    phase.phase_done.set_drain_time(this, 20ns);
    phase.drop_objection(this);
  endtask
endclass

// Random 전용. 시드를 바꿔가며 다회 실행한다.
class rv32i_ri_random_test extends uvm_test;
  `uvm_component_utils(rv32i_ri_random_test)

  rv32i_env                env;
  rv32i_ri_random_sequence random_seq;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = rv32i_env::type_id::create("env", this);
    random_seq = rv32i_ri_random_sequence::type_id::create("random_seq");
  endfunction

  // end_of_elaboration_phase는 기존 rv32i_ri_test와 동일하게 복사

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    random_seq.start(env.imem_agent.sqr);
    env.scb.wait_for_commits(random_seq.instruction_count);
    phase.phase_done.set_drain_time(this, 20ns);
    phase.drop_objection(this);
  endtask
endclass
```

### 커버리지 게이트 조정 필수

`rv32i_coverage::check_phase`의 강제 에러들은 `scenario_seen[...]` 플래그로 게이팅되어 있으므로, random 전용 테스트에서는 directed 커버그룹 게이트가 자동으로 비활성화된다. **이 동작이 유지되는지 반드시 확인**할 것. random 테스트가 "boundary 커버리지 미달"로 실패하면 안 된다.

### 실행 방법

```bash
# directed: 1회
xsim ... -testplusarg "UVM_TESTNAME=rv32i_ri_directed_test"

# random: 시드 변경하며 N회
xsim ... -testplusarg "UVM_TESTNAME=rv32i_ri_random_test" -sv_seed 1
xsim ... -testplusarg "UVM_TESTNAME=rv32i_ri_random_test" -sv_seed 2
...
```

Vivado 2020.2 Windows wrapper에서는 `=`가 포함된 `-testplusarg` 전달이
불안정하므로 다음 flag-only alias를 제공한다.

```bash
xsim ... -testplusarg RV32I_DIRECTED -sv_seed 1001 -R
xsim ... -testplusarg RV32I_RANDOM   -sv_seed 1001 -R
xsim ... -testplusarg RV32I_XPROP    -sv_seed 1001 -R
xsim ... -testplusarg RV32I_ILLEGAL  -sv_seed 1001 -R  # negative 전용
```

### 완료 기준

두 테스트가 각각 독립적으로 통과하고, directed 테스트에서 기존 커버리지 100%가 그대로 달성된다.

---

## T5. 랜덤 전용 커버그룹 추가 【시드를 의미있게 만드는 핵심】

**대상**: `tb_rv32i_uvm.sv` (`rv32i_coverage` 클래스)

### 문제 1 — 랜덤 오퍼랜드가 커버리지에 안 보인다

`operand_profile_cg`의 모든 coverpoint에 아래 가드가 걸려 있다.

```systemverilog
iff (sample_target && sample_scenario == RI_SCENARIO_OPERAND_PROFILE)
```

즉 **`RI_SCENARIO_RANDOM`에서 나온 1,000개 타겟의 오퍼랜드 값은 커버리지에 한 개도 기록되지 않는다.** 랜덤이 기여하는 건 `instruction_cg`(op/레지스터/alias)뿐인데, 그건 이미 `rf_access_seq`가 결정론적으로 100% 닫아놓았다.

### 문제 2 — 조합 공간이 비어 있다

| 자극 | 경계값 | alias(rd==rs1 등) | dependency | 3개 동시 |
|---|---|---|---|---|
| boundary_seq | O | X (rs1=1,rs2=2,rd=3 고정) | X | **X** |
| rf_access_seq | X (작은 값) | O | O | **X** |
| random_seq | 15%만 | 15%만 | 25%만 | 거의 없음 |

버그는 단일 축이 아니라 조합에서 나온다. "`0x80000000`을 `SRA`하는데 동시에 `rd==rs1`이고 직전 명령어가 그 레지스터를 썼을 때" 같은 3중 조합을 만드는 시퀀스가 **하나도 없다**.

### 구현

`rv32i_coverage` 클래스에 새 커버그룹을 추가한다. 기존 커버그룹은 **수정하지 않는다**(단, `operand_profile_cg`의 시나리오 가드는 아래 별도 지시 참조).

```systemverilog
  // 랜덤 자극 전용. directed로는 현실적으로 닫히지 않는 조합 공간을 측정한다.
  // 시드를 늘렸을 때 커버리지가 실제로 올라가는지 확인하는 지표 역할.
  covergroup random_combo_cg;
    option.per_instance = 1;

    cp_r_op: coverpoint sample_op
      iff (sample_target && sample_scenario == RI_SCENARIO_RANDOM &&
           sample_is_r) {
      bins operations[] = {[RI_ADD:RI_AND]};
    }
    cp_i_op: coverpoint sample_op
      iff (sample_target && sample_scenario == RI_SCENARIO_RANDOM &&
           sample_is_i) {
      bins operations[] = {[RI_ADDI:RI_SRAI]};
    }
    cp_src1: coverpoint sample_src_class
      iff (sample_target && sample_scenario == RI_SCENARIO_RANDOM) {
      bins classes[] = {[RI_VAL_ZERO:RI_VAL_NEG_OTHER]};
    }
    cp_src2: coverpoint sample_src2_class
      iff (sample_target && sample_scenario == RI_SCENARIO_RANDOM &&
           sample_is_r) {
      bins classes[] = {[RI_VAL_ZERO:RI_VAL_NEG_OTHER]};
    }
    cp_alias: coverpoint sample_alias
      iff (sample_target && sample_scenario == RI_SCENARIO_RANDOM &&
           sample_is_r) {
      bins all_different = {RI_ALIAS_ALL_DIFFERENT};
      bins rd_rs1        = {RI_ALIAS_RD_RS1};
      bins rd_rs2        = {RI_ALIAS_RD_RS2};
      bins rs1_rs2       = {RI_ALIAS_RS1_RS2};
      bins all_equal     = {RI_ALIAS_ALL_EQUAL};
    }
    cp_dep: coverpoint sample_dependency
      iff (sample_target && sample_scenario == RI_SCENARIO_RANDOM) {
      bins none = {RI_DEP_NONE};
      bins rs1  = {RI_DEP_RS1};
      bins rs2  = {RI_DEP_RS2};
      bins both = {RI_DEP_BOTH};
    }

    // 2-way: 비교적 빨리 닫힘 (시드 5~10개 수준)
    cx_r_op_alias:  cross cp_r_op, cp_alias;     // 10 x 5  = 50
    cx_r_op_dep:    cross cp_r_op, cp_dep;       // 10 x 4  = 40
    cx_i_op_src1:   cross cp_i_op, cp_src1;      //  9 x 9  = 81

    // 3-way: directed로 닫는 것이 비현실적. 시드 투자 효과의 주 지표.
    cx_r_op_src_alias: cross cp_r_op, cp_src1, cp_alias;   // 10 x 9 x 5 = 450
    cx_r_src_pair_dep: cross cp_src1, cp_src2, cp_dep;     //  9 x 9 x 4 = 324
  endgroup
```

생성자에 추가:
```systemverilog
    random_combo_cg = new();
```

`write_commit` 끝부분의 샘플링 호출에 추가:
```systemverilog
    random_combo_cg.sample();
```

### 중대 주의사항 — 커버리지 게이트에 절대 넣지 말 것

`check_phase`의 99.99% 강제 에러 목록에 **`random_combo_cg`를 추가하면 안 된다.** 3-way cross는 시드 몇 개로 절대 100%가 안 되므로, 게이트에 넣으면 모든 런이 실패한다. **report_phase에서 숫자만 출력**한다.

```systemverilog
    // report_phase에 추가 (게이트 아님, 관측용)
    if (scenario_seen[int'(RI_SCENARIO_RANDOM)])
      `uvm_info("COV_SUMMARY", $sformatf(
        "random_combo_cg: %6.2f%%  <- 시드 누적 지표 (게이트 아님)",
        random_combo_cg.get_inst_coverage()), UVM_LOW)
```

### operand_profile_cg 가드 완화

`operand_profile_cg`의 `sample_scenario == RI_SCENARIO_OPERAND_PROFILE` 조건을 **제거하여 랜덤 시나리오도 기여하게 한다.** 단, 이 커버그룹은 여전히 directed 게이트 대상이므로, **가드 제거 후 directed 테스트에서 100%가 유지되는지 반드시 재확인**할 것. (bin이 넓어지는 게 아니라 샘플 소스만 늘어나는 것이므로 100% 유지가 정상이다.)

### 완료 기준

- directed 테스트: 기존 게이트 커버그룹 전부 100% 유지
- random 테스트: 시드 1개 → 5개 → 20개로 늘릴 때 `random_combo_cg` 수치가 **단조 증가**하는 것을 확인. 증가하지 않으면 T6이 제대로 안 된 것이다.

---

## T6. 랜덤 자극 분포 확대

**대상**: `tb_rv32i_uvm.sv` (`rv32i_ri_base_sequence`, `rv32i_ri_random_sequence`)

### 문제

```systemverilog
function void initialize_all_registers(input ri_scenario_e scenario);
  for (int i = 1; i < 32; i++)
    emit_raw(encode_i(i * 37, 0, 3'b000, i[4:0]), ...);
endfunction
```

모든 레지스터가 `i*37`(37 ~ 1147)로 초기화된다. **전부 작은 양수**다. 경계값 주입은 `boundary_rate = 15`로 15%뿐이므로, **랜덤 연산의 85%가 작은 양수끼리의 연산**이고 부호 경계 근처를 거의 탐색하지 못한다. T5의 3-way cross가 이 상태로는 절대 안 채워진다.

### 구현

#### 6-1. 혼합 초기화 함수 추가

`rv32i_ri_base_sequence`에 추가한다. **기존 `initialize_all_registers`는 삭제하지 않는다** (directed 시퀀스가 쓰고 있음).

```systemverilog
  // 랜덤 시나리오 전용 초기화.
  // 레지스터의 절반을 경계값으로 채워, 이후 랜덤 연산이 부호 경계와
  // 특수 비트패턴 근처를 자연스럽게 탐색하게 만든다.
  function void initialize_mixed_registers(input ri_scenario_e scenario);
    bit [31:0] seeds[0:7];
    seeds = '{32'h0000_0000, 32'h0000_0001, 32'hffff_ffff, 32'h7fff_ffff,
              32'h8000_0000, 32'haaaa_aaaa, 32'h5555_5555, 32'h0000_001f};

    // x1~x15: 경계값 (load_constant는 명령어 7개를 소모하므로 절반만)
    for (int i = 1; i < 16; i++)
      load_constant(i[4:0], seeds[i % 8], scenario,
                    $sformatf("MIX_X%0d", i));

    // x16~x31: 일반 값 (기존 방식, 명령어 1개)
    for (int i = 16; i < 32; i++)
      emit_raw(encode_i(i * 37, 0, 3'b000, i[4:0]),
               RI_SETUP, scenario, $sformatf("MIX_X%0d", i));
  endfunction
```

#### 6-2. 랜덤 시퀀스 파라미터 조정

```systemverilog
class rv32i_ri_random_sequence extends rv32i_ri_base_sequence;
  int unsigned balanced_per_operation = 20;
  int unsigned free_random_count      = 620;
  int unsigned dependency_rate        = 35;   // 25 -> 35
  int unsigned alias_rate             = 30;   // 15 -> 30
  int unsigned boundary_rate          = 40;   // 15 -> 40
  int unsigned readback_rate          = 10;
```

`body()`의 `initialize_all_registers(RI_SCENARIO_RANDOM)`를
`initialize_mixed_registers(RI_SCENARIO_RANDOM)`으로 교체한다.

#### 6-3. (선택) `randomize()` 기반으로 전환

현재는 `$urandom_range`를 손으로 호출하는 구조라 제약 솔버를 못 쓴다. 여력이 있으면 클래스 랜덤화로 전환한다.

```systemverilog
class ri_random_knobs extends uvm_object;
  `uvm_object_utils(ri_random_knobs)

  rand bit [4:0]      rs1, rs2, rd, shamt;
  rand int signed     immediate;
  rand ri_operation_e op;

  constraint c_op_range { op inside {[RI_ADD:RI_SRAI]}; }
  constraint c_imm_range { immediate inside {[-2048:2047]}; }

  // 경계 immediate가 충분히 자주 나오도록 분포를 가중한다.
  constraint c_imm_dist {
    immediate dist { -2048 := 5, -2047 := 3, -1 := 5, 0 := 5,
                      1 := 5, 2046 := 3, 2047 := 5,
                      [-2046:-2] :/ 35, [2:2045] :/ 35 };
  }

  // alias 조합이 자연스럽게 나오도록 rd 분포를 가중한다.
  constraint c_alias_dist {
    rd dist { rs1 := 15, rs2 := 15, [0:31] :/ 70 };
  }

  function new(string name = "ri_random_knobs");
    super.new(name);
  endfunction
endclass
```

`emit_random_target`에서 이 객체를 `randomize()`하여 값을 얻도록 바꾼다.

> **주의**: `shamt`는 반드시 `bit [4:0]`로 유지한다. RV32I에서 shamt는 5비트이고, 6비트 이상이면 불법 인코딩이 되어 T2의 `a_assume_legal_encoding`에 걸린다.

### 완료 기준

시드 20개 실행 시 `random_combo_cg`의 `cx_r_op_src_alias`가 **60% 이상** 도달. 미달이면 `boundary_rate`/`alias_rate`를 더 올린다.

---

## T7. x0 간접 리드백 케이스 추가

**대상**: `tb_rv32i_uvm.sv` (`rv32i_ri_sanity_sequence`)

### 문제

현재 x0 목적지 테스트는 이렇게 되어 있다.

```systemverilog
emit_target_with_readback(RI_ADDI, 1, 0, 0, 123, 0, ..., "SANITY_X0_DESTINATION");
// -> ADDI x0, x1, 123  후에  ADDI x0, x0, 0 (리드백)
```

**리드백이 x0 자신을 읽는다.** DUT의 레지스터 파일은 읽기 경로에서 `(ra1 != 0) ? reg_file[ra1] : 32'd0`로 0을 강제하므로, 설령 `reg_file[0]`이 오염되어도 **아키텍처적으로 보이지 않는다.** 즉 이 테스트는 x0 보호를 실제로 검증하지 못한다.

### 구현

x0를 **다른 레지스터로 복사한 뒤 그 레지스터를 확인**하는 방식으로 바꾼다.

```systemverilog
    // x0 목적지: 쓰기가 버려지는지를 간접 경로로 확인한다.
    // x0를 직접 리드백하면 읽기 MUX가 0을 강제하므로 오염을 감지할 수 없다.
    emit_operation(RI_ADDI, 1, 0, 0, 123, 0, RI_TARGET,
                   RI_SCENARIO_SANITY, "SANITY_X0_WRITE_ATTEMPT");
    emit_target_with_readback(RI_ADDI, 0, 0, 24, 0, 0,
                              RI_SCENARIO_SANITY, "SANITY_X0_COPY_CHECK");
    // ADDI x24, x0, 0  ->  x24가 0이어야 통과

    // R-type 경로로도 동일 확인 (rs2 읽기 포트 검증)
    emit_operation(RI_ADD, 1, 0, 0, 0, 0, RI_TARGET,
                   RI_SCENARIO_SANITY, "SANITY_X0_WRITE_ATTEMPT_R");
    emit_target_with_readback(RI_ADD, 0, 0, 25, 0, 0,
                              RI_SCENARIO_SANITY, "SANITY_X0_COPY_CHECK_R");
```

### 참고

현재 DUT는 `logic [31:0] reg_file [1:31]`로 인덱스 0이 아예 없어 배열범위 밖 쓰기가 버려지고, 추가로 읽기 MUX가 0을 강제하는 **이중 보호** 구조다. 따라서 이 테스트는 현재 DUT에서 통과한다. 그럼에도 추가하는 이유는, 나중에 `reg_file`을 `[0:31]`로 바꾸거나 읽기 MUX를 제거하는 리팩터링이 들어왔을 때 **회귀를 잡기 위해서**다.

### 완료 기준

sanity 테스트 통과. `planned_case`/`hit_case`에 새 case_id가 등록되고 히트된다.

---

## T8. rd_we 항등식 체크 수정

**대상**: `tb_rv32i_uvm.sv` (`rv32i_scoreboard::write_commit`)

### 문제 — 현재 체크는 항등식이라 절대 실패하지 않는다

프로브가 raw 신호를 그대로 넘기는 게 아니라 **가공**하고 있다.

```systemverilog
// rv32i_core_probe.sv:52
assign probe_if.commit_rd_we = probe_if.commit_valid &&
                               rf_we && (instr[11:7] != 5'd0);
```

스코어보드는:
```systemverilog
expected_we = (rd != 5'd0);
if (actual.rd_we !== expected_we) `uvm_error(...)
```

`commit_valid`는 EXECUTE + R/I일 때만 1이고, 그 시점에 DUT의 `rf_we`는 항상 1이다(`a_rtype_control`/`a_itype_control`이 보장). 따라서:

```
actual.rd_we = 1 && 1 && (rd != 0) = (rd != 0)
expected_we  = (rd != 0)
→ (rd != 0) !== (rd != 0) → 항상 거짓 → 절대 실패하지 않음
```

**TB가 자기가 만든 값을 자기가 확인하는 구조**다.

### 구현

`rv32i_commit_item`에 이미 raw `rf_we`가 캡처되어 있다(`tr.rf_we = vif.mon_cb.rf_we`). **프로브는 수정하지 않고** 스코어보드에서 raw 신호를 별도로 검증한다.

기존 `rd_we` 체크는 유지하되(파생신호 정합성 확인 의미는 있음), 아래 체크를 **추가**한다.

```systemverilog
    // DUT의 raw rf_we 검증.
    // 이 설계는 x0 보호를 rf_we가 아니라 레지스터파일 읽기 MUX에서
    // 수행하므로, R/I 커밋 시점의 rf_we는 rd 값과 무관하게 항상 1이어야 한다.
    // (x0 쓰기가 실제로 버려지는지는 T7의 간접 리드백이 검증한다.)
    if (actual.rf_we !== 1'b1)
    begin
      transaction_pass = 1'b0;
      `uvm_error("SCB_RAW_WE", $sformatf(
        "Commit %0d: raw rf_we must be 1 for committed R/I (rd=x%0d), got %b",
        commit_count, rd, actual.rf_we))
    end
```

### 완료 기준

기존 회귀 전부 통과. `rd=x0`인 케이스(`SANITY_X0_*`)에서도 이 체크가 통과해야 한다 — 실패하면 DUT의 `rf_we` 동작이 예상과 다른 것이므로 보고할 것.

---

## T9. 시드 누적 커버리지 덤프

**대상**: `tb_rv32i_uvm.sv` (`rv32i_coverage`)

### 문제

`check_phase`의 99.99% 게이트는 **매 시드마다 동일하게 판정**된다. directed가 결정론적이므로 시드를 바꿔도 결과가 같다. 시드 투자의 효과를 보려면 **여러 런의 커버리지를 합산**해야 하는데, VCS `urg`를 못 쓰는 환경이다.

### 해결책 — 기존 메커니즘 재활용

이미 `planned_case` / `hit_case`라는 문자열 키 associative array 기반 자체 커버리지 추적기가 있다. **시뮬레이터 커버리지 라이선스가 전혀 필요 없는 방식**이므로 이걸 확장한다.

### 구현

#### 9-1. 랜덤 조합 키를 hit_case에 기록

`write_commit`의 샘플링 직전에 추가한다.

```systemverilog
    // 랜덤 시나리오의 조합을 문자열 키로 기록한다.
    // 시뮬레이터 커버리지 머지 기능 없이 시드 간 누적 집계를 가능하게 한다.
    if (sample_target && sample_scenario == RI_SCENARIO_RANDOM)
    begin
      string combo_key;
      if (sample_is_r)
        combo_key = $sformatf("COMBO_R_%0d_%0d_%0d_%0d",
                              sample_op, sample_src_class,
                              sample_alias, sample_dependency);
      else
        combo_key = $sformatf("COMBO_I_%0d_%0d_%0d",
                              sample_op, sample_src_class, sample_dependency);
      hit_case[combo_key] = 1'b1;
    end
```

> `planned_case`에는 넣지 않는다. `check_phase`가 planned이지만 미히트인 케이스를 에러로 잡기 때문에, 랜덤 조합을 planned로 등록하면 전부 실패한다.

#### 9-2. 히트 조합을 파일에 append

`report_phase` 끝부분에 추가한다.

```systemverilog
    // 시드별 히트 조합을 append하여, 외부에서 `sort -u | wc -l`로
    // 누적 커버리지를 집계할 수 있게 한다.
    begin
      int dump_fd;
      dump_fd = $fopen("cov_combo_dump.txt", "a");
      if (dump_fd != 0)
      begin
        foreach (hit_case[id])
          if (hit_case[id]) $fdisplay(dump_fd, "%s", id);
        $fclose(dump_fd);
      end
    end
```

### 집계 방법

```bash
# 시드 20개 실행 후
sort -u cov_combo_dump.txt | grep '^COMBO_R_' | wc -l   # R-type 조합 누적
sort -u cov_combo_dump.txt | grep '^COMBO_I_' | wc -l   # I-type 조합 누적

# 시드 수 대비 증가 곡선 확인 (5개, 10개, 20개 시점에서 각각 측정)
```

이론상 최대값은 R-type이 10(op) × 9(src class) × 5(alias) × 4(dep) = 1,800, I-type이 9 × 9 × 4 = 324다. 시드를 늘렸을 때 이 수치가 **포화(saturate)되는 지점**이 "더 이상 시드를 늘려도 얻는 게 없는 지점"이다.

### 완료 기준

시드 5/10/20개 실행 후 누적 조합 수가 각각 증가하고, 증가폭이 점차 줄어드는 포화 곡선을 관측할 수 있다.

---

## T10. 【선택】 불법 인코딩 negative 테스트

**대상**: `tb_rv32i_uvm.sv` (새 시퀀스 + 새 테스트)

> T1~T9를 먼저 완료하고, 여유가 있을 때만 착수한다.

### 배경 — 왜 필요한가

현재 검증범위는 "합법 R/I 인코딩"으로 한정되어 있고, 이는 정당한 스코핑이다. 다만 **DUT가 예약 비트를 무시한다는 사실을 문서화된 형태로 증명**해두면, 나중에 M-extension을 붙일 때 디코더 충돌로 시간을 낭비하는 걸 막을 수 있다.

DUT는 `alu_control = {instr[30], funct3}`로 `instr[31:25]` 중 bit 30만 본다. 따라서:

| 인코딩 | 스펙상 | 현재 DUT 동작 |
|---|---|---|
| `funct7=0000001, funct3=000` (M-ext MUL) | illegal (M 없으면) | **ADD로 실행** |
| `funct7=0100000, funct3=100` (XOR에 alt bit) | illegal | `alu_control=4'b1100` → ALU default → 0 |
| `SLLI`에 `instr[25]=1` | RV32I illegal (RV64 shamt[5]) | **정상 SLLI로 실행** |

### 구현 방침

이건 "버그를 잡는" 테스트가 아니라 **"현재 동작을 고정(pin down)하는"** 테스트다. 스코어보드가 에러를 내는 게 정상이므로, 별도 테스트로 분리하고 결과를 문서에 기록한다.

```systemverilog
class rv32i_ri_illegal_sequence extends rv32i_ri_base_sequence;
  `uvm_object_utils(rv32i_ri_illegal_sequence)

  function new(string name = "rv32i_ri_illegal_sequence");
    super.new(name);
  endfunction

  virtual task body();
    begin_program();
    load_constant(1, 32'h0000_000a, RI_SCENARIO_SANITY, "ILL_SRC1");
    load_constant(2, 32'h0000_0003, RI_SCENARIO_SANITY, "ILL_SRC2");

    // funct7=0000001 : M-extension MUL 인코딩
    emit_raw({7'b0000001, 5'd2, 5'd1, 3'b000, 5'd10, OP_RTYPE},
             RI_TARGET, RI_SCENARIO_SANITY, "ILLEGAL_MUL_ENCODING");

    // funct7=0100000 + funct3=100 : XOR에 존재하지 않는 alt bit
    emit_raw({7'b0100000, 5'd2, 5'd1, 3'b100, 5'd11, OP_RTYPE},
             RI_TARGET, RI_SCENARIO_SANITY, "ILLEGAL_XOR_ALT");

    // SLLI에 instr[25]=1 : RV64의 shamt[5], RV32I에서는 불법
    emit_raw({7'b0000001, 5'd4, 5'd1, 3'b001, 5'd12, OP_ITYPE},
             RI_TARGET, RI_SCENARIO_SANITY, "ILLEGAL_SLLI_SHAMT5");

    end_program();
  endtask
endclass
```

### 기대 결과

- T2의 `a_assume_legal_encoding` 어설션이 **발화한다** (정상)
- T3의 스코어보드 `SCB_ENCODING` 에러가 **발생한다** (정상)
- 시뮬레이션이 hang하거나 X가 제어경로로 전파되지 **않아야 한다** (이건 진짜 확인 대상)

### 문서화

실행 결과를 검증 보고서에 다음 형식으로 기록한다.

```
[설계 결정] 본 코어는 트랩 메커니즘이 없으므로 불법 R/I 인코딩에 대해
illegal-instruction 예외를 발생시키지 않는다. 디코더는 instr[30]만
참조하며 나머지 funct7 비트를 무시한다.
- funct7=0000001(MUL) → ADD로 실행됨을 확인
- SLLI instr[25]=1     → 정상 SLLI로 실행됨을 확인
M-extension 추가 시 디코더 확장이 선행되어야 한다.
```

---

## 완료 체크리스트

```
[x] T1  cover property + xsim 2020.2 호환 카운터 — MEMORY/WRITEBACK 0회 확인
[x] T2  누락 어설션 3개 추가 — clean/XPROP 회귀 통과
[x] T3  10비트 룩업 참조모델 — 합법 인코딩 결과 동일, ALU_ILLEGAL 충돌 없음
[x] T4  테스트 분리 — directed 1회 + random N회 독립 실행 및 script 반영
[x] T5  random_combo_cg 추가 — 관측용이며 gate 제외 확인
[x] T6  랜덤 분포 확대 — seed 1001~1020 누적 cx_r_op_src_alias 100%
[x] T7  x0 간접 리드백 — sanity 통과, directed case 1,137/1,137
[x] T8  raw rf_we 체크 추가 — rd=x0 포함 회귀 통과
[x] T9  조합 덤프 — R 1,211/1,800, I 162/324 unique key 누적
[x] T10 (선택) 불법 인코딩 — SCB_ENCODING 3회/legality assertion 3회, hang 없음
```

## 최종 회귀 확인

모든 작업 후 아래를 순서대로 실행하여 통과를 확인한다.

```bash
# 컴파일/elaboration + directed 1회 + random 20회 + XPROP 1회
./Scripts/sim.sh -f Scripts/filelist_tb_rv32i_uvm.f -top tb_rv32i_uvm -uvm

# 누적 집계 (실행 디렉터리: Vivado/tb_rv32i_uvm)
sort -u cov_combo_dump.txt | grep '^COMBO_R_' | wc -l
sort -u cov_combo_dump.txt | grep '^COMBO_I_' | wc -l
```

세 테스트 모두 `UVM_ERROR: 0`, `UVM_FATAL: 0`이어야 한다.

최종 실행 결과: `DIRECTED:PASS RANDOM_PASS:20 RANDOM_FAIL:0 XPROP:PASS`.
T10 illegal 테스트는 의도적으로 error를 기대하므로 clean 회귀에 포함하지 않는다.
