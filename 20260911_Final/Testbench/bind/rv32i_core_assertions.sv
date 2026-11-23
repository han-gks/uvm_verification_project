// Simulation-only checker for R/I FSM sequencing, datapath flow, and results.
// Reference functions implement ISA behavior independently from the RTL logic.
module rv32i_core_assertions
  import rv32_pkg::*;
(
  input logic        clk,
  input logic        rst_n,
  input logic [2:0]  state,
  input logic [31:0] pc,
  input logic [31:0] instr,

  input logic        pc_en,
  input logic        branch,
  input logic        jal,
  input logic        jalr,
  input logic        rf_we,
  input logic        alusrc_sel,
  input logic [3:0]  alu_control,
  input logic [2:0]  rf_srcsel,

  input logic [31:0] rf_rd1,
  input logic [31:0] rf_rd2,
  input logic [31:0] imm_ext,
  input logic [31:0] idex_rs1,
  input logic [31:0] idex_rs2,
  input logic [31:0] idex_imm,
  input logic [31:0] alu_src2,
  input logic [31:0] alu_result,
  input logic [31:0] wb_data,

  input logic        transfer,
  input logic        bus_we
);

  function automatic logic is_rtype(input logic [31:0] instruction);
    is_rtype = (instruction[6:0] == OP_RTYPE);
  endfunction

  function automatic logic is_itype(input logic [31:0] instruction);
    is_itype = (instruction[6:0] == OP_ITYPE);
  endfunction

  function automatic logic is_ri(input logic [31:0] instruction);
    is_ri = is_rtype(instruction) || is_itype(instruction);
  endfunction

  function automatic logic is_legal_rtype(input logic [31:0] instruction);
    logic [6:0] funct7;
    logic [2:0] funct3;
    begin
      funct7 = instruction[31:25];
      funct3 = instruction[14:12];

      if (!is_rtype(instruction)) begin
        is_legal_rtype = 1'b0;
      end else begin
        case (funct3)
          3'b000,
          3'b101: is_legal_rtype = (funct7 == 7'b0000000) ||
                                    (funct7 == 7'b0100000);
          default: is_legal_rtype = (funct7 == 7'b0000000);
        endcase
      end
    end
  endfunction

  function automatic logic is_legal_itype(input logic [31:0] instruction);
    logic [6:0] funct7;
    logic [2:0] funct3;
    begin
      funct7 = instruction[31:25];
      funct3 = instruction[14:12];

      if (!is_itype(instruction)) begin
        is_legal_itype = 1'b0;
      end else begin
        case (funct3)
          3'b001: is_legal_itype = (funct7 == 7'b0000000);
          3'b101: is_legal_itype = (funct7 == 7'b0000000) ||
                                    (funct7 == 7'b0100000);
          default: is_legal_itype = 1'b1;
        endcase
      end
    end
  endfunction

  function automatic logic [31:0] ref_i_imm(input logic [31:0] instruction);
    ref_i_imm = {{20{instruction[31]}}, instruction[31:20]};
  endfunction

  function automatic logic [3:0] ref_rtype_alu_control(
    input logic [31:0] instruction
  );
    begin
      case (instruction[14:12])
        3'b000: ref_rtype_alu_control = instruction[30] ? ALU_SUB : ALU_ADD;
        3'b001: ref_rtype_alu_control = ALU_SLL;
        3'b010: ref_rtype_alu_control = ALU_SLT;
        3'b011: ref_rtype_alu_control = ALU_SLTU;
        3'b100: ref_rtype_alu_control = ALU_XOR;
        3'b101: ref_rtype_alu_control = instruction[30] ? ALU_SRA : ALU_SRL;
        3'b110: ref_rtype_alu_control = ALU_OR;
        3'b111: ref_rtype_alu_control = ALU_AND;
        default: ref_rtype_alu_control = ALU_ADD;
      endcase
    end
  endfunction

  function automatic logic [3:0] ref_itype_alu_control(
    input logic [31:0] instruction
  );
    begin
      case (instruction[14:12])
        3'b000: ref_itype_alu_control = ALU_ADD;
        3'b001: ref_itype_alu_control = ALU_SLL;
        3'b010: ref_itype_alu_control = ALU_SLT;
        3'b011: ref_itype_alu_control = ALU_SLTU;
        3'b100: ref_itype_alu_control = ALU_XOR;
        3'b101: ref_itype_alu_control = instruction[30] ? ALU_SRA : ALU_SRL;
        3'b110: ref_itype_alu_control = ALU_OR;
        3'b111: ref_itype_alu_control = ALU_AND;
        default: ref_itype_alu_control = ALU_ADD;
      endcase
    end
  endfunction

  // Full ISA-table decoder, deliberately independent of the DUT's
  // {instruction[30], funct3} shortcut.
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
        3'b001: ref_itype_alu_control_full =
                  (instruction[31:25] == 7'b0000000) ? ALU_SLL : ALU_ILLEGAL;
        3'b101: ref_itype_alu_control_full =
                  (instruction[31:25] == 7'b0000000) ? ALU_SRL :
                  (instruction[31:25] == 7'b0100000) ? ALU_SRA : ALU_ILLEGAL;
        default: ref_itype_alu_control_full = ALU_ILLEGAL;
      endcase
    end
  endfunction

  function automatic logic [31:0] ref_rtype_result(
    input logic [31:0] instruction,
    input logic [31:0] src1,
    input logic [31:0] src2
  );
    begin
      case (instruction[14:12])
        3'b000: ref_rtype_result = instruction[30] ? src1 - src2 : src1 + src2;
        3'b001: ref_rtype_result = src1 << src2[4:0];
        3'b010: ref_rtype_result = ($signed(src1) < $signed(src2)) ? 32'd1 : 32'd0;
        3'b011: ref_rtype_result = (src1 < src2) ? 32'd1 : 32'd0;
        3'b100: ref_rtype_result = src1 ^ src2;
        // 3'b101: ref_rtype_result = instruction[30]
        //                               ? $signed(src1) >>> src2[4:0]
        //                               : src1 >> src2[4:0]; // [FIX] original
        3'b101: begin // [FIX] Avoid unsigned coercion across ternary branches.
          if (instruction[30])
            ref_rtype_result = $signed(src1) >>> src2[4:0];
          else
            ref_rtype_result = src1 >> src2[4:0];
        end
        3'b110: ref_rtype_result = src1 | src2;
        3'b111: ref_rtype_result = src1 & src2;
        default: ref_rtype_result = 32'd0;
      endcase
    end
  endfunction

  function automatic logic [31:0] ref_itype_result(
    input logic [31:0] instruction,
    input logic [31:0] src1
  );
    logic [31:0] immediate;
    begin
      immediate = ref_i_imm(instruction);

      case (instruction[14:12])
        3'b000: ref_itype_result = src1 + immediate;
        3'b001: ref_itype_result = src1 << instruction[24:20];
        3'b010: ref_itype_result = ($signed(src1) < $signed(immediate)) ? 32'd1 : 32'd0;
        3'b011: ref_itype_result = (src1 < immediate) ? 32'd1 : 32'd0;
        3'b100: ref_itype_result = src1 ^ immediate;
        // 3'b101: ref_itype_result = instruction[30]
        //                               ? $signed(src1) >>> instruction[24:20]
        //                               : src1 >> instruction[24:20]; // [FIX] original
        3'b101: begin // [FIX] Keep SRAI signed and use the encoded five-bit shamt.
          if (instruction[30])
            ref_itype_result = $signed(src1) >>> instruction[24:20];
          else
            ref_itype_result = src1 >> instruction[24:20];
        end
        3'b110: ref_itype_result = src1 | immediate;
        3'b111: ref_itype_result = src1 & immediate;
        default: ref_itype_result = 32'd0;
      endcase
    end
  endfunction

  // Reset and state sequencing
  a_reset_state: assert property (
    @(posedge clk) !rst_n |=> (state == CPU_FETCH && pc == 32'd0)
  ) else $error("RV32I_ASSERT: reset did not restore FETCH/PC=0");

  // Intentionally not disabled by reset: a reset edge must not write state.
  a_no_activity_during_reset: assert property (
    @(posedge clk) !rst_n |-> (!rf_we && !transfer && !bus_we)
  ) else $error("RV32I_ASSERT: write or bus activity while reset is asserted");

  a_state_known: assert property (
    @(posedge clk) disable iff (!rst_n)
      !$isunknown(state)
  ) else $error("RV32I_ASSERT: FSM state contains X/Z");

  a_state_legal: assert property (
    @(posedge clk) disable iff (!rst_n)
      state inside {CPU_FETCH, CPU_DECODE, CPU_EXECUTE,
                    CPU_MEMORY, CPU_WRITEBACK}
  ) else $error("RV32I_ASSERT: illegal FSM state");

  a_fetch_to_decode: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_FETCH |=> state == CPU_DECODE
  ) else $error("RV32I_ASSERT: FETCH did not transition to DECODE");

  a_decode_to_execute: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_DECODE |=> state == CPU_EXECUTE
  ) else $error("RV32I_ASSERT: DECODE did not transition to EXECUTE");

  a_ri_execute_to_fetch: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_EXECUTE && is_ri(instr) |=> state == CPU_FETCH
  ) else $error("RV32I_ASSERT: R/I EXECUTE did not transition to FETCH");

  // Fetch/decode stability and instruction-interface sanity
  a_pc_aligned: assert property (
    @(posedge clk) disable iff (!rst_n)
      pc[1:0] == 2'b00
  ) else $error("RV32I_ASSERT: instruction PC is not word aligned");

  a_fetch_signals_stable: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_FETCH |=> $stable(pc) && $stable(instr)
  ) else $error("RV32I_ASSERT: PC/instruction changed between FETCH and DECODE");

  a_decode_signals_stable: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_DECODE |=> $stable(pc) && $stable(instr)
  ) else $error("RV32I_ASSERT: PC/instruction changed between DECODE and EXECUTE");

  a_instruction_known: assert property (
    @(posedge clk) disable iff (!rst_n)
      state inside {CPU_FETCH, CPU_DECODE, CPU_EXECUTE}
      |-> !$isunknown({pc, instr})
  ) else $error("RV32I_ASSERT: PC or instruction contains X/Z");

  // Decode and ID/EX capture
  a_itype_immediate: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_DECODE && is_itype(instr)
      |-> (imm_ext == ref_i_imm(instr) && idex_imm == ref_i_imm(instr))
  ) else $error("RV32I_ASSERT: I-type immediate decode/capture mismatch");

  a_rs1_capture: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_DECODE && is_ri(instr) &&
      !$isunknown({idex_rs1, rf_rd1})
      |-> idex_rs1 == rf_rd1
  ) else $error("RV32I_ASSERT: rs1 was not captured into ID/EX");

  a_rs2_capture: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_DECODE && is_rtype(instr) &&
      !$isunknown({idex_rs2, rf_rd2})
      |-> idex_rs2 == rf_rd2
  ) else $error("RV32I_ASSERT: rs2 was not captured into ID/EX");

  a_rs1_x0: assert property (
    @(posedge clk) disable iff (!rst_n)
      instr[19:15] == 5'd0 |-> rf_rd1 == 32'd0
  ) else $error("RV32I_ASSERT: rs1=x0 did not read as zero");

  a_rs2_x0: assert property (
    @(posedge clk) disable iff (!rst_n)
      instr[24:20] == 5'd0 |-> rf_rd2 == 32'd0
  ) else $error("RV32I_ASSERT: rs2=x0 did not read as zero");

  // Execute-stage control decode
  a_rtype_control: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_EXECUTE && is_legal_rtype(instr)
      |-> (pc_en && rf_we && !alusrc_sel && !branch && !jal && !jalr &&
           !transfer && !bus_we && rf_srcsel == WB_ALU_RESULT &&
           alu_control == ref_rtype_alu_control_full(instr))
  ) else $error("RV32I_ASSERT: R-type execute controls are incorrect");

  a_itype_control: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_EXECUTE && is_legal_itype(instr)
      |-> (pc_en && rf_we && alusrc_sel && !branch && !jal && !jalr &&
           !transfer && !bus_we && rf_srcsel == WB_ALU_RESULT &&
           alu_control == ref_itype_alu_control_full(instr))
  ) else $error("RV32I_ASSERT: I-type execute controls are incorrect");

  // Execute-stage operands, ALU result, and write-back selection
  a_rtype_execute: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_EXECUTE && is_legal_rtype(instr) &&
      !$isunknown({idex_rs1, idex_rs2})
      |-> (alu_src2 == idex_rs2 &&
           alu_result == ref_rtype_result(instr, idex_rs1, idex_rs2) &&
           wb_data == alu_result)
  ) else $error("RV32I_ASSERT: R-type execute/write-back result mismatch");

  a_itype_execute: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_EXECUTE && is_legal_itype(instr) &&
      !$isunknown(idex_rs1)
      |-> (alu_src2 == idex_imm &&
           alu_result == ref_itype_result(instr, idex_rs1) &&
           wb_data == alu_result)
  ) else $error("RV32I_ASSERT: I-type execute/write-back result mismatch");

  // ADD/SUB/XOR cannot mask an unknown source.  These checks complement the
  // known-source result assertions above and make X-propagation an observed
  // requirement at both the ALU result and register-file write-back input.
  a_rtype_x_result_propagates: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_EXECUTE && is_legal_rtype(instr) &&
      instr[14:12] inside {3'b000, 3'b100} &&
      $isunknown({idex_rs1, idex_rs2})
      |-> ($isunknown(alu_result) && $isunknown(wb_data))
  ) else $error("RV32I_ASSERT: R-type source X did not reach ALU/write-back");

  a_itype_x_result_propagates: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_EXECUTE && is_legal_itype(instr) &&
      instr[14:12] inside {3'b000, 3'b100} &&
      $isunknown(idex_rs1)
      |-> ($isunknown(alu_result) && $isunknown(wb_data))
  ) else $error("RV32I_ASSERT: I-type source X did not reach ALU/write-back");

  a_ri_execute_known: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_EXECUTE && is_ri(instr)
      |-> !$isunknown({pc_en, rf_we, alusrc_sel, alu_control,
                       rf_srcsel})
  ) else $error("RV32I_ASSERT: R/I execute control contains X/Z");

  a_ri_pc_increment: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_EXECUTE && is_ri(instr)
      |=> pc == $past(pc) + 32'd4
  ) else $error("RV32I_ASSERT: R/I instruction did not advance PC by four");

  a_ri_no_bus_access: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_EXECUTE && is_ri(instr)
      |-> (!transfer && !bus_we)
  ) else $error("RV32I_ASSERT: R/I instruction initiated a data-bus access");

  // EXECUTE 이전 상태에서는 레지스터 쓰기가 일어나면 안 된다.
  a_no_write_outside_execute: assert property (
    @(posedge clk) disable iff (!rst_n)
      state inside {CPU_FETCH, CPU_DECODE} |-> !rf_we
  ) else $error("RV32I_ASSERT: rf_we asserted outside EXECUTE");

  // A multicycle instruction must retain its PC until the committing state.
  a_pc_stable_before_commit: assert property (
    @(posedge clk) disable iff (!rst_n)
      state inside {CPU_FETCH, CPU_DECODE} |=> $stable(pc)
  ) else $error("RV32I_ASSERT: PC advanced before the committing state");

  // Make the legal-R/I stimulus assumption observable instead of allowing
  // illegal encodings to bypass all legality-gated assertions vacuously.
  a_assume_legal_encoding: assert property (
    @(posedge clk) disable iff (!rst_n)
      state == CPU_EXECUTE && is_ri(instr)
      |-> (is_legal_rtype(instr) || is_legal_itype(instr))
  ) else $error("RV32I_ASSERT: TB assumption violated - illegal R/I encoding reached EXECUTE");

  // =================================================================
  // COVER PROPERTIES
  // Substitute for unavailable code coverage and expose assertion antecedents.
  // =================================================================
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

  c_trans_fetch_decode: cover property (
    @(posedge clk) disable iff (!rst_n)
    (state == CPU_FETCH) ##1 (state == CPU_DECODE));
  c_trans_decode_execute: cover property (
    @(posedge clk) disable iff (!rst_n)
    (state == CPU_DECODE) ##1 (state == CPU_EXECUTE));
  c_trans_execute_fetch: cover property (
    @(posedge clk) disable iff (!rst_n)
    (state == CPU_EXECUTE) ##1 (state == CPU_FETCH));

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

  c_reset_asserted: cover property (
    @(posedge clk) !rst_n);
  c_reset_release: cover property (
    @(posedge clk) (!rst_n) ##1 (rst_n));

  // Vivado xsim 2020.2 parses cover property but ignores it during simulation
  // (XSIM 43-4127). Mirror the same events with counters so this supported
  // project toolchain still emits quantitative reachability evidence.
  int unsigned cov_state_fetch_count;
  int unsigned cov_state_decode_count;
  int unsigned cov_state_execute_count;
  int unsigned cov_state_memory_count;
  int unsigned cov_state_writeback_count;
  int unsigned cov_trans_fetch_decode_count;
  int unsigned cov_trans_decode_execute_count;
  int unsigned cov_trans_execute_fetch_count;
  int unsigned cov_rtype_executed_count;
  int unsigned cov_itype_executed_count;
  int unsigned cov_rtype_x_source_count;
  int unsigned cov_itype_x_source_count;
  int unsigned cov_rs1_is_x0_count;
  int unsigned cov_rs2_is_x0_count;
  int unsigned cov_rd_is_x0_count;
  int unsigned cov_reset_asserted_count;
  int unsigned cov_reset_release_count;
  logic [2:0] cov_previous_state;
  logic       cov_previous_rst_n;
  bit         cov_previous_valid;

  initial
  begin
    cov_state_fetch_count = 0;
    cov_state_decode_count = 0;
    cov_state_execute_count = 0;
    cov_state_memory_count = 0;
    cov_state_writeback_count = 0;
    cov_trans_fetch_decode_count = 0;
    cov_trans_decode_execute_count = 0;
    cov_trans_execute_fetch_count = 0;
    cov_rtype_executed_count = 0;
    cov_itype_executed_count = 0;
    cov_rtype_x_source_count = 0;
    cov_itype_x_source_count = 0;
    cov_rs1_is_x0_count = 0;
    cov_rs2_is_x0_count = 0;
    cov_rd_is_x0_count = 0;
    cov_reset_asserted_count = 0;
    cov_reset_release_count = 0;
    cov_previous_state = CPU_FETCH;
    cov_previous_rst_n = 1'b0;
    cov_previous_valid = 1'b0;
  end

  always @(posedge clk)
  begin
    if (!rst_n)
      cov_reset_asserted_count++;

    if (cov_previous_valid && !cov_previous_rst_n && rst_n)
      cov_reset_release_count++;

    if (rst_n)
    begin
      case (state)
        CPU_FETCH:     cov_state_fetch_count++;
        CPU_DECODE:    cov_state_decode_count++;
        CPU_EXECUTE:   cov_state_execute_count++;
        CPU_MEMORY:    cov_state_memory_count++;
        CPU_WRITEBACK: cov_state_writeback_count++;
        default: ;
      endcase

      if (cov_previous_valid && cov_previous_rst_n)
      begin
        if (cov_previous_state == CPU_FETCH && state == CPU_DECODE)
          cov_trans_fetch_decode_count++;
        if (cov_previous_state == CPU_DECODE && state == CPU_EXECUTE)
          cov_trans_decode_execute_count++;
        if (cov_previous_state == CPU_EXECUTE && state == CPU_FETCH)
          cov_trans_execute_fetch_count++;
      end

      if (state == CPU_EXECUTE && is_legal_rtype(instr))
        cov_rtype_executed_count++;
      if (state == CPU_EXECUTE && is_legal_itype(instr))
        cov_itype_executed_count++;
      if (state == CPU_EXECUTE && is_legal_rtype(instr) &&
          $isunknown({idex_rs1, idex_rs2}))
        cov_rtype_x_source_count++;
      if (state == CPU_EXECUTE && is_legal_itype(instr) &&
          $isunknown(idex_rs1))
        cov_itype_x_source_count++;
      if (instr[19:15] == 5'd0)
        cov_rs1_is_x0_count++;
      if (is_rtype(instr) && instr[24:20] == 5'd0)
        cov_rs2_is_x0_count++;
      if (state == CPU_EXECUTE && is_ri(instr) && instr[11:7] == 5'd0)
        cov_rd_is_x0_count++;
    end

    cov_previous_state = state;
    cov_previous_rst_n = rst_n;
    cov_previous_valid = 1'b1;
  end

  final
  begin
    $display("RV32I_COVER: c_state_fetch=%0d", cov_state_fetch_count);
    $display("RV32I_COVER: c_state_decode=%0d", cov_state_decode_count);
    $display("RV32I_COVER: c_state_execute=%0d", cov_state_execute_count);
    $display("RV32I_COVER: c_state_memory=%0d", cov_state_memory_count);
    $display("RV32I_COVER: c_state_writeback=%0d", cov_state_writeback_count);
    $display("RV32I_COVER: c_trans_fetch_decode=%0d", cov_trans_fetch_decode_count);
    $display("RV32I_COVER: c_trans_decode_execute=%0d", cov_trans_decode_execute_count);
    $display("RV32I_COVER: c_trans_execute_fetch=%0d", cov_trans_execute_fetch_count);
    $display("RV32I_COVER: c_rtype_executed=%0d", cov_rtype_executed_count);
    $display("RV32I_COVER: c_itype_executed=%0d", cov_itype_executed_count);
    $display("RV32I_COVER: c_rtype_x_source=%0d", cov_rtype_x_source_count);
    $display("RV32I_COVER: c_itype_x_source=%0d", cov_itype_x_source_count);
    $display("RV32I_COVER: c_rs1_is_x0=%0d", cov_rs1_is_x0_count);
    $display("RV32I_COVER: c_rs2_is_x0=%0d", cov_rs2_is_x0_count);
    $display("RV32I_COVER: c_rd_is_x0=%0d", cov_rd_is_x0_count);
    $display("RV32I_COVER: c_reset_asserted=%0d", cov_reset_asserted_count);
    $display("RV32I_COVER: c_reset_release=%0d", cov_reset_release_count);
  end

endmodule
