# RV32I R/I 전용 UVM 검증 구조

이 문서는 `rv32i_cpu`의 legal R-type/I-type ALU 명령만 검증하는 UVM 환경의 설계 의도와 구현 구조를 설명한다.

검증 범위에 포함되는 명령은 다음 19개다.

- R-type: ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
- I-type: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI

Branch, jump, load/store, APB requester, instruction ROM 자체와 exception 처리는 현재 범위에 포함하지 않는다. Illegal instruction의 정상 처리 기능은 범위 밖이지만, 예약 R/I 인코딩이 legality assertion과 scoreboard에서 검출되는지는 별도 negative test로 고정한다.

## 1. 검증 철학

하나의 큰 random program에 모든 목적을 섞지 않고 다음 여섯 clean/X 시나리오와 별도 negative 시나리오를 구성한다.

```text
Sanity        모든 legal R/I 명령의 기본 동작
Boundary      연산 의미가 변하는 경계와 인접값
RF Access     모든 register 주소와 실제 write/read
Operand Profile 대표 피연산자 값 클래스의 pairwise 조합
Random        예상하지 못한 명령·주소·dependency 조합
X Propagation 미초기화 register의 X 전파와 회복
Illegal       예약 funct7/shift-I 인코딩 검출과 현재 DUT 동작 기록
```

Dependency는 별도 sequence로 만들지 않는다.

- Sanity와 Boundary는 각 TARGET 뒤에 READBACK을 배치한다.
- RF Access는 모든 register를 체계적으로 write/read한다.
- Operand Profile은 전수 Cartesian 곱 없이 operation/operand-class cross를 닫는다.
- Random은 일정 비율로 이전 destination을 다음 source로 사용한다.
- X Propagation은 X 결과의 재사용과 known overwrite 이후 회복을 확인한다.
- Illegal은 clean regression에서 제외하며 assertion/scoreboard error가 예상 결과다.

Sequence는 검증 조건을 만들고, monitor는 실제 commit을 관측하며, scoreboard가 정답을 판정한다. Coverage는 검사 결과가 아니라 계획한 조건이 실제 수행됐는지를 측정한다.

## 2. 전체 데이터 흐름

```text
[Stimulus]
Test -> Scenario sequence -> Program item -> IMEM driver -> DUT

[Expected]
IMEM driver -> original program + metadata -> Scoreboard/Coverage

[Actual]
DUT -> bind probe -> Commit monitor -> Scoreboard/Coverage
```

Scoreboard는 driver가 전달한 원본 instruction으로 reference 결과를 계산한다. DUT에서 관측한 instruction을 그대로 expected 값으로 사용하지 않는다.

Coverage collector는 program metadata와 실제 commit 순서를 정렬한 뒤 sample한다. 따라서 operand 준비용 ADDI가 TARGET ADDI coverage를 채우지 않는다.

## 3. Program metadata

각 program word에는 instruction 외에 다음 정보가 붙는다.

```text
role
scenario
case_id
```

### 역할

```text
RI_SETUP
  source operand와 register 상태를 준비한다.

RI_TARGET
  현재 scenario에서 검증하려는 명령이다.

RI_READBACK
  TARGET destination을 다시 읽어 실제 register 저장을 확인한다.

RI_XPROP
  의도적으로 X를 읽거나 X 상태를 전파·회복시킨다.
```

모든 역할의 instruction은 scoreboard 검사를 받는다. 다만 ISA operation과 boundary coverage는 `RI_TARGET`만 sample한다.

`case_id`는 `ADD_POS_OVERFLOW`, `SRA_RSHIFT_32`, `RF_ADD_ADDR_7`처럼 각 directed case의 목적을 나타낸다. Coverage collector는 planned case가 실제 commit됐는지도 별도로 확인한다.

## 4. 공통 base sequence

`rv32i_ri_base_sequence`는 시나리오가 공통으로 사용하는 기능을 제공한다.

- R-type encoder
- 일반 I-type encoder
- shift-I encoder
- 19개 semantic operation encoder
- program word와 metadata 추가
- register 초기화
- random 전용 mixed register 초기화
- 32비트 상수 생성
- TARGET과 READBACK 생성
- operation 이름과 R/I format 판별

### 32비트 상수 생성

Boundary operand는 RTL register backdoor로 넣지 않는다. ADDI와 SLLI만 사용해 네 개 byte를 순서대로 누적한다.

```text
ADDI rd, x0, byte3
SLLI rd, rd, 8
ADDI rd, rd, byte2
SLLI rd, rd, 8
ADDI rd, rd, byte1
SLLI rd, rd, 8
ADDI rd, rd, byte0
```

이 setup 명령들도 정상적인 architectural instruction이므로 scoreboard가 모두 검사한다.

### READBACK

TARGET destination이 `rd`이면 다음 명령을 사용한다.

```text
ADDI rd, rd, 0
```

이 명령은 register read port에서 실제 저장값을 읽고 같은 register에 그대로 다시 쓴다. Commit 전의 `wb_data`만 보고 register write가 성공했다고 판단하는 문제를 피한다.

## 5. Sanity sequence

클래스: `rv32i_ri_sanity_sequence`

목적은 모든 legal R/I operation이 대표 입력에서 기본적으로 동작하는지 빠르고 결정적으로 확인하는 것이다.

### 구성

1. 고정 register에 고정 operand를 설정한다.
2. R-type 10개를 각각 한 번 TARGET으로 실행한다.
3. I-type 9개를 각각 한 번 TARGET으로 실행한다.
4. 모든 TARGET 뒤에 READBACK을 붙인다.
5. x0 source case를 실행한다.
6. x0 write를 시도한 뒤 ADDI/R-type read port를 통해 x24/x25로 복사하여 간접 확인한다.

Sanity에는 random register mapping을 사용하지 않는다. 동일 실패가 항상 같은 PC와 register에서 발생해야 waveform 분석이 쉽기 때문이다.

### 완료 기준

- 19개 operation 모두 수행
- 모든 TARGET 및 READBACK 결과 일치
- data skip 0
- x0 불변
- scoreboard/assertion 오류 0

## 6. Boundary sequence

클래스: `rv32i_ri_boundary_sequence`

기본 원칙은 의미가 변하는 경계마다 `경계 직전 / 경계 / 경계 직후`를 검사하는 것이다. 다만 legal encoding으로 표현 가능한 범위만 사용한다.

### ADD/SUB

다음 사건을 구분한다.

```text
정상 범위
결과 0
signed positive overflow
signed negative overflow
unsigned carry
unsigned borrow
```

대표값으로 signed maximum/minimum의 직전, 정확한 경계, wraparound를 발생시키는 다음 값을 사용한다.

### SLT/SLTU

다음 관계를 모두 만든다.

```text
A < B
A == B
A > B
```

0 주변, -1/1, signed minimum/maximum, unsigned maximum/zero 조합을 SLT와 SLTU에서 동일하게 실행한다.

SLTI와 SLTIU도 LT/EQ/GT를 명시적으로 각각 만든다.

### AND/OR/XOR

수치 overflow 대신 다음 bit pattern을 사용한다.

```text
zero/zero
zero/all-one
all-one/all-one
0xaaaaaaaa/0x55555555
동일 alternating pattern
MSB-only/LSB-only
일반 비대칭 pattern
```

### R-type shift

effective shift amount와 raw rs2를 모두 본다.

```text
effective: 0, 1, middle, 30, 31
raw rs2  : 0, 1, 16, 30, 31, 32, 33, 63, 64, 65
```

특히 다음 masking 경계를 확인한다.

```text
31 -> effective 31
32 -> effective 0
33 -> effective 1
63 -> effective 31
64 -> effective 0
65 -> effective 1
```

### I-type shift

legal shamt `0, 1, 16, 30, 31`을 사용한다. shamt 32는 legal RV32I encoding이 아니므로 제외한다.

### 일반 I-type immediate

ADDI, SLTI, SLTIU, XORI, ORI, ANDI 각각에 다음 값을 적용한다.

```text
-2048, -2047, -1, 0, 1, 2046, 2047
```

`-2049`와 `2048`은 legal 12-bit immediate가 아니므로 만들지 않는다.

### 완료 기준

- 모든 directed `case_id` commit
- mandatory boundary bin/cross 100%
- 모든 TARGET 및 READBACK 결과 일치
- data skip 0
- scoreboard/assertion 오류 0

## 7. RF Access sequence

클래스: `rv32i_ri_rf_access_sequence`

목적은 ALU data boundary와 독립적으로 모든 register 주소의 source/destination 선택과 실제 저장을 확인하는 것이다.

### 초기화와 read port 확인

x1~x31에 서로 다른 known signature를 쓴다. 이후 x0~x31을 각각 rs1과 rs2 read port로 읽는다.

### Operation/address pairwise sweep

각 operation마다 32회 반복한다.

```text
rs1 = i
rs2 = rotated permutation(i)  // R-type만 사용
rd  = another permutation(i)
```

32회 동안 각 역할에 x0~x31이 정확히 한 번씩 나타난다. 하나의 loop가 다음 pairwise cross를 동시에 닫는다.

```text
operation x rs1 address
R-operation x rs2 address
operation x rd address
```

`operation x rs1 x rs2 x rd` 전체 Cartesian cross는 만들지 않는다. bin 수가 크고 동일한 address mux 동작을 과도하게 반복하기 때문이다.

### Alias

R-type마다 다음 형태를 명시적으로 실행한다.

```text
ALL_DIFFERENT
RD_EQ_RS1
RD_EQ_RS2
RS1_EQ_RS2
ALL_EQUAL
```

I-type마다 다음 두 형태를 실행한다.

```text
RD_NE_RS1
RD_EQ_RS1
```

### Dependency closure

각 R-type operation에 `RD_TO_RS1`, `RD_TO_RS2`, `RD_TO_BOTH`를 명시적으로 만들고, 각 I-type operation에는 `RD_TO_RS1`을 만든다. Source를 SETUP으로 초기화한 뒤 READBACK을 producer로 사용하므로 dependency의 시작점이 분명하다.

대표 ADD case에서는 각 dependency 형태에 대해 gap `0, 1, 2, 3 이상`도 명시적으로 생성한다. 따라서 random 발생 확률에 의존하지 않고 mandatory dependency cross를 닫는다.

### 완료 기준

- 모든 register가 rs1으로 사용됨
- 모든 register가 R-type rs2로 사용됨
- 모든 register가 rd로 사용됨
- operation/address pairwise cross 100%
- operation/alias cross 100%
- x1~x31 write/readback 완료
- x0 불변
- data skip 0

## 8. Operand Profile sequence

클래스: `rv32i_ri_operand_profile_sequence`

주소 조합을 확인하는 RF Access와 별도로, 실제 피연산자 값 공간을 대표 클래스 기준으로 확장한다.

```text
32-bit value class:
  0, 1, -1, signed max, signed min,
  0xaaaaaaaa, 0x55555555, positive-other, negative-other

```

R-type은 operation마다 9회 회전 조합을 사용한다. 각 operation이 rs1/rs2의 9개 클래스를 모두 만나며, operation 전체로는 rs1-class × rs2-class 81쌍이 모두 생성된다. 따라서 `operation × rs1 × rs2` 3차 전수곱 없이 필요한 2-way 관계를 닫는다.

I-type도 operation마다 9회 실행한다. 일반 I-type은 rs1 class를 순회하고, immediate 경계는 별도 boundary sequence가 담당한다. Shift-I는 rs1 class와 legal shamt 구간을 순회한다. 이 sequence는 seed마다 의미 있는 TARGET을 추가한다.

## 9. Random sequence

클래스: `rv32i_ri_random_sequence`

Random functional regression은 모든 register가 known 상태인 clean test다. X는 이 sequence에서 허용하지 않는다.

### 기본 구성

```text
operation-balanced phase: operation당 20 TARGET (380)
free-random phase        : 620 TARGET
합계                     : seed당 1,000 random TARGET
```

Balanced phase는 매 seed에서 모든 operation이 충분히 생성되게 한다. Free phase는 operation 순서까지 자유롭게 섞는다.

### 기본 knob

```text
dependency_rate = 35%
alias_rate      = 30%
boundary_rate   = 40%
readback_rate   = 10%
```

각 비율은 독립 조건이므로 한 instruction에 dependency와 alias가 동시에 적용될 수 있다.

Random program 시작 시 x1~x15는 대표 경계/비트패턴으로, x16~x31은 일반 양수 signature로 초기화한다. 이후 boundary injection이 선택되면 source register를 특수값 또는 random 32-bit 값으로 다시 설정한다. 따라서 주소 random화뿐 아니라 실제 operand 값 분포도 넓어진다.

```text
0, 1, -1
0x7fffffff, 0x80000000
0xaaaaaaaa, 0x55555555
random 32-bit
```

### Regression 기준

기본 regression은 directed suite를 한 번 실행한 뒤 random-only test를 20개 seed로 실행한다. Random은 seed당 1,000 TARGET이며, Operand Profile의 171개 TARGET은 directed suite에서 한 번만 실행된다. 결정론적 시나리오를 seed마다 반복하지 않으면서 랜덤 조합의 수렴을 측정한다.

모든 clean random run은 `DATA_SKIPPED=0`이어야 한다.

## 10. X Propagation sequence

클래스: `rv32i_ri_xprop_sequence`

X 검증은 clean functional regression과 분리하며 별도 `rv32i_ri_xprop_test`에서 실행한다.

### 시나리오

```text
unknown rs1 in I-type
unknown rs1 in R-type
unknown rs2 in R-type
both R-type sources unknown
unknown result reuse
known overwrite
overwrite recovery readback
known path operation after X cases
```

X operand의 산술 결과를 임의의 2-state expected 값과 비교하지 않는다. ADD/SUB/XOR 계열은 X source가 실제 `alu_result`와 `wb_data`까지 전파됐는지를 assertion과 coverage로 확인한다. 동시에 PC, instruction, FSM, R/I control이 known 상태를 유지하는지 확인하고 known overwrite 이후 data comparison이 다시 정상화되는지 본다.

일반 capture assertion은 known operand일 때만 값 동등성을 검사한다. X 입력 때문에 `X == X`가 assertion failure로 해석되는 잡음을 방지한다.

## 11. Commit monitor

Monitor는 다음 실제 commit 정보를 전달한다.

```text
PC, instruction
derived rd write-enable, raw rf_we, rd address/data
rs1/rs2 address
rs1/rs2 actual operand
captured immediate
R/I control signals
ALU result and write-back data
data-bus activity
```

Monitor는 pass/fail을 판단하거나 stimulus 역할을 하지 않는다. Coverage도 monitor 내부에서 바로 sample하지 않는다. Program role과 scenario를 모르는 상태에서 sample하면 SETUP/READBACK이 TARGET coverage를 오염시키기 때문이다.

## 12. Scoreboard

Scoreboard는 다음을 독립적으로 확인한다.

- 원본 program과 실제 PC/instruction 일치
- destination과 effective write-enable
- commit 시점 DUT raw `rf_we`
- ISA 기준 R/I 결과
- x0 write discard
- reference register 상태
- expected commit 수

Known source의 결과는 정확히 비교한다. X source를 사용한 X-propagation case는 data comparison을 skip하고 destination validity를 unknown으로 전파한다. Clean test에서 skip이 발생하면 검증 환경 또는 sequence 구성 문제로 취급한다.

R-type expected 연산 선택은 `{funct7, funct3}` 10비트 ISA 표를 직접 사용한다. I-type shift도 `instr[31:25]`가 SLLI/SRLI/SRAI의 legal 값인지 확인한다. DUT의 `instr[30]` 축약 decode와 표현을 분리했으며, 불법 인코딩은 `SCB_ENCODING`으로 보고한다. 산술 우측 시프트는 unsigned coercion을 피하도록 signed branch를 별도로 유지한다.

## 13. Coverage collector

Coverage collector는 driver의 metadata와 monitor의 실제 commit을 instruction 순서로 맞춘다.

아래 표는 `rv32i_coverage`의 실제 cross 정의를 PPT 표와 동일한 형식으로 정리한 것이다. `×` 뒤의 수는 각 coverpoint의 명시적 bin 수를 곱한 cross bin 수이며, `iff` 조건을 만족하는 sample만 집계한다.

| Covergroup / 관측 범위 | Cross 조합 (코드의 cross 이름 · bin 수) | Sample 조건 · 판정 |
|---|---|---|
| instruction_cg — ISA·주소 | `cx_operation_rd` = 19 operation × 32 rd = 608; `cx_r_operation_rs1` = 10 R-op × 32 = 320; `cx_r_operation_rs2` = 10 × 32 = 320; `cx_i_operation_rs1` = 9 I-op × 32 = 288 | `RI_TARGET`만; semantic operation은 R 10개 + I 9개. x0~x31을 source/destination으로 모두 확인 |
| instruction_cg — alias | `cx_r_operation_alias` = 10 R-op × 5 alias = 50; `cx_i_operation_alias` = 9 I-op × 2 alias = 18 | `RI_TARGET`만; R: all-diff/rd=rs1/rd=rs2/rs1=rs2/all-equal, I: rd=rs1 또는 different |
| boundary_cg — 산술 | `cx_arith_signed` = ADD/SUB 2 × signed event(normal/+overflow/−overflow) 3 = 6; ADD carry와 SUB borrow는 각각 독립 coverpoint; zero-result도 독립 coverpoint | `RI_TARGET && BOUNDARY`; signed overflow와 unsigned carry/borrow를 분리 |
| boundary_cg — 비교·논리 | `cx_compare_relation` = 4 compare-op × LT/EQ/GT 3 = 12; `cx_compare_sign` = 2 R-compare-op × 9 sign-pair = 18; `cx_logic_profile` = 3 logic-op × 7 profile = 21 | `RI_TARGET && BOUNDARY`; 비교의 signed/unsigned 관계와 논리 bit-pattern을 구분 |
| boundary_cg — immediate·shift | `cx_immediate_boundary` = 6 nonshift-I-op × 7 endpoint = 42; `cx_shift_amount` = 6 shift-op × 5 effective-shamt = 30; `cx_r_shift_upper` = 3 R-shift × upper[31:5] zero/nonzero = 6; `cx_shift_source` = 6 × 5 value-class = 30 | `RI_TARGET && BOUNDARY`; I-shift는 legal shamt 0~31만, R-shift masking(upper bits)은 별도 확인 |
| operand_profile_cg — pairwise | `cx_r_operation_src1` = 10 R-op × 9 src1 class = 90; `cx_r_operation_src2` = 10 × 9 = 90; `cx_r_source_pair` = 9 src1 × 9 src2 = 81; `cx_i_operation_src1` = 9 I-op × 9 = 81 | `RI_TARGET`; value class = 0/1/−1/signed max·min/AA/55/positive-other/negative-other |
| operand_profile_cg — 3-way·I operand | `cx_r_operation_source_pair` = 10 R-op × 9 src1 × 9 src2 = 810; `cx_shift_i_amount` = 3 shift-I-op × 6 shamt region = 18 | `RI_TARGET`; immediate endpoint 검증은 중복 없이 `boundary_cg`의 `cx_immediate_boundary`(42 bins)가 담당 |
| random_combo_cg | `cx_r_op_alias` = 10 × 5 = 50; `cx_r_op_dep` = 10 × 4 = 40; `cx_i_op_src1` = 9 × 9 = 81; `cx_r_op_src_alias` = 10 × 9 × 5 = 450; `cx_r_src_pair_dep` = 9 × 9 × 4 = 324 | `RI_TARGET && RANDOM`만; seed 누적 관측 지표이며 mandatory coverage gate 제외 |
| dependency_cg — pairwise | `cx_r_operation_dependency` = 10 R-op × 3 dep = 30; `cx_i_operation_dependency` = 9 I-op × rs1-dep 1 = 9; `cx_dependency_gap` = 3 dep × 4 gap = 12 | TARGET 또는 READBACK, dependency≠NONE; SETUP writer는 producer에서 제외 |
| dependency_cg — 3-way | `cx_r_operation_dependency_gap` = 10 R-op × 3 dep × 4 gap = 120; `cx_i_operation_dependency_gap` = 9 I-op × 1 rs1-dep × 4 gap = 36 | gap = immediate/1/2/3+; I-type은 architectural rs2 source가 없어 rs1 dependency만 포함 |
| xprop_cg | Cross 없음. `cp_x_source` = known/rs1/rs2/both(4); `cp_control_known` = known(unknown은 illegal bin); `cp_operation` = ADD/XOR/ADDI(3); `cp_result_propagated` = propagated(lost는 illegal bin) | `RI_XPROP`만; source X가 ALU와 WB까지 전파되는지, control은 known인지 확인 |
| planned case / closure | Cross 없음. non-random `RI_TARGET`·`RI_XPROP`의 `case_id`를 `planned_case`에 등록하고 실제 `commit`의 `hit_case`와 대조 | 미실행 case는 `COV_CASE` UVM error; group 평균 100%만으로 closure를 선언하지 않음 |

### Instruction coverage

```text
19개 semantic operation
operation x rd
R-operation x rs1
R-operation x rs2
I-operation x rs1
```

Raw opcode/funct3보다 ADD/SUB, SRL/SRA, SRLI/SRAI가 구분되는 semantic operation을 기준으로 한다.

### Alias coverage

```text
R-operation x R alias type
I-operation x I alias type
```

### Arithmetic boundary coverage

```text
ADD/SUB x signed overflow event
ADD unsigned carry
SUB unsigned borrow
zero result
```

### Compare coverage

```text
SLT/SLTU/SLTI/SLTIU x LT/EQ/GT
SLT/SLTU x operand sign pair
```

I-type compare immediate endpoints는 별도 immediate cross가 담당한다.

### Logic coverage

```text
AND/OR/XOR x logic operand profile
```

I-type logic 명령은 immediate boundary cross에서 측정한다.

### Immediate coverage

```text
ADDI/SLTI/SLTIU/XORI/ORI/ANDI
  x {-2048, -2047, -1, 0, 1, 2046, 2047}
```

### Shift coverage

```text
shift operation x effective shamt
R-shift operation x rs2 upper-bits zero/nonzero
shift operation x source value class
```

### Operand-profile coverage

```text
R-operation x rs1 value class
R-operation x rs2 value class
rs1 value class x rs2 value class
R-operation x rs1 value class x rs2 value class
I-operation x rs1 value class
shift-I operation x shamt region
```

새 R-type 3-way cross는 10 operation × 9 rs1 class × 9 rs2 class = 810 bins이다. register 번호의 Cartesian cross가 아니라, 같은 operation에서 두 source 값 class가 함께 사용됐는지를 확인한다. Directed operand-profile sequence는 이 810개 조합을 모두 실행해 mandatory gate를 닫고, 모든 `RI_TARGET` sample은 random target도 누적 coverage에 기여할 수 있다.

Immediate endpoint는 `boundary_cg`의 directed boundary sequence에서만 교차 검증한다. Shift-I의 shamt 제약은 변경하지 않는다.

### Random-combination coverage

`random_combo_cg`는 `RI_SCENARIO_RANDOM && RI_TARGET`만 sample한다.

```text
R-operation x alias
R-operation x dependency
I-operation x rs1 value class
R-operation x rs1 value class x alias
rs1 value class x rs2 value class x dependency
```

3-way cross는 seed 투자 효과를 보는 관측 지표이며 `check_phase`의 99.99% gate에 포함하지 않는다. 같은 sample은 `COMBO_R_*`, `COMBO_I_*` 문자열 key로 `cov_combo_dump.txt`에 append되어 simulator coverage merge 기능 없이 `sort -u`로 누적할 수 있다.

### Dependency coverage

Dependency는 최근 non-SETUP writer를 기준으로 계산한다.

```text
NONE
RD_TO_RS1
RD_TO_RS2
RD_TO_BOTH
```

Gap은 producer와 consumer 사이 instruction 수로 분류한다.

```text
0, 1, 2, 3 이상
```

Cross는 R/I format에서 가능한 dependency만 만든다. I-type에 rs2 dependency bin을 만들지 않는다.

```text
R-operation x R-dependency x gap = 10 x 3 x 4 = 120 bins
I-operation x I-dependency x gap =  9 x 1 x 4 =  36 bins
```

I-type은 architectural rs2 source가 없으므로 rs1 dependency만 측정한다. Directed RF-access sequence가 유효한 모든 156개 조합을 실행하며, 의미 없는 조합을 coverage goal 조정으로 제거하지 않는다.

### Random-merge coverage map

Random-only XCRG merge는 `RI_SCENARIO_RANDOM`에서 sample 가능한 그룹만 해석한다. `boundary_cg`와 `xprop_cg`는 각각 directed boundary/XPROP test 전용이므로 random merge의 0%를 coverage 실패로 해석하지 않으며, 별도 test의 UVM summary에서 확인한다.

| Group | Coverpoint | 검증 의도 |
|---|---|---|
| `instruction_cg` | `cp_operation`, `cp_r_operation`, `cp_i_operation` | 19개 semantic operation과 R/I 분류 도달 |
| | `cp_rs1`, `cp_r_rs1`, `cp_i_rs1`, `cp_rs2`, `cp_rd` | x0~x31이 형식별 source/destination register로 사용됨 |
| | `cp_r_alias`, `cp_i_alias` | rd/rs1/rs2의 동일·상이 alias 관계 도달 |
| `operand_profile_cg` | `cp_r_operation`, `cp_i_operation`, `cp_shift_i_operation` | R/I 및 shift-I operation class 도달 |
| | `cp_src1_class`, `cp_src2_class` | 0, 1, -1, signed end point, bit pattern, positive/negative-other의 9개 값 class 도달 |
| | `cp_shift_amount` | legal shamt 6개 영역 도달 |
| `random_combo_cg` | `cp_r_op`, `cp_i_op`, `cp_src1`, `cp_src2`, `cp_alias`, `cp_dep` | random operation, source class, alias, dependency class의 분포 확인 |
| `dependency_cg` | `cp_r_operation`, `cp_i_operation`, `cp_r_dependency`, `cp_i_dependency`, `cp_dependency`, `cp_gap` | operation, producer-consumer dependency 형태, gap 0/1/2/3+ 도달 |

| Group | Cross | 검증 의도 / bin 수 |
|---|---|---|
| `instruction_cg` | `cx_operation_rd` | operation × rd, 19×32=608 |
| | `cx_r_operation_rs1`, `cx_r_operation_rs2` | R operation × rs1/rs2, 각각 10×32=320 |
| | `cx_i_operation_rs1` | I operation × rs1, 9×32=288 |
| | `cx_r_operation_alias`, `cx_i_operation_alias` | operation × alias pattern, 각각 10×5=50 / 9×2=18 |
| `operand_profile_cg` | `cx_r_operation_src1`, `cx_r_operation_src2`, `cx_r_source_pair` | R operation × 각 source class 및 ordered source-class pair, 90/90/81 |
| | `cx_r_operation_source_pair` | **R operation × rs1 class × rs2 class**, 10×9×9=810. 특정 연산에서 두 operand의 값 성격이 함께 결합됐는지 확인 |
| | `cx_i_operation_src1`, `cx_shift_i_amount` | I operation × rs1 class(81), shift-I operation × shamt region(18) |
| `random_combo_cg` | `cx_r_op_alias`, `cx_r_op_dep`, `cx_i_op_src1` | random R operation × alias(50), R operation × dependency(40), I operation × rs1 class(81) |
| | `cx_r_op_src_alias` | R operation × rs1 class × alias, 10×9×5=450 |
| | `cx_r_src_pair_dep` | rs1 class × rs2 class × dependency, 9×9×4=324 |
| `dependency_cg` | `cx_r_operation_dependency`, `cx_i_operation_dependency`, `cx_dependency_gap` | operation × dependency와 dependency × gap의 pairwise closure, 30/9/12 |
| | `cx_r_operation_dependency_gap` | **R operation × R dependency × gap**, 10×3×4=120 |
| | `cx_i_operation_dependency_gap` | **I operation × I dependency × gap**, 9×1×4=36. I-type은 architectural rs2 source가 없으므로 rs1 dependency만 포함 |

40-seed random merge 예에서는 `cx_r_operation_source_pair`와 `random_combo_cg`의 모든 cross가 100%에 도달했다. 남은 bin은 `cx_r_operation_dependency_gap`(105/120), `cx_i_operation_dependency_gap`(33/36)처럼 operation·dependency·gap이 동시에 맞아야 하는 희소 random 조합이다. 이는 mandatory directed closure의 실패가 아니라 seed 수와 stimulus 분포에 따른 random convergence 지표다.

### X coverage

```text
known source
unknown rs1
unknown rs2
both unknown
architectural control known
X test에서 사용한 operation
unknown source가 ALU/write-back까지 전파됨
```

Directed non-random TARGET/XPROP의 모든 `case_id`는 planned case로 기록되고, commit되지 않은 case는 coverage error가 된다.

## 14. Coverage sampling 정책

| Coverage | Sample role |
|---|---|
| Operation | TARGET |
| Boundary | TARGET |
| RF operation/address | TARGET |
| Alias | TARGET |
| Operand profile | TARGET |
| Random combination | RANDOM의 TARGET |
| Dependency | TARGET, READBACK |
| X propagation | XPROP |
| SETUP | TARGET coverage에서 제외 |

SETUP과 READBACK도 correctness 검사는 받는다. Coverage 목적에 맞는 집계에서만 분리한다.

## 15. Test 구성

하위 호환용 `rv32i_ri_test`는 모든 clean scenario를 순서대로 실행한다.

```text
Sanity -> Boundary -> RF Access -> Operand Profile -> Random
```

실제 batch regression은 다음처럼 분리한다.

```text
rv32i_ri_directed_test : Sanity -> Boundary -> RF Access -> Operand Profile (1회)
rv32i_ri_random_test   : Random only (seed 1001~1020)
rv32i_ri_xprop_test    : X Propagation only (1회)
rv32i_ri_illegal_test  : Illegal only (수동 negative test)
```

각 program은 reset 상태에서 instruction memory에 적재되고 독립적인 architectural state로 시작한다.

`UVM_TESTNAME` plusarg가 없으면 하위 호환용 clean test가 실행된다. Vivado 2020.2 Windows wrapper에서는 `RV32I_DIRECTED`, `RV32I_RANDOM`, `RV32I_XPROP`, `RV32I_ILLEGAL` flag-only alias를 사용한다. `Scripts/sim.sh -uvm`은 directed 1회, random 20회, XPROP 1회를 실행하고 결과를 같은 numbered regression log에 합친다. Random seed마다 독립 coverage DB를 생성하고, XCRG는 `-report_format text`로 병합한다. Vivado 2020.2의 HTML report 충돌은 regression 실패 조건이 아니다.

## 16. 완료 판정

전체 평균 coverage 하나로 완료를 선언하지 않는다. 다음 항목을 각각 확인한다.

```text
Sanity operation coverage       100%
Boundary planned-case coverage  100%
Mandatory boundary cross        100%
RF address coverpoint           100%
Operation/address pairwise      100%
Operation/alias cross           100%
Operand-profile 3-way cross     100% (directed)
Dependency 3-way cross          100% (directed)
X source/result propagation     100%
Directed planned case           1,962/1,962
Random op/src/alias cumulative  450/450
```

해당 scenario가 실행된 경우 coverage collector의 `check_phase`가 mandatory group을 확인한다. RF Access가 실행되면 instruction/RF와 dependency coverage, Boundary가 실행되면 boundary coverage, X test가 실행되면 X coverage가 100% 미만일 때 UVM error를 발생시킨다. Random 반복 hit 수와 multi-seed merge 목표는 regression 결과에서 별도로 관리한다.

동시에 다음 correctness 조건을 만족해야 한다.

```text
clean test scoreboard error     0
clean test assertion error      0
clean test data skip            0
X test unexpected control X     0
expected commit count mismatch  0
```

Coverage 100%는 correctness를 대신하지 않으며, correctness pass도 coverage closure를 대신하지 않는다.

## 17. SVA 도달성 및 illegal negative test

추가 assertion은 FETCH/DECODE의 spurious `rf_we`, commit 이전 PC 변경, EXECUTE에 도달한 불법 R/I 인코딩을 검사한다. Control reference model은 `ALU_ILLEGAL=4'b1111`을 사용하는 full-funct7 lookup이다.

FSM 상태/전이와 assertion antecedent에는 `cover property`를 배치했다. 다만 프로젝트 simulator인 Vivado xsim 2020.2는 이를 실행하지 않고 `[XSIM 43-4127]`을 출력하므로, 동일 event를 세는 `RV32I_COVER` 호환 카운터를 함께 사용한다. Directed에서 MEMORY/WRITEBACK과 X-source가 0회이고, XPROP에서 R-type X-source 4회와 I-type X-source 1회가 관측됐다.

`rv32i_ri_illegal_test`는 다음 세 인코딩을 별도로 실행한다.

```text
funct7=0000001, funct3=000  (M-extension MUL encoding)
funct7=0100000, funct3=100  (reserved XOR alternate encoding)
SLLI with instr[25]=1       (RV32I illegal shamt[5])
```

세 case 모두 legality assertion과 `SCB_ENCODING`을 발화했고 simulation hang은 없었다. 이 error는 negative test의 예상 결과이며 clean regression의 pass/fail 집계에는 포함하지 않는다.

## 18. 2026-09-13 회귀 결과

```text
Directed             PASS, 8,419 commits, planned case 1,962/1,962
Random 1001~1020     PASS 20 / FAIL 0, 총 80,640 commits
Random per-run       4,017~4,044 commits, random_combo_cg 99.8878% (merged)
XPROP                PASS, 17 PASS / 5 intentional SKIP / 0 FAIL
Final clean result   UVM_ERROR 0 / UVM_FATAL 0
R operand 3-way      806 / 810 (99.5062%)
R dependency 3-way   98 / 120 (81.6667%)
I dependency 3-way   32 / 36 (88.8889%)
Immediate -2047/2046/2047  each 20 hits
```

통합 regression log는 프로젝트 루트의 `rv32i_uvm_report_007.log`, XCRG text report는 `Vivado/tb_rv32i_uvm/coverage_runs/regression_007/report/xcrg_report.txt`에 있다.
