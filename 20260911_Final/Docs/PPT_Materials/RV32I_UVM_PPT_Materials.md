# RV32I UVM 발표 자료

FIFO UVM 발표 자료의 흐름과 표 형식을 RV32I CPU core-only R/I 검증에 맞게 옮긴 문서다. PPT 파일 자체를 수정하지 않고, 각 슬라이드에 넣을 제목·표·설명과 draw.io 원본을 제공한다.

## 공통 디자인 가이드

- 화면비: 16:9
- 배경: 흰색
- 제목: 좌측 정렬, 검정, 굵게
- 제목 아래 구분선: 파란색 `#2F75B5`
- 표 헤더: 파란색 `#5B9BD5`, 흰색 굵은 글씨
- 표 본문: 흰색, 검정 테두리
- UVM 데이터 흐름: 파랑, monitor 흐름: 초록, scoreboard: 주황, coverage: 하늘색
- 한글과 영문 용어를 함께 쓸 때 signal/class 이름은 코드 표기를 유지한다.
- TSV는 PowerPoint에서 같은 행·열 수의 빈 표를 만든 뒤 전체 셀을 선택해 붙여넣는 용도다.

## 슬라이드 1. 표지

```text
RV32I UVM Verification
CPU Core-only / Legal R-type & I-type
2026.09
```

## 슬라이드 2. RV32I CPU Core

삽입 자료:

- `../Block_Diagram/RV32I_General_Block_Diagram.drawio`

발표 문장:

> 검증 대상은 `rv32i_cpu` 코어이며 instruction ROM과 APB 주변장치는 제외했다. R/I 명령에서는 instruction interface로 명령을 공급하고, control unit과 datapath의 실행 결과가 register file에 저장되는 경로를 검증한다.

## 슬라이드 3. 검증 대상 및 목표

| 구분 | 내용 |
|---|---|
| 검증 대상 | `rv32i_cpu`의 control unit, datapath, register file, ALU |
| 명령 범위 | legal RV32I R-type 10개, I-type 9개 |
| R-type | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND |
| I-type | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI |
| 주요 목표 | 연산 결과, PC 증가, decode/control, register write/readback, x0 불변 |
| 경계 검증 | signed overflow, unsigned carry/borrow, compare 관계, immediate/shamt 경계 |
| 조합 검증 | register 주소, alias, dependency/gap, operand class pairwise + random 3-way |
| 강건성 | known control 유지, source X의 ALU/write-back 전파, known overwrite 회복 |
| 제외 범위 | branch/jump, load/store, APB requester/RAM, ROM 자체, exception 처리 |
| 검증 방법 | UVM scoreboard + functional coverage + bind SVA + directed 1회/random 20-seed |

발표 문장:

> 전체 CPU 명령을 넓게 훑는 것이 아니라, legal R/I 명령의 실행과 register-file 반영을 깊게 확인하는 것이 이번 검증 범위다.

## 슬라이드 4. UVM 구조

삽입 자료:

- `../Block_Diagram/RV32I_UVM_Block_Diagram.drawio`
- `../Block_Diagram/RV32I_UVM_Hierarchy.drawio`

발표 문장:

> 하나의 active IMEM agent가 program을 공급하고, bind된 passive probe가 실제 commit을 관측한다. Driver가 보낸 원본 program metadata와 monitor가 관측한 commit을 scoreboard와 coverage가 각각 사용한다.

## 슬라이드 5. 인터페이스와 SVA

### Interface

| 신호 | 방향 | 요약 |
|---|---|---|
| `clk` | TB → DUT | CPU 동작 기준 clock |
| `rst_n` | IMEM driver/core_if → DUT | PC, FSM, datapath register 초기화 |
| `instr_code[31:0]` | core_if IMEM → DUT | 현재 PC에 해당하는 R/I instruction 공급 |
| `instr_addr[31:0]` | DUT → core_if/Monitor | instruction fetch address와 PC 정렬 확인 |
| `ready` | core_if → DUT | R/I test에서는 known idle 값 유지 |
| `bus_rdata[31:0]` | core_if → DUT | R/I test에서는 known idle 값 유지 |
| `transfer / bus_we` | DUT → Monitor | R/I 실행 중 data-bus access가 없음을 확인 |
| `itype / bus_addr / bus_wdata` | DUT → Monitor | core port 관측, 현재 R/I 기능 범위에서는 비활성 경로 |

### SVA

| Assertion 그룹 | 대표 Property | 확인 내용 |
|---|---|---|
| Reset/State | `a_reset_state`, `a_state_known`, `a_state_legal` | reset 후 FETCH/PC=0, FSM known/legal 확인 |
| State transition | `a_fetch_to_decode`, `a_decode_to_execute`, `a_ri_execute_to_fetch` | R/I의 FETCH→DECODE→EXECUTE→FETCH 순서 확인 |
| Commit invariant | `a_no_write_outside_execute`, `a_pc_stable_before_commit` | EXECUTE 밖 write 금지와 commit 이전 PC 안정성 확인 |
| PC/Instruction | `a_pc_aligned`, `a_fetch_signals_stable`, `a_instruction_known` | PC 정렬 및 fetch/decode 안정성 확인 |
| Operand capture | `a_itype_immediate`, `a_rs1_capture`, `a_rs2_capture` | immediate와 register operand의 ID/EX capture 확인 |
| x0 | `a_rs1_x0`, `a_rs2_x0` | x0 read 값이 항상 0인지 확인 |
| Decode control | `a_rtype_control`, `a_itype_control` | ALU control, source select, write-enable 확인 |
| Encoding legality | `a_assume_legal_encoding` | illegal R/I가 legality-gated 검사를 우회하지 못하게 검출 |
| Execute/WB | `a_rtype_execute`, `a_itype_execute` | independent reference 결과와 ALU/write-back 비교 |
| X propagation | `a_rtype_x_result_propagates`, `a_itype_x_result_propagates` | source X가 ALU result와 WB data까지 전달되는지 확인 |
| R/I side effect | `a_ri_pc_increment`, `a_ri_no_bus_access` | PC+4 및 data-bus access 금지 확인 |
| Reachability | `c_state_*`, `c_trans_*`, `c_*_executed` | FSM/antecedent 도달성; xsim 2020.2는 호환 카운터로 집계 |

## 슬라이드 6. Core/Probe Interface 구조

| 구조 | Timing | 역할 |
|---|---|---|
| `rv32i_core_if` | combinational IMEM + driver-controlled reset | instruction memory model과 DUT 외부 입력 제공 |
| `rv32i_probe_if.mon_cb` | `@(posedge clk)`, input `#1step` | register-file write edge 직전 execute/commit 값 sample |
| `commit_valid` | R/I opcode의 `CPU_EXECUTE` | scoreboard/coverage가 처리할 instruction 경계 표시; illegal negative도 관측 |
| Architectural probe | PC, instruction, rd_we, raw rf_we, rd, rd_data | commit 정렬과 파생/raw write-enable 비교 |
| Operand probe | rs1/rs2 address, ID/EX operands, immediate | 실제 ALU 입력과 reference operand 비교 |
| Control/result probe | control signals, alu_result, wb_data | decode, ALU 결과, write-back 선택과 X 전파 확인 |
| Bus probe | transfer, bus_we, address/data | R/I 명령의 예상하지 않은 bus side effect 검출 |

발표 문장:

> Monitor는 판정하지 않고 edge 직전의 실제 값을 commit item으로 전달한다. pass/fail 판단은 scoreboard와 assertion이 담당한다.

## 슬라이드 7. Single Active Agent + Passive Probe

간략 흐름:

```text
Scenario sequence
      ↓
rv32i_program_item
      ↓
IMEM sequencer → IMEM driver → rv32i_core_if + DUT
                                      ↓ bind
                                Probe monitor
                                      ↓
                              rv32i_commit_item
                                ↙           ↘
                         Scoreboard       Coverage
```

표기 권장:

| 블록 | 색상 | 핵심 설명 |
|---|---|---|
| Sequence/Driver | 파랑 | original program 생성 및 IMEM drive |
| core_if + DUT | 노랑 | instruction 공급과 R/I execution |
| Probe Monitor | 초록 | bind signal을 passive sample |
| Scoreboard | 주황 | independent ISA/GPR model 비교 |
| Coverage | 하늘색 | intent-aware coverage와 planned-case closure |
| SVA | 빨강 | state/control/datapath property 검사 |

## 슬라이드 8. Sequence와 Item

### Item

| Item | 주요 field | 사용 목적 |
|---|---|---|
| `rv32i_program_item` | `instructions`, `roles`, `scenarios`, `case_ids` | driver에 program 전달, scoreboard/coverage에 검증 의도 전달 |
| `rv32i_commit_item` | PC, instruction, rd_we/raw rf_we, rd/data | architectural commit 정렬과 register write 비교 |
| `rv32i_commit_item` | rs1/rs2, actual operands, immediate | independent R/I reference result 계산 |
| `rv32i_commit_item` | control, ALU result, WB data, bus activity | control/SVA/X propagation 및 side-effect 확인 |

### Sequence

| Sequence | Stimulus | 검증 목적 |
|---|---|---|
| `sanity_seq` | legal R/I 19개 + x0 source/간접 copy | 기본 동작과 x0 write-discard의 I/R 경로 확인 |
| `boundary_seq` | 경계값과 경계 인접값 | overflow/carry/borrow, compare, logic, immediate, shift 확인 |
| `rf_access_seq` | x0~x31 주소 rotation + alias/dependency | rs1/rs2/rd 전 주소와 실제 register 저장 확인 |
| `operand_profile_seq` | 대표 value class 회전 조합, TARGET 171개 | 값 공간 pairwise closure, 3-way Cartesian 폭증 방지 |
| `random_seq` | mixed 초기화 + balanced 380 + free random 620 | 35% dependency, 30% alias, 40% boundary로 3-way 조합 탐색 |
| `xprop_seq` | uninitialized source, reuse, overwrite/recovery | source X 전파와 known 상태 회복 확인 |
| `illegal_seq` | MUL/reserved XOR/illegal SLLI encoding | 별도 negative test에서 legality 및 full-funct7 검출 확인 |

하단 설명:

```text
SETUP    : operand/register 상태 준비, TARGET coverage 제외
TARGET   : 현재 scenario의 실제 검증 명령
READBACK : destination을 다시 읽어 register-file 저장 확인
XPROP    : 의도적으로 X source/result를 사용하는 명령
```

## 슬라이드 9. Monitor와 Commit Sampling

| 구간 | 동작 | 의미 |
|---|---|---|
| Program publish | driver가 program과 metadata 전송 | scoreboard/coverage가 원본 expected stream 확보 |
| Execute edge 직전 | `mon_cb` input `#1step`으로 sample | register-file에 쓰일 ALU/WB 값을 write edge 전에 관측 |
| Commit filter | reset 또는 `commit_valid`일 때 item 생성 | R/I opcode commit을 전달하여 illegal negative도 검출 가능 |
| Architectural sample | PC/instruction/rd_we/rd/rd_data | 실행 순서, PC, destination, 실제 write data 확인 |
| Internal sample | operands/immediate/control/ALU/WB | decode와 datapath 내부 경로를 독립 reference/SVA로 확인 |
| Alignment | metadata queue의 동일 index와 결합 | SETUP/READBACK이 TARGET coverage를 채우는 오염 방지 |

발표 문장:

> Monitor는 결과를 추정하지 않는다. 관측값만 전달하고, program role과 scenario는 driver metadata를 통해 coverage 단계에서 결합한다.

## 슬라이드 10. Scoreboard

삽입 자료:

- `../Block_Diagram/RV32I_Scoreboard_Flow.drawio`

| 단계 | 동작 | 검증 의미 |
|---|---|---|
| Input | program item과 commit item 수신 | original expected stream과 actual commit 분리 |
| Alignment | expected PC/instruction와 actual 비교 | instruction 누락, 중복, 순서 오류 검출 |
| Source | `ref_gpr/ref_valid`에서 source 계산 | DUT register read 결과에 의존하지 않는 reference 구성 |
| Execute | semantic R/I operation으로 expected result 계산 | ADD/SUB, shift, compare, logic 결과 확인 |
| Write-back | rd_we + raw rf_we, rd/data와 x0 규칙 비교 | 파생 신호 항등식과 DUT write control을 분리 검증 |
| READBACK | destination을 후속 명령의 source로 재관측 | 내부 register-file 저장 결과 확인 |
| X policy | X source는 validity를 taint, known overwrite로 회복 | 임의의 2-state expected 비교 없이 X 흐름 관리 |
| Result | scenario별 PASS/FAIL/SKIP/TOTAL | 실패 위치와 data skip을 분리 보고 |

Reference decode는 DUT의 bit-30 축약과 달리 `{funct7, funct3}` 10비트 ISA 표를 사용한다. Illegal encoding은 `SCB_ENCODING`으로 분리 보고한다.

## 슬라이드 11. Coverage

| 항목 | 확인 대상 | 조건 / 제외 |
|---|---|---|
| `instruction_cg` | 19 operation, rs1/rs2/rd, alias | `RI_TARGET`만 sample |
| operation/address cross | op×rd, R-op×rs1/rs2, I-op×rs1 | 4-way Cartesian 대신 pairwise 사용 |
| `boundary_cg` | arithmetic, compare, logic, immediate, shift | `BOUNDARY && TARGET`만 sample |
| arithmetic cross | ADD/SUB×overflow, carry/borrow, zero result | signed/unsigned event 분리 |
| compare/logic cross | op×LT/EQ/GT, sign pair, logic profile | 연산 의미가 달라지는 대표 관계 사용 |
| immediate/shift cross | op×imm boundary, op×shamt, source class | illegal shift-I shamt 32 제외, R-shift upper bits 별도 |
| `operand_profile_cg` | pairwise + R-op×rs1 class×rs2 class | 810-bin directed 3-way, 모든 TARGET이 sample에 기여 |
| `random_combo_cg` | op×alias/dep, I-op×src, R-op×src×alias | RANDOM TARGET 전용 관측 지표, mandatory gate 제외 |
| `dependency_cg` | pairwise + operation×dependency×gap | R 120 + I 36 bins, SETUP writer 제외 |
| `xprop_cg` | X source 위치, control known, result propagated | 별도 XPROP test에서만 sample |
| planned case | non-random directed `case_id` commit | 미실행 case는 `COV_CASE` UVM error |
| combo dump | `COMBO_R_*`, `COMBO_I_*` unique key | `cov_combo_dump.txt`를 `sort -u`하여 seed 누적 |

대표 operand class:

```text
0, 1, -1, signed max, signed min,
0xAAAAAAAA, 0x55555555, positive-other, negative-other
```

## 슬라이드 12. Regression 결과

### Clean 결과 (`rv32i_uvm_report_007.log`)

| 항목 | 결과 | 판정 |
|---|---:|---|
| Directed | seed 1001, 1회 | PASS, 8,419 commits |
| Random seed | 1001~1020, 20개 | PASS 20 / FAIL 0 |
| Random commit | 총 80,640개 | run당 4,017~4,044, FAIL/SKIP 0 |
| Random TARGET | seed당 1,003개 | random 1,000 + immediate directed 3 |
| Directed case | 1,962 / 1,962 | 100% |
| `instruction_cg` | 100% | PASS |
| `boundary_cg` | 100% | PASS |
| `operand_profile_cg` | directed 100%; random merged 95.893% | R 3-way 806/810 |
| `dependency_cg` | directed 100%; random merged 97.3232% | R/I 3-way 98/120, 32/36 |
| `random_combo_cg` | 99.8878% (merged) | 관측용, gate 아님 |
| Immediate -2047 / 2046 / 2047 | 각 20 hits | non-shift I-type deterministic item |
| UVM/SVA | error 0 / fatal 0 | PASS |

### XPROP 및 최종 결과 (`rv32i_uvm_report_007.log`)

| 항목 | 결과 | 판정 |
|---|---|---|
| Executed test | `rv32i_ri_xprop_test` | 실제 별도 test 실행 확인 |
| XPROP scoreboard | PASS 17 / FAIL 0 / SKIP 5 / TOTAL 22 | X source 5건의 data compare만 의도대로 skip |
| `xprop_cg` | 100% | PASS |
| X propagation SVA | error 0 / fatal 0 | PASS |
| SVA reachability | clean X-source 0, XPROP R/I X-source 4/1 | 예상과 일치 |
| FSM scope | MEMORY 0, WRITEBACK 0 | R/I-only 범위의 정상 미도달 |
| Final regression | directed PASS + random 20/20 + XPROP PASS | PASS |

Negative test는 clean 결과와 분리했다. `rv32i_ri_illegal_test`에서 legality assertion 3회와 `SCB_ENCODING` 3회가 예상대로 발생했고 hang은 없었다.

## 슬라이드 13. 결론 및 제한 사항

### 결론 문구

> Legal RV32I R/I 명령에 대해 operation, boundary, register address, alias, dependency, operand profile과 random 3-way 조합을 검증했다. Directed 1회와 random 20-seed, 별도 XPROP가 모두 통과했으며, illegal negative test는 full-funct7 reference와 legality assertion이 예약 인코딩을 검출함을 확인했다.

### 고찰 표

| 관찰 | 현재 대응 | 남은 확장 방향 |
|---|---|---|
| 전체 instruction 수와 실제 TARGET 수가 다름 | role metadata로 SETUP/TARGET/READBACK 분리 | 결과 표에 TARGET과 commit을 별도 표기 |
| register 주소 random만으로 값 공간 부족 | operand-profile 9개 class와 R-op×src1×src2 3-way 추가 | 버그 발견률에 따라 class 세분화 |
| 전수 Cartesian cross의 bin 폭증 | value-class/dependency 3-way만 directed closure, register Cartesian은 제외 | seed 증가에 따른 XCRG merged-bin 포화 추세 확인 |
| X source 결과를 2-state로 비교 불가 | X validity model + ALU/WB propagation SVA | XPROP 실제 실행을 regression gate로 유지 |
| functional coverage 100%가 code coverage를 의미하지 않음 | scoreboard/SVA/functional coverage를 함께 판정 | 필요 시 statement/branch/toggle coverage 추가 |
| xsim 2020.2가 cover property 실행을 무시함 | 표준 property 유지 + `RV32I_COVER` 호환 카운터 | simulator upgrade 시 native hit count와 교차 확인 |
| 현재 명령 범위가 R/I로 제한됨 | 범위를 문서와 test name에 명시 | branch/jump/load/store는 별도 environment로 확장 |

## 6분 발표용 표 구성

`Docs/RV32I_UVM_6min.pptx`는 원본 표 스타일을 유지하면서 발표 본문과 상세 Appendix를 분리한다.

- 본문 8장: 표지, 범위, interface/probe, 검증 시나리오, monitor/scoreboard, SVA/coverage, regression, 결론
- 권장 발표 시간: 총 5분 50초로 구성해 10초 여유 확보
- Appendix 12장: `Docs/PPT_Materials/Tables/*.tsv`의 원본 상세 표를 내용 변경 없이 수록
- 본문 요약 TSV: `Docs/PPT_Materials/Tables/6min/*.tsv`

## Appendix A. 발표자가 확인할 최종 체크리스트

- [x] directed 1회 PASS + random seed 20/20 PASS
- [x] 모든 clean run `DATA SKIPPED:0`
- [x] directed case 1,962/1,962
- [x] mandatory clean covergroup 4개 100%
- [x] 실제 test name이 `rv32i_ri_xprop_test`
- [x] `xprop_cg` 100%
- [x] X propagation assertion error 0
- [x] random 누적 R op×src×alias 450/450
- [x] illegal negative `SCB_ENCODING`/legality assertion 각 3회, hang 없음
- [x] 결론 슬라이드에 범위 밖 명령을 명확히 표시

## Appendix B. 파일 연결

| 자료 | 파일 |
|---|---|
| TSV 표 PowerPoint | `Docs/RV32I_UVM_Tables.pptx` |
| PowerPoint 재생성 스크립트 | `Scripts/generate_rv32i_tables_ppt.ps1` |
| 6분 발표용 PowerPoint | `Docs/RV32I_UVM_6min.pptx` |
| 6분 PPT 재생성 스크립트 | `Scripts/generate_rv32i_6min_ppt.ps1` |
| CPU 일반 블록 다이어그램 | `Docs/Block_Diagram/RV32I_General_Block_Diagram.drawio` |
| UVM flow | `Docs/Block_Diagram/RV32I_UVM_Block_Diagram.drawio` |
| UVM hierarchy | `Docs/Block_Diagram/RV32I_UVM_Hierarchy.drawio` |
| Scoreboard flow | `Docs/Block_Diagram/RV32I_Scoreboard_Flow.drawio` |
| PPT 표/문구 | `Docs/PPT_Materials/RV32I_UVM_PPT_Materials.md` |
| 복사용 TSV 표 | `Docs/PPT_Materials/Tables/*.tsv` |
| 6분 본문 요약 TSV | `Docs/PPT_Materials/Tables/6min/*.tsv` |
