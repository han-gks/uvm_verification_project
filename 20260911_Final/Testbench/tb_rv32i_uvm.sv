/*******************************************************************
 - File name   : tb_rv32i_uvm.sv
 - Description : Single-file UVM testbench for the RV32I core

 [ Verification Architecture ]
 1. DUT          : rv32i_cpu only; instruction ROM and APB are excluded.
 2. Stimulus     : Sanity, boundary, RF-access, operand-profile, clean-random,
                    and X-propagation sequences load programs through one
                    active IMEM agent.
 3. Observation  : A passive monitor reads the bound rv32i_probe_if.
 4. Scoreboard   : An independent architectural register model checks PC,
                   instruction, destination register, and write-back data.
 5. Coverage     : Intent-aware operation, boundary, register-address, operand,
                    alias, dependency, and X coverage is sampled after commit
                    alignment.
 6. Assertions   : Stage-level checks are provided by Testbench/bind files.

 This file intentionally contains no DPI-C or external C reference model.
*******************************************************************/
`timescale 1ns/1ps

`ifndef UVM_REPORT_DISABLE_FILE_LINE
`define UVM_REPORT_DISABLE_FILE_LINE
`endif

`include "uvm_macros.svh"
import uvm_pkg::*;
import rv32_pkg::*;

`uvm_analysis_imp_decl(_commit)
`uvm_analysis_imp_decl(_program)

// Verification intent is carried with each program word.  SETUP and READBACK
// instructions are still checked by the scoreboard, but only TARGET words are
// allowed to close ISA/operand coverage.
typedef enum int unsigned {
  RI_SETUP,
  RI_TARGET,
  RI_READBACK,
  RI_XPROP
} ri_instr_role_e;

typedef enum int unsigned {
  RI_SCENARIO_SANITY,
  RI_SCENARIO_BOUNDARY,
  RI_SCENARIO_RF_ACCESS,
  RI_SCENARIO_OPERAND_PROFILE,
  RI_SCENARIO_RANDOM,
  RI_SCENARIO_XPROP
} ri_scenario_e;

typedef enum int unsigned {
  RI_ADD,  RI_SUB,  RI_SLL,  RI_SLT,  RI_SLTU,
  RI_XOR,  RI_SRL,  RI_SRA,  RI_OR,   RI_AND,
  RI_ADDI, RI_SLTI, RI_SLTIU, RI_XORI, RI_ORI,
  RI_ANDI, RI_SLLI, RI_SRLI, RI_SRAI, RI_OP_UNKNOWN
} ri_operation_e;

typedef enum int unsigned {
  RI_ALIAS_ALL_DIFFERENT,
  RI_ALIAS_RD_RS1,
  RI_ALIAS_RD_RS2,
  RI_ALIAS_RS1_RS2,
  RI_ALIAS_ALL_EQUAL,
  RI_ALIAS_I_DIFFERENT,
  RI_ALIAS_I_EQUAL
} ri_alias_e;

typedef enum int unsigned {
  RI_DEP_NONE,
  RI_DEP_RS1,
  RI_DEP_RS2,
  RI_DEP_BOTH
} ri_dependency_e;

typedef enum int unsigned {
  RI_VAL_ZERO,
  RI_VAL_ONE,
  RI_VAL_NEG_ONE,
  RI_VAL_SIGNED_MAX,
  RI_VAL_SIGNED_MIN,
  RI_VAL_ALT_A,
  RI_VAL_ALT_5,
  RI_VAL_POS_OTHER,
  RI_VAL_NEG_OTHER
} ri_value_class_e;

typedef enum int unsigned {
  RI_REL_LT,
  RI_REL_EQ,
  RI_REL_GT
} ri_relation_e;

typedef enum int unsigned {
  RI_SIGN_ZERO_ZERO,
  RI_SIGN_POS_POS,
  RI_SIGN_POS_NEG,
  RI_SIGN_NEG_POS,
  RI_SIGN_NEG_NEG,
  RI_SIGN_ZERO_POS,
  RI_SIGN_ZERO_NEG,
  RI_SIGN_POS_ZERO,
  RI_SIGN_NEG_ZERO
} ri_sign_pair_e;

typedef enum int unsigned {
  RI_LOGIC_ZERO_ZERO,
  RI_LOGIC_ZERO_ONES,
  RI_LOGIC_ONES_ONES,
  RI_LOGIC_ALT_COMPLEMENT,
  RI_LOGIC_ALT_SAME,
  RI_LOGIC_MSB_LSB,
  RI_LOGIC_OTHER
} ri_logic_profile_e;

// Route every UVM report to both the simulator console and a text file.
// Root settings catch reports emitted before the component hierarchy exists;
// hierarchical settings are applied again at end_of_elaboration_phase.
function void rv32i_configure_root_report(input int log_fd);
  uvm_top.set_report_verbosity_level(UVM_HIGH);
  uvm_top.set_report_max_quit_count(0);
  uvm_top.set_report_default_file(log_fd);
  uvm_top.set_report_severity_action(UVM_INFO,    UVM_DISPLAY | UVM_LOG);
  uvm_top.set_report_severity_action(UVM_WARNING, UVM_DISPLAY | UVM_LOG | UVM_COUNT);
  uvm_top.set_report_severity_action(UVM_ERROR,   UVM_DISPLAY | UVM_LOG | UVM_COUNT);
  uvm_top.set_report_severity_action(UVM_FATAL,   UVM_DISPLAY | UVM_LOG | UVM_EXIT);
  uvm_top.set_report_severity_file(UVM_INFO,    log_fd);
  uvm_top.set_report_severity_file(UVM_WARNING, log_fd);
  uvm_top.set_report_severity_file(UVM_ERROR,   log_fd);
  uvm_top.set_report_severity_file(UVM_FATAL,   log_fd);
endfunction

function void rv32i_configure_hier_report(input int log_fd);
  uvm_top.set_report_verbosity_level_hier(UVM_HIGH);
  uvm_top.set_report_default_file_hier(log_fd);
  uvm_top.set_report_severity_action_hier(UVM_INFO,    UVM_DISPLAY | UVM_LOG);
  uvm_top.set_report_severity_action_hier(UVM_WARNING, UVM_DISPLAY | UVM_LOG | UVM_COUNT);
  uvm_top.set_report_severity_action_hier(UVM_ERROR,   UVM_DISPLAY | UVM_LOG | UVM_COUNT);
  uvm_top.set_report_severity_action_hier(UVM_FATAL,   UVM_DISPLAY | UVM_LOG | UVM_EXIT);
  uvm_top.set_report_severity_file_hier(UVM_INFO,    log_fd);
  uvm_top.set_report_severity_file_hier(UVM_WARNING, log_fd);
  uvm_top.set_report_severity_file_hier(UVM_ERROR,   log_fd);
  uvm_top.set_report_severity_file_hier(UVM_FATAL,   log_fd);
endfunction

// Preserve previous reports by selecting the first unused numbered filename.
function int rv32i_open_numbered_report_log(
  input string log_prefix,
  output string log_path
);
  int idx;
  int probe_fd;
  int log_fd;
  string candidate;

  for (idx = 1; idx <= 999; idx++)
  begin
    candidate = $sformatf("%s_%03d.log", log_prefix, idx);
    probe_fd = $fopen(candidate, "r");
    if (probe_fd != 0)
      $fclose(probe_fd);
    else
    begin
      log_fd = $fopen(candidate, "w");
      if (log_fd != 0)
      begin
        log_path = candidate;
        return log_fd;
      end
    end
  end

  log_path = "";
  return 0;
endfunction

function string rv32i_strip_log_extension(input string log_path);
  int path_len;
  path_len = log_path.len();
  if ((path_len > 4) &&
      (log_path.substr(path_len - 4, path_len - 1) == ".log"))
    return log_path.substr(0, path_len - 5);
  return log_path;
endfunction

// =================================================================
// 1. CORE INSTRUCTION INTERFACE
// =================================================================
interface rv32i_core_if #(
  int IMEM_DEPTH = 4096,
  int IMEM_AW    = 12
) (
  input logic clk
);
  localparam logic [31:0] STOP_INSTR = 32'h0000_0000;

  logic        rst_n;
  logic [31:0] instr_code;
  logic [31:0] instr_addr;

  logic [31:0] bus_rdata;
  logic        ready;
  logic [2:0]  itype;
  logic        bus_we;
  logic        transfer;
  logic [31:0] bus_addr;
  logic [31:0] bus_wdata;

  // The driver writes this array before reset is released. The combinational
  // lookup models the asynchronous instruction ROM expected by this core.
  logic [31:0] instr_mem [0:IMEM_DEPTH-1];

  always_comb
  begin
    instr_code = STOP_INSTR;
    if (!$isunknown(instr_addr[IMEM_AW+1:2]))
      instr_code = instr_mem[instr_addr[IMEM_AW+1:2]];
  end

  initial
  begin
    rst_n     = 1'b0;
    ready     = 1'b1;
    bus_rdata = 32'd0;
    for (int i = 0; i < IMEM_DEPTH; i++)
      instr_mem[i] = STOP_INSTR;
  end

  // Reset changes on the falling edge so it is stable at DUT clock edges.
  clocking drv_cb @(negedge clk);
    default input #1step output #1ns;
    output rst_n;
    input  instr_addr;
  endclocking

endinterface

// =================================================================
// 2. PROGRAM SEQUENCE ITEM
// =================================================================
class rv32i_program_item extends uvm_sequence_item;
  bit [31:0] instructions[$];
  ri_instr_role_e roles[$];
  ri_scenario_e   scenarios[$];
  string          case_ids[$];

  `uvm_object_utils_begin(rv32i_program_item)
    `uvm_field_queue_int(instructions, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "rv32i_program_item");
    super.new(name);
  endfunction

  function void append(
    input bit [31:0]      instruction,
    input ri_instr_role_e role,
    input ri_scenario_e   scenario,
    input string          case_id
  );
    instructions.push_back(instruction);
    roles.push_back(role);
    scenarios.push_back(scenario);
    case_ids.push_back(case_id);
  endfunction

  virtual function string convert2string();
    return $sformatf("instruction_count=%0d", instructions.size());
  endfunction
endclass

// =================================================================
// 3. COMMIT MONITOR ITEM
// =================================================================
class rv32i_commit_item extends uvm_sequence_item;
  bit          reset;
  logic [31:0] pc;
  logic [31:0] instr;
  logic        rd_we;
  logic [4:0]  rd;
  logic [31:0] rd_data;
  logic [4:0]  rs1;
  logic [4:0]  rs2;
  logic [31:0] rs1_data;
  logic [31:0] rs2_data;
  logic [31:0] immediate;
  logic        pc_en;
  logic        branch;
  logic        jal;
  logic        jalr;
  logic        rf_we;
  logic        alusrc_sel;
  logic [3:0]  alu_control;
  logic [2:0]  rf_srcsel;
  logic [31:0] alu_result;
  logic [31:0] wb_data;
  logic        transfer;
  logic        bus_we;

  `uvm_object_utils_begin(rv32i_commit_item)
    `uvm_field_int(reset,   UVM_DEFAULT)
    `uvm_field_int(pc,      UVM_DEFAULT)
    `uvm_field_int(instr,   UVM_DEFAULT)
    `uvm_field_int(rd_we,   UVM_DEFAULT)
    `uvm_field_int(rd,      UVM_DEFAULT)
    `uvm_field_int(rd_data, UVM_DEFAULT)
    `uvm_field_int(rs1,     UVM_DEFAULT)
    `uvm_field_int(rs2,     UVM_DEFAULT)
    `uvm_field_int(rs1_data,UVM_DEFAULT)
    `uvm_field_int(rs2_data,UVM_DEFAULT)
    `uvm_field_int(immediate,UVM_DEFAULT)
    `uvm_field_int(pc_en, UVM_DEFAULT)
    `uvm_field_int(branch, UVM_DEFAULT)
    `uvm_field_int(jal, UVM_DEFAULT)
    `uvm_field_int(jalr, UVM_DEFAULT)
    `uvm_field_int(rf_we, UVM_DEFAULT)
    `uvm_field_int(alusrc_sel, UVM_DEFAULT)
    `uvm_field_int(alu_control, UVM_DEFAULT)
    `uvm_field_int(rf_srcsel, UVM_DEFAULT)
    `uvm_field_int(alu_result, UVM_DEFAULT)
    `uvm_field_int(wb_data, UVM_DEFAULT)
    `uvm_field_int(transfer, UVM_DEFAULT)
    `uvm_field_int(bus_we, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "rv32i_commit_item");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("PC:%08h Instr:%08h WE:%b RD:x%0d Data:%08h",
                     pc, instr, rd_we, rd, rd_data);
  endfunction
endclass


// =================================================================
// 4. SCENARIO-ORIENTED R/I SEQUENCES
// =================================================================
class rv32i_ri_base_sequence extends uvm_sequence #(rv32i_program_item);
  `uvm_object_utils(rv32i_ri_base_sequence)

  rv32i_program_item req;
  int unsigned       instruction_count;

  function new(string name = "rv32i_ri_base_sequence");
    super.new(name);
  endfunction

  function automatic bit [31:0] encode_r(
    input bit [6:0] funct7, input bit [4:0] rs2,
    input bit [4:0] rs1, input bit [2:0] funct3,
    input bit [4:0] rd
  );
    return {funct7, rs2, rs1, funct3, rd, OP_RTYPE};
  endfunction

  function automatic bit [31:0] encode_i(
    input int signed immediate, input bit [4:0] rs1,
    input bit [2:0] funct3, input bit [4:0] rd
  );
    return {immediate[11:0], rs1, funct3, rd, OP_ITYPE};
  endfunction

  function automatic bit [31:0] encode_shift_i(
    input bit [6:0] funct7, input bit [4:0] shamt,
    input bit [4:0] rs1, input bit [2:0] funct3,
    input bit [4:0] rd
  );
    return {funct7, shamt, rs1, funct3, rd, OP_ITYPE};
  endfunction

  function automatic bit is_r_operation(input ri_operation_e op);
    return op inside {RI_ADD, RI_SUB, RI_SLL, RI_SLT, RI_SLTU,
                      RI_XOR, RI_SRL, RI_SRA, RI_OR, RI_AND};
  endfunction

  function automatic string operation_name(input ri_operation_e op);
    case (op)
      RI_ADD: return "ADD"; RI_SUB: return "SUB";
      RI_SLL: return "SLL"; RI_SLT: return "SLT";
      RI_SLTU: return "SLTU"; RI_XOR: return "XOR";
      RI_SRL: return "SRL"; RI_SRA: return "SRA";
      RI_OR: return "OR"; RI_AND: return "AND";
      RI_ADDI: return "ADDI"; RI_SLTI: return "SLTI";
      RI_SLTIU: return "SLTIU"; RI_XORI: return "XORI";
      RI_ORI: return "ORI"; RI_ANDI: return "ANDI";
      RI_SLLI: return "SLLI"; RI_SRLI: return "SRLI";
      RI_SRAI: return "SRAI";
      default: return "UNKNOWN";
    endcase
  endfunction

  function automatic bit [31:0] encode_operation(
    input ri_operation_e op, input bit [4:0] rs1,
    input bit [4:0] rs2, input bit [4:0] rd,
    input int signed immediate, input bit [4:0] shamt
  );
    case (op)
      RI_ADD:   return encode_r(7'h00, rs2, rs1, 3'b000, rd);
      RI_SUB:   return encode_r(7'h20, rs2, rs1, 3'b000, rd);
      RI_SLL:   return encode_r(7'h00, rs2, rs1, 3'b001, rd);
      RI_SLT:   return encode_r(7'h00, rs2, rs1, 3'b010, rd);
      RI_SLTU:  return encode_r(7'h00, rs2, rs1, 3'b011, rd);
      RI_XOR:   return encode_r(7'h00, rs2, rs1, 3'b100, rd);
      RI_SRL:   return encode_r(7'h00, rs2, rs1, 3'b101, rd);
      RI_SRA:   return encode_r(7'h20, rs2, rs1, 3'b101, rd);
      RI_OR:    return encode_r(7'h00, rs2, rs1, 3'b110, rd);
      RI_AND:   return encode_r(7'h00, rs2, rs1, 3'b111, rd);
      RI_ADDI:  return encode_i(immediate, rs1, 3'b000, rd);
      RI_SLTI:  return encode_i(immediate, rs1, 3'b010, rd);
      RI_SLTIU: return encode_i(immediate, rs1, 3'b011, rd);
      RI_XORI:  return encode_i(immediate, rs1, 3'b100, rd);
      RI_ORI:   return encode_i(immediate, rs1, 3'b110, rd);
      RI_ANDI:  return encode_i(immediate, rs1, 3'b111, rd);
      RI_SLLI:  return encode_shift_i(7'h00, shamt, rs1, 3'b001, rd);
      RI_SRLI:  return encode_shift_i(7'h00, shamt, rs1, 3'b101, rd);
      RI_SRAI:  return encode_shift_i(7'h20, shamt, rs1, 3'b101, rd);
      default:  return 32'd0;
    endcase
  endfunction

  virtual task begin_program();
    req = rv32i_program_item::type_id::create("req");
    start_item(req);
  endtask

  virtual task end_program();
    instruction_count = req.instructions.size();
    finish_item(req);
  endtask

  function void emit_raw(
    input bit [31:0] instruction, input ri_instr_role_e role,
    input ri_scenario_e scenario, input string case_id
  );
    req.append(instruction, role, scenario, case_id);
  endfunction

  function void emit_operation(
    input ri_operation_e op, input bit [4:0] rs1,
    input bit [4:0] rs2, input bit [4:0] rd,
    input int signed immediate, input bit [4:0] shamt,
    input ri_instr_role_e role, input ri_scenario_e scenario,
    input string case_id
  );
    emit_raw(encode_operation(op, rs1, rs2, rd, immediate, shamt),
             role, scenario, case_id);
  endfunction

  // ADDI rd,rd,0 observes the value through the architectural read port and
  // writes it back unchanged.  This checks storage without peeking at the array.
  function void emit_readback(
    input bit [4:0] rd, input ri_scenario_e scenario,
    input string case_id
  );
    emit_operation(RI_ADDI, rd, 0, rd, 0, 0, RI_READBACK,
                   scenario, {case_id, "_READBACK"});
  endfunction

  function void emit_target_with_readback(
    input ri_operation_e op, input bit [4:0] rs1,
    input bit [4:0] rs2, input bit [4:0] rd,
    input int signed immediate, input bit [4:0] shamt,
    input ri_scenario_e scenario, input string case_id
  );
    emit_operation(op, rs1, rs2, rd, immediate, shamt,
                   RI_TARGET, scenario, case_id);
    emit_readback(rd, scenario, case_id);
  endfunction

  // Construct any 32-bit value using only legal ADDI/SLLI instructions.
  function void load_constant(
    input bit [4:0] rd, input bit [31:0] value,
    input ri_scenario_e scenario, input string case_id
  );
    emit_raw(encode_i(int'(value[31:24]), 0, 3'b000, rd),
             RI_SETUP, scenario, {case_id, "_B3"});
    for (int byte_index = 2; byte_index >= 0; byte_index--)
    begin
      emit_raw(encode_shift_i(7'h00, 8, rd, 3'b001, rd),
               RI_SETUP, scenario,
               $sformatf("%s_SHIFT_%0d", case_id, byte_index));
      emit_raw(encode_i(int'(value[byte_index*8 +: 8]), rd, 3'b000, rd),
               RI_SETUP, scenario,
               $sformatf("%s_BYTE_%0d", case_id, byte_index));
    end
  endfunction

  function void initialize_all_registers(input ri_scenario_e scenario);
    for (int i = 1; i < 32; i++)
      emit_raw(encode_i(i * 37, 0, 3'b000, i[4:0]),
               RI_SETUP, scenario, $sformatf("INIT_X%0d", i));
  endfunction

  // Random-only initialization: retain ordinary values in half of the file,
  // while making boundary/sign patterns common inputs to subsequent targets.
  function void initialize_mixed_registers(input ri_scenario_e scenario);
    bit [31:0] seeds[0:7];
    seeds = '{32'h0000_0000, 32'h0000_0001, 32'hffff_ffff, 32'h7fff_ffff,
              32'h8000_0000, 32'haaaa_aaaa, 32'h5555_5555, 32'h0000_001f};

    for (int i = 1; i < 16; i++)
      load_constant(i[4:0], seeds[i % 8], scenario,
                    $sformatf("MIX_X%0d", i));

    for (int i = 16; i < 32; i++)
      emit_raw(encode_i(i * 37, 0, 3'b000, i[4:0]),
               RI_SETUP, scenario, $sformatf("MIX_X%0d", i));
  endfunction

  function void emit_binary_case(
    input ri_operation_e op, input bit [31:0] src1,
    input bit [31:0] src2, input ri_scenario_e scenario,
    input string case_id
  );
    load_constant(1, src1, scenario, {case_id, "_SRC1"});
    load_constant(2, src2, scenario, {case_id, "_SRC2"});
    emit_target_with_readback(op, 1, 2, 3, 0, 0, scenario, case_id);
  endfunction

  function void emit_i_case(
    input ri_operation_e op, input bit [31:0] src1,
    input int signed immediate, input ri_scenario_e scenario,
    input string case_id
  );
    load_constant(1, src1, scenario, {case_id, "_SRC1"});
    emit_target_with_readback(op, 1, 0, 3, immediate,
                              immediate[4:0], scenario, case_id);
  endfunction
endclass

class rv32i_ri_sanity_sequence extends rv32i_ri_base_sequence;
  `uvm_object_utils(rv32i_ri_sanity_sequence)

  function new(string name = "rv32i_ri_sanity_sequence");
    super.new(name);
  endfunction

  virtual task body();
    begin_program();
    load_constant(1, 32'd5,         RI_SCENARIO_SANITY, "SANITY_SRC1");
    load_constant(2, 32'hffff_fff0, RI_SCENARIO_SANITY, "SANITY_SRC2");
    load_constant(3, 32'd32,        RI_SCENARIO_SANITY, "SANITY_SHIFT");

    emit_target_with_readback(RI_ADD,  1, 2,  4, 0, 0, RI_SCENARIO_SANITY, "SANITY_ADD");
    emit_target_with_readback(RI_SUB,  1, 2,  5, 0, 0, RI_SCENARIO_SANITY, "SANITY_SUB");
    emit_target_with_readback(RI_SLL,  1, 3,  6, 0, 0, RI_SCENARIO_SANITY, "SANITY_SLL");
    emit_target_with_readback(RI_SLT,  2, 1,  7, 0, 0, RI_SCENARIO_SANITY, "SANITY_SLT");
    emit_target_with_readback(RI_SLTU, 2, 1,  8, 0, 0, RI_SCENARIO_SANITY, "SANITY_SLTU");
    emit_target_with_readback(RI_XOR,  1, 2,  9, 0, 0, RI_SCENARIO_SANITY, "SANITY_XOR");
    emit_target_with_readback(RI_SRL,  2, 3, 10, 0, 0, RI_SCENARIO_SANITY, "SANITY_SRL");
    emit_target_with_readback(RI_SRA,  2, 1, 11, 0, 0, RI_SCENARIO_SANITY, "SANITY_SRA");
    emit_target_with_readback(RI_OR,   1, 2, 12, 0, 0, RI_SCENARIO_SANITY, "SANITY_OR");
    emit_target_with_readback(RI_AND,  1, 2, 13, 0, 0, RI_SCENARIO_SANITY, "SANITY_AND");

    emit_target_with_readback(RI_ADDI,  1, 0, 14,   -5,  0, RI_SCENARIO_SANITY, "SANITY_ADDI");
    emit_target_with_readback(RI_SLTI,  2, 0, 15,   -1,  0, RI_SCENARIO_SANITY, "SANITY_SLTI");
    emit_target_with_readback(RI_SLTIU, 1, 0, 16,   -1,  0, RI_SCENARIO_SANITY, "SANITY_SLTIU");
    emit_target_with_readback(RI_XORI,  1, 0, 17,   -1,  0, RI_SCENARIO_SANITY, "SANITY_XORI");
    emit_target_with_readback(RI_ORI,   1, 0, 18, 12'h120, 0, RI_SCENARIO_SANITY, "SANITY_ORI");
    emit_target_with_readback(RI_ANDI,  2, 0, 19,    7,  0, RI_SCENARIO_SANITY, "SANITY_ANDI");
    emit_target_with_readback(RI_SLLI,  1, 0, 20,    0, 31, RI_SCENARIO_SANITY, "SANITY_SLLI");
    emit_target_with_readback(RI_SRLI,  2, 0, 21,    0,  4, RI_SCENARIO_SANITY, "SANITY_SRLI");
    emit_target_with_readback(RI_SRAI,  2, 0, 22,    0,  2, RI_SCENARIO_SANITY, "SANITY_SRAI");

    emit_target_with_readback(RI_ADDI, 0, 0, 23, 1, 0,
                              RI_SCENARIO_SANITY, "SANITY_X0_SOURCE");
    // Attempt the x0 write, then copy x0 through each source port into a
    // nonzero register. A direct x0 readback would only retest the zero MUX.
    emit_operation(RI_ADDI, 1, 0, 0, 123, 0, RI_TARGET,
                   RI_SCENARIO_SANITY, "SANITY_X0_WRITE_ATTEMPT");
    emit_target_with_readback(RI_ADDI, 0, 0, 24, 0, 0,
                              RI_SCENARIO_SANITY, "SANITY_X0_COPY_CHECK");
    emit_operation(RI_ADD, 1, 0, 0, 0, 0, RI_TARGET,
                   RI_SCENARIO_SANITY, "SANITY_X0_WRITE_ATTEMPT_R");
    emit_target_with_readback(RI_ADD, 0, 0, 25, 0, 0,
                              RI_SCENARIO_SANITY, "SANITY_X0_COPY_CHECK_R");
    end_program();
  endtask
endclass

// =================================================================
// 5. BOUNDARY SEQUENCE
// =================================================================
class rv32i_ri_boundary_sequence extends rv32i_ri_base_sequence;
  `uvm_object_utils(rv32i_ri_boundary_sequence)

  function new(string name = "rv32i_ri_boundary_sequence");
    super.new(name);
  endfunction

  virtual task body();
    ri_operation_e imm_ops[0:5];
    ri_operation_e shift_i_ops[0:2];
    bit [31:0] cmp_a[0:11];
    bit [31:0] cmp_b[0:11];
    bit [31:0] logic_a[0:6];
    bit [31:0] logic_b[0:6];
    bit [31:0] shift_src[0:4];
    int signed imm_values[0:6];
    int unsigned shamt_values[0:4];
    int unsigned rshift_values[0:9];

    begin_program();

    // ADD/SUB immediately below, at, and across signed/unsigned boundaries.
    emit_binary_case(RI_ADD, 32'h0000_0000, 32'h0000_0000, RI_SCENARIO_BOUNDARY, "ADD_ZERO");
    emit_binary_case(RI_ADD, 32'h7fff_fffe, 32'h0000_0001, RI_SCENARIO_BOUNDARY, "ADD_BELOW_SIGNED_MAX");
    emit_binary_case(RI_ADD, 32'h7fff_ffff, 32'h0000_0000, RI_SCENARIO_BOUNDARY, "ADD_AT_SIGNED_MAX");
    emit_binary_case(RI_ADD, 32'h7fff_ffff, 32'h0000_0001, RI_SCENARIO_BOUNDARY, "ADD_POS_OVERFLOW");
    emit_binary_case(RI_ADD, 32'h8000_0001, 32'hffff_ffff, RI_SCENARIO_BOUNDARY, "ADD_ABOVE_SIGNED_MIN");
    emit_binary_case(RI_ADD, 32'h8000_0000, 32'hffff_ffff, RI_SCENARIO_BOUNDARY, "ADD_NEG_OVERFLOW");
    emit_binary_case(RI_ADD, 32'hffff_ffff, 32'h0000_0001, RI_SCENARIO_BOUNDARY, "ADD_UNSIGNED_CARRY");

    emit_binary_case(RI_SUB, 32'h0000_0000, 32'h0000_0000, RI_SCENARIO_BOUNDARY, "SUB_ZERO");
    emit_binary_case(RI_SUB, 32'h0000_0001, 32'h0000_0001, RI_SCENARIO_BOUNDARY, "SUB_EQUAL");
    emit_binary_case(RI_SUB, 32'h0000_0000, 32'h0000_0001, RI_SCENARIO_BOUNDARY, "SUB_UNSIGNED_BORROW");
    emit_binary_case(RI_SUB, 32'h8000_0001, 32'h0000_0001, RI_SCENARIO_BOUNDARY, "SUB_AT_SIGNED_MIN");
    emit_binary_case(RI_SUB, 32'h8000_0000, 32'h0000_0001, RI_SCENARIO_BOUNDARY, "SUB_NEG_OVERFLOW");
    emit_binary_case(RI_SUB, 32'h7fff_ffff, 32'hffff_ffff, RI_SCENARIO_BOUNDARY, "SUB_POS_OVERFLOW");

    // Comparison equality, zero crossing, and signed/unsigned end points.
    cmp_a = '{32'd0, 32'hffff_ffff, 32'hffff_ffff, 32'd0, 32'd1,
              32'hffff_ffff, 32'd1, 32'h8000_0000, 32'h7fff_ffff,
              32'hffff_ffff, 32'd0, 32'd1};
    cmp_b = '{32'd0, 32'hffff_ffff, 32'd0, 32'd1, 32'd0,
              32'd1, 32'hffff_ffff, 32'h7fff_ffff, 32'h8000_0000,
              32'd0, 32'hffff_ffff, 32'd2};
    for (int op_index = 0; op_index < 2; op_index++)
    begin
      ri_operation_e cmp_op;
      cmp_op = (op_index == 0) ? RI_SLT : RI_SLTU;
      for (int i = 0; i < 12; i++)
        emit_binary_case(cmp_op, cmp_a[i], cmp_b[i], RI_SCENARIO_BOUNDARY,
          $sformatf("%s_COMPARE_%0d", operation_name(cmp_op), i));
    end

    // Logic boundaries are represented by high-information bit patterns.
    logic_a = '{32'h0000_0000, 32'h0000_0000, 32'hffff_ffff,
                32'haaaa_aaaa, 32'haaaa_aaaa, 32'h8000_0000,
                32'h1234_5678};
    logic_b = '{32'h0000_0000, 32'hffff_ffff, 32'hffff_ffff,
                32'h5555_5555, 32'haaaa_aaaa, 32'h0000_0001,
                32'h8765_4321};
    for (int op_index = 0; op_index < 3; op_index++)
    begin
      ri_operation_e logic_op;
      logic_op = (op_index == 0) ? RI_XOR :
                 (op_index == 1) ? RI_OR : RI_AND;
      for (int i = 0; i < 7; i++)
        emit_binary_case(logic_op, logic_a[i], logic_b[i], RI_SCENARIO_BOUNDARY,
          $sformatf("%s_LOGIC_%0d", operation_name(logic_op), i));
    end

    // R shifts cross both 31->32 and 63->64 masking boundaries.
    shift_src = '{32'h0000_0000, 32'h0000_0001, 32'h7fff_ffff,
                  32'h8000_0000, 32'hffff_ffff};
    rshift_values = '{0, 1, 16, 30, 31, 32, 33, 63, 64, 65};
    for (int op_index = 0; op_index < 3; op_index++)
    begin
      ri_operation_e shift_op;
      shift_op = (op_index == 0) ? RI_SLL :
                 (op_index == 1) ? RI_SRL : RI_SRA;
      for (int i = 0; i < 10; i++)
        emit_binary_case(shift_op, shift_src[i % 5], rshift_values[i],
          RI_SCENARIO_BOUNDARY,
          $sformatf("%s_RSHIFT_%0d", operation_name(shift_op), rshift_values[i]));
    end

    // Legal non-shift I immediates: both endpoints and nearest values.
    imm_ops = '{RI_ADDI, RI_SLTI, RI_SLTIU, RI_XORI, RI_ORI, RI_ANDI};
    imm_values = '{-2048, -2047, -1, 0, 1, 2046, 2047};
    for (int op_index = 0; op_index < 6; op_index++)
      for (int i = 0; i < 7; i++)
        emit_i_case(imm_ops[op_index],
          (op_index inside {1, 2}) ? 32'h8000_0000 : 32'haaaa_aaaa,
          imm_values[i], RI_SCENARIO_BOUNDARY,
          $sformatf("%s_IMM_%0d", operation_name(imm_ops[op_index]), i));

    // Explicit LT/EQ/GT relations for immediate compares.
    emit_i_case(RI_SLTI,  32'hffff_ffff, -1, RI_SCENARIO_BOUNDARY, "SLTI_REL_EQ");
    emit_i_case(RI_SLTI,  32'hffff_ffff,  0, RI_SCENARIO_BOUNDARY, "SLTI_REL_LT");
    emit_i_case(RI_SLTI,  32'hffff_ffff, -2, RI_SCENARIO_BOUNDARY, "SLTI_REL_GT");
    emit_i_case(RI_SLTIU, 32'h0000_0001,  1, RI_SCENARIO_BOUNDARY, "SLTIU_REL_EQ");
    emit_i_case(RI_SLTIU, 32'h0000_0001,  2, RI_SCENARIO_BOUNDARY, "SLTIU_REL_LT");
    emit_i_case(RI_SLTIU, 32'h0000_0001,  0, RI_SCENARIO_BOUNDARY, "SLTIU_REL_GT");

    // Legal shift-I range.  32 is deliberately absent because it is illegal.
    shift_i_ops = '{RI_SLLI, RI_SRLI, RI_SRAI};
    shamt_values = '{0, 1, 16, 30, 31};
    for (int op_index = 0; op_index < 3; op_index++)
      for (int i = 0; i < 5; i++)
      begin
        load_constant(1, shift_src[(op_index + i) % 5],
                      RI_SCENARIO_BOUNDARY,
                      $sformatf("%s_SRC_%0d", operation_name(shift_i_ops[op_index]), i));
        emit_target_with_readback(shift_i_ops[op_index], 1, 0, 3,
          0, shamt_values[i][4:0], RI_SCENARIO_BOUNDARY,
          $sformatf("%s_SHAMT_%0d", operation_name(shift_i_ops[op_index]), shamt_values[i]));
      end

    end_program();
  endtask
endclass

// =================================================================
// 6. REGISTER-FILE ACCESS SEQUENCE
// =================================================================
class rv32i_ri_rf_access_sequence extends rv32i_ri_base_sequence;
  `uvm_object_utils(rv32i_ri_rf_access_sequence)

  function new(string name = "rv32i_ri_rf_access_sequence");
    super.new(name);
  endfunction

  virtual task body();
    begin_program();
    initialize_all_registers(RI_SCENARIO_RF_ACCESS);

    // Observe every register through both architectural read ports.
    for (int i = 0; i < 32; i++)
    begin
      emit_operation(RI_ADDI, i[4:0], 0, 0, 0, 0, RI_TARGET,
                     RI_SCENARIO_RF_ACCESS, $sformatf("RF_RS1_X%0d", i));
      emit_operation(RI_ADD, 0, i[4:0], 0, 0, 0, RI_TARGET,
                     RI_SCENARIO_RF_ACCESS, $sformatf("RF_RS2_X%0d", i));
    end

    // Rotations close op*rs1, R-op*rs2 and op*rd pairwise crosses together.
    for (int op_value = int'(RI_ADD); op_value <= int'(RI_SRAI); op_value++)
    begin
      ri_operation_e op;
      op = ri_operation_e'(op_value);
      for (int i = 0; i < 32; i++)
      begin
        bit [4:0] rs1;
        bit [4:0] rs2;
        bit [4:0] rd;
        rs1 = i[4:0];
        rs2 = (i + 23) % 32;
        rd  = (i + 11) % 32;
        emit_target_with_readback(op, rs1, rs2, rd, 1, 1,
          RI_SCENARIO_RF_ACCESS,
          $sformatf("RF_%s_ADDR_%0d", operation_name(op), i));
      end

      // Alias bins are explicit and mutually exclusive.
      if (is_r_operation(op))
      begin
        emit_target_with_readback(op, 1, 2, 3, 0, 1, RI_SCENARIO_RF_ACCESS,
          {"RF_", operation_name(op), "_ALL_DIFFERENT"});
        emit_target_with_readback(op, 1, 2, 1, 0, 1, RI_SCENARIO_RF_ACCESS,
          {"RF_", operation_name(op), "_RD_RS1"});
        emit_target_with_readback(op, 1, 2, 2, 0, 1, RI_SCENARIO_RF_ACCESS,
          {"RF_", operation_name(op), "_RD_RS2"});
        emit_target_with_readback(op, 1, 1, 2, 0, 1, RI_SCENARIO_RF_ACCESS,
          {"RF_", operation_name(op), "_RS1_RS2"});
        emit_target_with_readback(op, 1, 1, 1, 0, 1, RI_SCENARIO_RF_ACCESS,
          {"RF_", operation_name(op), "_ALL_EQUAL"});
      end
      else
      begin
        emit_target_with_readback(op, 1, 0, 2, 1, 1, RI_SCENARIO_RF_ACCESS,
          {"RF_", operation_name(op), "_RD_NE_RS1"});
        emit_target_with_readback(op, 1, 0, 1, 1, 1, RI_SCENARIO_RF_ACCESS,
          {"RF_", operation_name(op), "_RD_EQ_RS1"});
      end

    end

    // Close R operation x dependency shape x gap.  The SETUP writes reset
    // producer history; READBACK is then the observable producer.  gap=3 is
    // representative of the cp_gap long_gap ([3:4095]) bin.
    for (int op_value = int'(RI_ADD); op_value <= int'(RI_AND); op_value++)
      for (int dep_kind = 1; dep_kind <= 3; dep_kind++)
        for (int gap = 0; gap <= 3; gap++)
        begin
          ri_operation_e op;
          op = ri_operation_e'(op_value);
          load_constant(28, 32'h0000_0011, RI_SCENARIO_RF_ACCESS,
            $sformatf("RF_R3_%s_D%0d_G%0d_A", operation_name(op), dep_kind, gap));
          load_constant(29, 32'h0000_0022, RI_SCENARIO_RF_ACCESS,
            $sformatf("RF_R3_%s_D%0d_G%0d_B", operation_name(op), dep_kind, gap));
          if (dep_kind inside {1, 3})
            emit_readback(28, RI_SCENARIO_RF_ACCESS,
              $sformatf("RF_R3_%s_D%0d_G%0d_P1", operation_name(op), dep_kind, gap));
          if (dep_kind inside {2, 3})
            emit_readback(29, RI_SCENARIO_RF_ACCESS,
              $sformatf("RF_R3_%s_D%0d_G%0d_P2", operation_name(op), dep_kind, gap));
          repeat (gap)
            emit_operation(RI_ADDI, 0, 0, 0, 0, 0, RI_SETUP,
              RI_SCENARIO_RF_ACCESS,
              $sformatf("RF_R3_%s_D%0d_G%0d_PAD", operation_name(op), dep_kind, gap));
          emit_operation(op, 28, 29, 30, 1, 1, RI_TARGET,
            RI_SCENARIO_RF_ACCESS,
            $sformatf("RF_R3_%s_D%0d_G%0d_TARGET", operation_name(op), dep_kind, gap));
        end

    // I-type has only an rs1 dependency because it has no architectural rs2
    // source.  No combinations are ignored: all 9 x 1 x 4 are executable.
    for (int op_value = int'(RI_ADDI); op_value <= int'(RI_SRAI); op_value++)
      for (int gap = 0; gap <= 3; gap++)
      begin
        ri_operation_e op;
        op = ri_operation_e'(op_value);
        load_constant(28, 32'h0000_0011, RI_SCENARIO_RF_ACCESS,
          $sformatf("RF_I3_%s_G%0d_A", operation_name(op), gap));
        emit_readback(28, RI_SCENARIO_RF_ACCESS,
          $sformatf("RF_I3_%s_G%0d_P1", operation_name(op), gap));
        repeat (gap)
          emit_operation(RI_ADDI, 0, 0, 0, 0, 0, RI_SETUP,
            RI_SCENARIO_RF_ACCESS,
            $sformatf("RF_I3_%s_G%0d_PAD", operation_name(op), gap));
        emit_operation(op, 28, 0, 30, 1, 1, RI_TARGET,
          RI_SCENARIO_RF_ACCESS,
          $sformatf("RF_I3_%s_G%0d_TARGET", operation_name(op), gap));
      end

    end_program();
  endtask
endclass

// =================================================================
// 7. OPERAND-PROFILE PAIRWISE SEQUENCE
// =================================================================
class rv32i_ri_operand_profile_sequence extends rv32i_ri_base_sequence;
  `uvm_object_utils(rv32i_ri_operand_profile_sequence)

  function new(string name = "rv32i_ri_operand_profile_sequence");
    super.new(name);
  endfunction

  virtual task body();
    bit [31:0] value_profile[0:8];
    int unsigned shamt_profile[0:8];

    value_profile = '{32'h0000_0000, 32'h0000_0001,
                      32'hffff_ffff, 32'h7fff_ffff,
                      32'h8000_0000, 32'haaaa_aaaa,
                      32'h5555_5555, 32'h1234_5678,
                      32'h8765_4321};
    shamt_profile = '{0, 1, 2, 7, 15, 16, 23, 30, 31};

    begin_program();

    // Keep one copy of each source-value class in x1..x9.  The R-type loop
    // below intentionally closes operation x src1-class x src2-class: this
    // is a value-profile cross, not a register-number Cartesian cross.
    for (int i = 0; i < 9; i++)
      load_constant(i + 1, value_profile[i],
                    RI_SCENARIO_OPERAND_PROFILE,
                    $sformatf("PROFILE_R_SRC_%0d", i));

    // Every R operation sees every ordered pair of the nine value classes.
    // x31 is kept separate from x1..x9 so no source profile is overwritten.
    for (int op_value = int'(RI_ADD); op_value <= int'(RI_AND); op_value++)
    begin
      ri_operation_e op;
      op = ri_operation_e'(op_value);
      for (int src1_index = 0; src1_index < 9; src1_index++)
        for (int src2_index = 0; src2_index < 9; src2_index++)
          emit_target_with_readback(op, src1_index + 1,
            src2_index + 1, 31, 0, 0,
            RI_SCENARIO_OPERAND_PROFILE,
            $sformatf("PROFILE_%s_S1_%0d_S2_%0d", operation_name(op),
                      src1_index, src2_index));
    end

    // Each I-type operation sees every rs1 class. Immediate boundary closure
    // is owned by boundary_cg; shift operations still span legal shamt values.
    for (int op_value = int'(RI_ADDI); op_value <= int'(RI_SRAI); op_value++)
    begin
      ri_operation_e op;
      int unsigned rotation;
      op = ri_operation_e'(op_value);
      rotation = op_value - int'(RI_ADDI);
      for (int i = 0; i < 9; i++)
      begin
        load_constant(1, value_profile[i], RI_SCENARIO_OPERAND_PROFILE,
          $sformatf("PROFILE_%s_%0d_SRC", operation_name(op), i));
        if (op inside {RI_SLLI, RI_SRLI, RI_SRAI})
          emit_target_with_readback(op, 1, 0, 3, 0,
            shamt_profile[(i + rotation) % 9][4:0],
            RI_SCENARIO_OPERAND_PROFILE,
            $sformatf("PROFILE_%s_%0d", operation_name(op), i));
        else
          emit_target_with_readback(op, 1, 0, 3, 0, 0,
            RI_SCENARIO_OPERAND_PROFILE,
            $sformatf("PROFILE_%s_%0d", operation_name(op), i));
      end
    end

    end_program();
  endtask
endclass

// =================================================================
// 8. CLEAN RANDOM AND X-PROPAGATION SEQUENCES
// =================================================================
class rv32i_ri_random_sequence extends rv32i_ri_base_sequence;
  `uvm_object_utils(rv32i_ri_random_sequence)

  int unsigned balanced_per_operation = 20;
  int unsigned free_random_count      = 620;
  int unsigned dependency_rate        = 35;
  int unsigned alias_rate             = 30;
  int unsigned boundary_rate          = 40;
  int unsigned readback_rate          = 10;

  function new(string name = "rv32i_ri_random_sequence");
    super.new(name);
  endfunction

  function void emit_random_target(
    input ri_operation_e op, input int unsigned serial,
    inout bit [4:0] previous_rd
  );
    bit [4:0] rs1, rs2, rd, shamt;
    int signed immediate;
    bit [31:0] boundary_values[0:7];

    boundary_values = '{32'h0000_0000, 32'h0000_0001,
                        32'hffff_ffff, 32'h7fff_ffff,
                        32'h8000_0000, 32'haaaa_aaaa,
                        32'h5555_5555, $urandom};
    rs1 = $urandom_range(31, 0);
    rs2 = $urandom_range(31, 0);
    rd = $urandom_range(31, 0);
    shamt = $urandom_range(31, 0);
    immediate = $urandom_range(4095, 0);
    if (immediate > 2047)
      immediate -= 4096;

    if ((previous_rd != 0) && ($urandom_range(99, 0) < dependency_rate))
    begin
      if (is_r_operation(op) && $urandom_range(1, 0)) rs2 = previous_rd;
      else rs1 = previous_rd;
    end

    if ($urandom_range(99, 0) < alias_rate)
    begin
      if (is_r_operation(op))
        case ($urandom_range(3, 0))
          0: rd = rs1;
          1: rd = rs2;
          2: rs2 = rs1;
          3: begin rs2 = rs1; rd = rs1; end
        endcase
      else
        rd = rs1;
    end

    // A coprime stride gives exactly boundary_rate injections per 100 targets.
    // This preserves random values/addresses while bounding program size.
    if (((serial * 37 + 17) % 100) < boundary_rate)
    begin
      if (rs1 == 0) rs1 = $urandom_range(31, 1);
      load_constant(rs1, boundary_values[$urandom_range(7, 0)],
                    RI_SCENARIO_RANDOM, $sformatf("RANDOM_SETUP_%0d", serial));
    end

    emit_operation(op, rs1, rs2, rd, immediate, shamt, RI_TARGET,
                   RI_SCENARIO_RANDOM,
                   $sformatf("RANDOM_%s_%0d", operation_name(op), serial));
    if ((rd != 0) && ($urandom_range(99, 0) < readback_rate))
      emit_readback(rd, RI_SCENARIO_RANDOM,
                    $sformatf("RANDOM_%s_%0d", operation_name(op), serial));
    if (rd != 0) previous_rd = rd;
  endfunction

  // These three legal immediate boundary values are deliberately injected
  // into every random-run database.  They are non-shift I-type operations;
  // shift-I instructions continue to use the independently constrained shamt.
  function void emit_directed_immediate_boundaries();
    load_constant(1, 32'haaaa_aaaa, RI_SCENARIO_RANDOM, "RANDOM_IMM_SRC");
    emit_target_with_readback(RI_ADDI, 1, 0, 3, -2047, 0,
      RI_SCENARIO_RANDOM, "RANDOM_IMM_MIN_PLUS1");
    emit_target_with_readback(RI_XORI, 1, 0, 3, 2046, 0,
      RI_SCENARIO_RANDOM, "RANDOM_IMM_MAX_MINUS1");
    emit_target_with_readback(RI_ANDI, 1, 0, 3, 2047, 0,
      RI_SCENARIO_RANDOM, "RANDOM_IMM_MAX");
  endfunction

  virtual task body();
    bit [4:0] previous_rd;
    int unsigned serial;
    begin_program();
    initialize_mixed_registers(RI_SCENARIO_RANDOM);
    emit_directed_immediate_boundaries();
    previous_rd = 0;
    serial = 0;

    for (int op_value = int'(RI_ADD); op_value <= int'(RI_SRAI); op_value++)
      repeat (balanced_per_operation)
      begin
        emit_random_target(ri_operation_e'(op_value), serial, previous_rd);
        serial++;
      end

    repeat (free_random_count)
    begin
      ri_operation_e random_op;
      random_op = ri_operation_e'($urandom_range(int'(RI_SRAI), int'(RI_ADD)));
      emit_random_target(random_op, serial, previous_rd);
      serial++;
    end
    end_program();
  endtask
endclass

class rv32i_ri_xprop_sequence extends rv32i_ri_base_sequence;
  `uvm_object_utils(rv32i_ri_xprop_sequence)

  function new(string name = "rv32i_ri_xprop_sequence");
    super.new(name);
  endfunction

  virtual task body();
    begin_program();
    load_constant(1, 32'd5, RI_SCENARIO_XPROP, "XPROP_KNOWN_X1");
    load_constant(2, 32'hffff_fffd, RI_SCENARIO_XPROP, "XPROP_KNOWN_X2");
    // x5/x6 deliberately remain uninitialized.
    emit_operation(RI_ADDI, 5, 0, 10, 1, 0, RI_XPROP,
                   RI_SCENARIO_XPROP, "XPROP_UNKNOWN_RS1_ITYPE");
    emit_operation(RI_ADD, 5, 1, 11, 0, 0, RI_XPROP,
                   RI_SCENARIO_XPROP, "XPROP_UNKNOWN_RS1_RTYPE");
    emit_operation(RI_ADD, 1, 6, 12, 0, 0, RI_XPROP,
                   RI_SCENARIO_XPROP, "XPROP_UNKNOWN_RS2_RTYPE");
    emit_operation(RI_ADD, 5, 6, 15, 0, 0, RI_XPROP,
                   RI_SCENARIO_XPROP, "XPROP_UNKNOWN_BOTH_RTYPE");
    emit_operation(RI_XOR, 10, 1, 13, 0, 0, RI_XPROP,
                   RI_SCENARIO_XPROP, "XPROP_UNKNOWN_RESULT_REUSED");
    emit_operation(RI_ADDI, 0, 0, 5, 17, 0, RI_XPROP,
                   RI_SCENARIO_XPROP, "XPROP_KNOWN_OVERWRITE");
    emit_operation(RI_ADDI, 5, 0, 5, 0, 0, RI_XPROP,
                   RI_SCENARIO_XPROP, "XPROP_RECOVERY_READBACK");
    emit_operation(RI_ADD, 1, 2, 14, 0, 0, RI_XPROP,
                   RI_SCENARIO_XPROP, "XPROP_KNOWN_PATH_AFTER_X");
    end_program();
  endtask
endclass

// Optional negative test: characterize unsupported encodings separately from
// clean regression, where assertion/scoreboard errors would be failures.
class rv32i_ri_illegal_sequence extends rv32i_ri_base_sequence;
  `uvm_object_utils(rv32i_ri_illegal_sequence)

  function new(string name = "rv32i_ri_illegal_sequence");
    super.new(name);
  endfunction

  virtual task body();
    begin_program();
    load_constant(1, 32'h0000_000a, RI_SCENARIO_SANITY, "ILL_SRC1");
    load_constant(2, 32'h0000_0003, RI_SCENARIO_SANITY, "ILL_SRC2");

    emit_raw({7'b0000001, 5'd2, 5'd1, 3'b000, 5'd10, OP_RTYPE},
             RI_TARGET, RI_SCENARIO_SANITY, "ILLEGAL_MUL_ENCODING");
    emit_raw({7'b0100000, 5'd2, 5'd1, 3'b100, 5'd11, OP_RTYPE},
             RI_TARGET, RI_SCENARIO_SANITY, "ILLEGAL_XOR_ALT");
    emit_raw({7'b0000001, 5'd4, 5'd1, 3'b001, 5'd12, OP_ITYPE},
             RI_TARGET, RI_SCENARIO_SANITY, "ILLEGAL_SLLI_SHAMT5");
    end_program();
  endtask
endclass

// =================================================================
// 8. INSTRUCTION-MEMORY DRIVER
// =================================================================
class rv32i_imem_driver extends uvm_driver #(rv32i_program_item);
  `uvm_component_utils(rv32i_imem_driver)

  virtual rv32i_core_if vif;
  uvm_analysis_port #(rv32i_program_item) program_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    program_ap = new("program_ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual rv32i_core_if)::get(this, "", "vif", vif))
      `uvm_fatal("IMEM_DRV", "Failed to get rv32i_core_if")
  endfunction

  virtual task run_phase(uvm_phase phase);
    rv32i_program_item req;

    forever
    begin
      seq_item_port.get_next_item(req);

      if (req.instructions.size() > vif.IMEM_DEPTH)
        `uvm_fatal("IMEM_DRV", $sformatf(
          "Program has %0d words, instruction memory holds %0d",
          req.instructions.size(), vif.IMEM_DEPTH))

      // Keep reset asserted while replacing the complete instruction image.
      vif.drv_cb.rst_n <= 1'b0;
      for (int i = 0; i < vif.IMEM_DEPTH; i++)
        vif.instr_mem[i] = vif.STOP_INSTR;
      foreach (req.instructions[i])
        vif.instr_mem[i] = req.instructions[i];

      // Publish the intended image before execution starts so the scoreboard
      // can independently check the instruction observed at each commit PC.
      program_ap.write(req);

      repeat (3)
        @(vif.drv_cb);
      vif.drv_cb.rst_n <= 1'b1;

      seq_item_port.item_done();
    end
  endtask
endclass

// =================================================================
// 9. INSTRUCTION-MEMORY AGENT
// =================================================================
class rv32i_imem_agent extends uvm_agent;
  `uvm_component_utils(rv32i_imem_agent)

  rv32i_imem_driver                    drv;
  uvm_sequencer #(rv32i_program_item)  sqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv = rv32i_imem_driver::type_id::create("drv", this);
    sqr = uvm_sequencer#(rv32i_program_item)::type_id::create("sqr", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass

// =================================================================
// 10. PASSIVE COMMIT MONITOR
// =================================================================
class rv32i_probe_monitor extends uvm_monitor;
  `uvm_component_utils(rv32i_probe_monitor)

  virtual rv32i_probe_if vif;
  uvm_analysis_port #(rv32i_commit_item) commit_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    commit_ap = new("commit_ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual rv32i_probe_if)::get(this, "", "vif", vif))
      `uvm_fatal("PROBE_MON", "Failed to get bound rv32i_probe_if")
  endfunction

  virtual task run_phase(uvm_phase phase);
    rv32i_commit_item tr;

    forever
    begin
      @(vif.mon_cb);

      if (!vif.mon_cb.rst_n || vif.mon_cb.commit_valid)
      begin
        tr = rv32i_commit_item::type_id::create("tr");
        tr.reset   = !vif.mon_cb.rst_n;
        tr.pc      = vif.mon_cb.pc;
        tr.instr   = vif.mon_cb.instr;
        tr.rd_we   = vif.mon_cb.commit_rd_we;
        tr.rd      = vif.mon_cb.commit_rd;
        tr.rd_data = vif.mon_cb.commit_wdata;
        tr.rs1     = vif.mon_cb.instr[19:15];
        tr.rs2     = vif.mon_cb.instr[24:20];
        tr.rs1_data = vif.mon_cb.idex_rs1;
        tr.rs2_data = vif.mon_cb.idex_rs2;
        tr.immediate = vif.mon_cb.idex_imm;
        tr.pc_en = vif.mon_cb.pc_en;
        tr.branch = vif.mon_cb.branch;
        tr.jal = vif.mon_cb.jal;
        tr.jalr = vif.mon_cb.jalr;
        tr.rf_we = vif.mon_cb.rf_we;
        tr.alusrc_sel = vif.mon_cb.alusrc_sel;
        tr.alu_control = vif.mon_cb.alu_control;
        tr.rf_srcsel = vif.mon_cb.rf_srcsel;
        tr.alu_result = vif.mon_cb.alu_result;
        tr.wb_data = vif.mon_cb.wb_data;
        tr.transfer = vif.mon_cb.transfer;
        tr.bus_we = vif.mon_cb.bus_we;

        commit_ap.write(tr);
      end
    end
  endtask

endclass

// =================================================================
// 11. ARCHITECTURAL SCOREBOARD
// =================================================================
class rv32i_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(rv32i_scoreboard)

  uvm_analysis_imp_commit  #(rv32i_commit_item,  rv32i_scoreboard) commit_imp;
  uvm_analysis_imp_program #(rv32i_program_item, rv32i_scoreboard) program_imp;

  logic [31:0] ref_gpr [0:31];
  bit          ref_valid [0:31];
  bit [31:0]   expected_program[$];
  ri_scenario_e expected_scenarios[$];
  bit [31:0]   expected_pc;

  int unsigned commit_count;
  int unsigned total_commit_count;
  int unsigned pass_count;
  int unsigned fail_count;
  int unsigned skip_count;
  int unsigned data_check_count;
  int unsigned data_skip_count;
  int unsigned scenario_pass_count [int unsigned];
  int unsigned scenario_fail_count [int unsigned];
  int unsigned scenario_skip_count [int unsigned];
  int unsigned scenario_total_count[int unsigned];
  event        commit_seen;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    commit_imp = new("commit_imp", this);
    program_imp = new("program_imp", this);
    reset_arch_state();
  endfunction

  function void reset_arch_state();
    expected_pc = 32'd0;
    commit_count = 0;
    for (int i = 0; i < 32; i++)
    begin
      ref_gpr[i] = 32'd0;
      ref_valid[i] = 1'b0;
    end
    ref_gpr[0] = 32'd0;
    ref_valid[0] = 1'b1;
  endfunction

  function automatic logic [31:0] sign_extend_i(input logic [31:0] instr);
    return {{20{instr[31]}}, instr[31:20]};
  endfunction

  function automatic string scenario_name(input ri_scenario_e scenario);
    case (scenario)
      RI_SCENARIO_SANITY:    return "SANITY";
      RI_SCENARIO_BOUNDARY:  return "BOUNDARY";
      RI_SCENARIO_RF_ACCESS: return "RF_ACCESS";
      RI_SCENARIO_OPERAND_PROFILE: return "OPERAND_PROFILE";
      RI_SCENARIO_RANDOM:    return "RANDOM";
      RI_SCENARIO_XPROP:     return "XPROP";
      default:               return "UNKNOWN";
    endcase
  endfunction

  function void record_scenario_result(
    input ri_scenario_e scenario,
    input bit passed,
    input bit skipped
  );
    int unsigned id;
    id = int'(scenario);
    scenario_total_count[id]++;
    if (!passed)
      scenario_fail_count[id]++;
    else if (skipped)
      scenario_skip_count[id]++;
    else
      scenario_pass_count[id]++;
  endfunction

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
      // [FIX] Keep the arithmetic shift outside a mixed-sign ternary.
      10'b0100000_101: return $signed(src1) >>> src2[4:0];
      10'b0000000_110: return src1 | src2;
      10'b0000000_111: return src1 & src2;
      default: begin
        `uvm_error("SCB_ENCODING", $sformatf(
          "Illegal R-type encoding: funct7=%07b funct3=%03b",
          instr[31:25], instr[14:12]))
        return 32'd0;
      end
    endcase
  endfunction

  function automatic logic [31:0] execute_itype(
    input logic [31:0] instr,
    input logic [31:0] src1
  );
    logic [31:0] immediate;
    immediate = sign_extend_i(instr);

    case (instr[14:12])
      3'b000: return src1 + immediate;
      3'b001: begin
        if (instr[31:25] == 7'b0000000)
          return src1 << instr[24:20];
        `uvm_error("SCB_ENCODING", $sformatf(
          "Illegal SLLI encoding: funct7=%07b", instr[31:25]))
        return 32'd0;
      end
      3'b010: return ($signed(src1) < $signed(immediate)) ? 32'd1 : 32'd0;
      3'b011: return (src1 < immediate) ? 32'd1 : 32'd0;
      3'b100: return src1 ^ immediate;
      3'b101: begin // [FIX] Keep the arithmetic shift in an explicitly signed branch.
        if (instr[31:25] == 7'b0100000)
          return $signed(src1) >>> instr[24:20];
        else if (instr[31:25] == 7'b0000000)
          return src1 >> instr[24:20];
        `uvm_error("SCB_ENCODING", $sformatf(
          "Illegal SRLI/SRAI encoding: funct7=%07b", instr[31:25]))
        return 32'd0;
      end
      3'b110: return src1 | immediate;
      3'b111: return src1 & immediate;
      default: return 32'd0;
    endcase
  endfunction

  // Receives the program directly from the instruction driver. This prevents
  // the observed DUT instruction from becoming its own expected value.
  virtual function void write_program(rv32i_program_item req);
    string program_name;

    expected_program.delete();
    expected_scenarios.delete();
    foreach (req.instructions[i])
    begin
      expected_program.push_back(req.instructions[i]);
      expected_scenarios.push_back((i < req.scenarios.size()) ?
                                   req.scenarios[i] : RI_SCENARIO_SANITY);
    end
    reset_arch_state();

    program_name = (expected_scenarios.size() == 0) ? "EMPTY" :
                   scenario_name(expected_scenarios[0]);

    `uvm_info("SCB", $sformatf("[%-10s] PROGRAM START  WORDS:%0d",
                                program_name, expected_program.size()), UVM_LOW)
  endfunction

  virtual function void write_commit(rv32i_commit_item actual);
    logic [31:0] expected_instr;
    logic [31:0] expected_data;
    logic [31:0] src1_data;
    logic [31:0] src2_data;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic        expected_we;
    bit          sources_known;
    bit          transaction_pass;
    ri_scenario_e scenario;

    if (actual.reset)
    begin
      reset_arch_state();
      return;
    end

    transaction_pass = 1'b1;
    sources_known = 1'b1;

    if (commit_count >= expected_program.size())
    begin
      fail_count++;
      `uvm_error("SCB", $sformatf("Unexpected extra commit: %s",
                                   actual.convert2string()))
      -> commit_seen;
      return;
    end

    expected_instr = expected_program[commit_count];
    scenario = expected_scenarios[commit_count];

    if (actual.pc !== expected_pc)
    begin
      transaction_pass = 1'b0;
      `uvm_error("SCB_PC", $sformatf(
        "Commit %0d PC mismatch: expected=%08h actual=%08h",
        commit_count, expected_pc, actual.pc))
    end

    if (actual.instr !== expected_instr)
    begin
      transaction_pass = 1'b0;
      `uvm_error("SCB_INSTR", $sformatf(
        "Commit %0d instruction mismatch: expected=%08h actual=%08h",
        commit_count, expected_instr, actual.instr))
    end

    rs1 = expected_instr[19:15];
    rs2 = expected_instr[24:20];
    rd  = expected_instr[11:7];

    if (!ref_valid[rs1])
    begin
      sources_known = 1'b0;
      `uvm_info("SCB_SKIP", $sformatf(
        "Commit %0d data check skipped: rs1=x%0d is uninitialized",
        commit_count, rs1), UVM_MEDIUM)
    end

    if ((expected_instr[6:0] == OP_RTYPE) && !ref_valid[rs2])
    begin
      sources_known = 1'b0;
      `uvm_info("SCB_SKIP", $sformatf(
        "Commit %0d data check skipped: rs2=x%0d is uninitialized",
        commit_count, rs2), UVM_MEDIUM)
    end

    src1_data = ref_gpr[rs1];
    src2_data = ref_gpr[rs2];
    expected_data = 32'd0;

    if (sources_known)
    begin
      case (expected_instr[6:0])
        OP_RTYPE: expected_data = execute_rtype(expected_instr, src1_data, src2_data);
        OP_ITYPE: expected_data = execute_itype(expected_instr, src1_data);
        default:
        begin
          transaction_pass = 1'b0;
          `uvm_error("SCB_OPCODE", $sformatf(
            "Unsupported opcode at commit %0d: %02h",
            commit_count, expected_instr[6:0]))
        end
      endcase
    end

    expected_we = (rd != 5'd0);

    if (actual.rd !== rd)
    begin
      transaction_pass = 1'b0;
      `uvm_error("SCB_RD", $sformatf(
        "Commit %0d rd mismatch: expected=x%0d actual=x%0d",
        commit_count, rd, actual.rd))
    end

    if (actual.rd_we !== expected_we)
    begin
      transaction_pass = 1'b0;
      `uvm_error("SCB_WE", $sformatf(
        "Commit %0d write-enable mismatch: expected=%b actual=%b",
        commit_count, expected_we, actual.rd_we))
    end

    // Check the raw DUT control separately from commit_rd_we, which is a
    // probe-derived signal gated by commit_valid and rd!=x0.
    if (actual.rf_we !== 1'b1)
    begin
      transaction_pass = 1'b0;
      `uvm_error("SCB_RAW_WE", $sformatf(
        "Commit %0d: raw rf_we must be 1 for committed R/I (rd=x%0d), got %b",
        commit_count, rd, actual.rf_we))
    end

    // Compare the ALU/write-back value even when rd=x0. The register update is
    // discarded architecturally, but the execute operation remains observable.
    if (sources_known && actual.rd_data !== expected_data)
    begin
      transaction_pass = 1'b0;
      `uvm_error("SCB_DATA", $sformatf(
        "Commit %0d data mismatch: expected=%08h actual=%08h (%s)",
        commit_count, expected_data, actual.rd_data,
        actual.convert2string()))
    end

    if (sources_known)
      data_check_count++;
    else
      data_skip_count++;

    if (expected_we)
    begin
      if (sources_known)
      begin
        ref_gpr[rd] = expected_data;
        ref_valid[rd] = 1'b1;
      end
      else
      begin
        // An unknown source taints the architectural destination. Clearing the
        // validity prevents a stale, previously known value from being reused.
        ref_gpr[rd] = 'x;
        ref_valid[rd] = 1'b0;
      end
    end
    ref_gpr[0] = 32'd0;
    ref_valid[0] = 1'b1;

    if (!transaction_pass)
      fail_count++;
    else if (!sources_known)
      skip_count++;
    else
      pass_count++;

    record_scenario_result(scenario, transaction_pass, !sources_known);

    commit_count++;
    total_commit_count++;
    expected_pc += 32'd4;
    -> commit_seen;
  endfunction

  virtual task wait_for_commits(input int unsigned target);
    while (commit_count < target)
      @commit_seen;
  endtask

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (commit_count != expected_program.size())
      `uvm_error("SCB_COUNT", $sformatf(
        "Expected %0d commits but observed %0d",
        expected_program.size(), commit_count))
  endfunction

  virtual function void report_phase(uvm_phase phase);
    real data_check_rate;
    int unsigned id;
    int unsigned scenario_pass;
    int unsigned scenario_fail;
    int unsigned scenario_skip;
    ri_scenario_e scenario;

    super.report_phase(phase);
    if (total_commit_count == 0)
      data_check_rate = 0.0;
    else
      data_check_rate = 100.0 * data_check_count / total_commit_count;

    `uvm_info("SCB_SUMMARY",
      "================ RV32I SCOREBOARD SUMMARY BY SCENARIO ================",
      UVM_LOW)

    for (id = int'(RI_SCENARIO_SANITY); id <= int'(RI_SCENARIO_XPROP); id++)
    begin
      if (scenario_total_count.exists(id))
      begin
        scenario = ri_scenario_e'(id);
        scenario_pass = scenario_pass_count.exists(id) ? scenario_pass_count[id] : 0;
        scenario_fail = scenario_fail_count.exists(id) ? scenario_fail_count[id] : 0;
        scenario_skip = scenario_skip_count.exists(id) ? scenario_skip_count[id] : 0;
        `uvm_info("SCB_SUMMARY", $sformatf(
          "%-18s PASS:%-5d FAIL:%-5d SKIP:%-5d TOTAL:%0d",
          scenario_name(scenario), scenario_pass, scenario_fail,
          scenario_skip, scenario_total_count[id]), UVM_LOW)
      end
    end

    `uvm_info("SCB_SUMMARY", $sformatf(
      "%-18s PASS:%-5d FAIL:%-5d SKIP:%-5d TOTAL:%0d",
      "ALL", pass_count, fail_count, skip_count,
      pass_count + fail_count + skip_count), UVM_LOW)
    `uvm_info("SCB_SUMMARY", $sformatf(
      "DATA CHECK         CHECKED:%0d  SKIPPED:%0d  RATE:%0.2f%%",
      data_check_count, data_skip_count, data_check_rate), UVM_LOW)
    `uvm_info("SCB_SUMMARY",
      "======================================================================",
      UVM_LOW)
  endfunction
endclass

// =================================================================
// 12. INTENT-AWARE FUNCTIONAL COVERAGE
// =================================================================
class rv32i_coverage extends uvm_component;
  `uvm_component_utils(rv32i_coverage)

  uvm_analysis_imp_commit  #(rv32i_commit_item, rv32i_coverage) commit_imp;
  uvm_analysis_imp_program #(rv32i_program_item, rv32i_coverage) program_imp;

  ri_instr_role_e expected_roles[$];
  ri_scenario_e   expected_scenarios[$];
  string          expected_case_ids[$];
  bit             planned_case[string];
  bit             hit_case[string];
  bit             scenario_seen[0:5];

  int last_writer[0:31];
  ri_instr_role_e last_writer_role[0:31];
  int unsigned sample_index;
  int unsigned sample_count;

  ri_operation_e  sample_op;
  ri_instr_role_e sample_role;
  ri_scenario_e   sample_scenario;
  ri_alias_e      sample_alias;
  ri_dependency_e sample_dependency;
  ri_value_class_e sample_src_class;
  ri_value_class_e sample_src2_class;
  ri_relation_e   sample_relation;
  ri_sign_pair_e  sample_sign_pair;
  ri_logic_profile_e sample_logic_profile;

  int unsigned sample_rs1;
  int unsigned sample_rs2;
  int unsigned sample_rd;
  int unsigned sample_shamt;
  int unsigned sample_dependency_gap;
  int signed   sample_imm_signed;
  int unsigned sample_signed_event;
  int unsigned sample_unsigned_event;
  bit sample_target;
  bit sample_boundary;
  bit sample_readback;
  bit sample_xprop;
  bit sample_is_r;
  bit sample_is_i;
  bit sample_is_nonshift_i;
  bit sample_is_shift;
  bit sample_is_r_shift;
  bit sample_is_arithmetic;
  bit sample_is_compare;
  bit sample_is_logic;
  bit sample_result_zero;
  bit sample_r_rs2_upper_nonzero;
  int unsigned sample_x_source;
  bit sample_control_known;
  bit sample_x_propagated;

  covergroup instruction_cg;
    option.per_instance = 1;

    cp_operation: coverpoint sample_op iff (sample_target) {
      bins operations[] = {[RI_ADD:RI_SRAI]};
    }
    cp_r_operation: coverpoint sample_op iff (sample_target && sample_is_r) {
      bins operations[] = {[RI_ADD:RI_AND]};
    }
    cp_i_operation: coverpoint sample_op iff (sample_target && sample_is_i) {
      bins operations[] = {[RI_ADDI:RI_SRAI]};
    }
    cp_rs1: coverpoint sample_rs1 iff (sample_target) {
      bins registers[] = {[0:31]};
    }
    cp_r_rs1: coverpoint sample_rs1 iff (sample_target && sample_is_r) {
      bins registers[] = {[0:31]};
    }
    cp_i_rs1: coverpoint sample_rs1 iff (sample_target && sample_is_i) {
      bins registers[] = {[0:31]};
    }
    cp_rs2: coverpoint sample_rs2 iff (sample_target && sample_is_r) {
      bins registers[] = {[0:31]};
    }
    cp_rd: coverpoint sample_rd iff (sample_target) {
      bins registers[] = {[0:31]};
    }
    cp_r_alias: coverpoint sample_alias iff (sample_target && sample_is_r) {
      bins all_different = {RI_ALIAS_ALL_DIFFERENT};
      bins rd_rs1 = {RI_ALIAS_RD_RS1};
      bins rd_rs2 = {RI_ALIAS_RD_RS2};
      bins rs1_rs2 = {RI_ALIAS_RS1_RS2};
      bins all_equal = {RI_ALIAS_ALL_EQUAL};
    }
    cp_i_alias: coverpoint sample_alias iff (sample_target && sample_is_i) {
      bins different = {RI_ALIAS_I_DIFFERENT};
      bins equal = {RI_ALIAS_I_EQUAL};
    }

    cx_operation_rd: cross cp_operation, cp_rd;
    cx_r_operation_rs1: cross cp_r_operation, cp_r_rs1;
    cx_r_operation_rs2: cross cp_r_operation, cp_rs2;
    cx_i_operation_rs1: cross cp_i_operation, cp_i_rs1;
    cx_r_operation_alias: cross cp_r_operation, cp_r_alias;
    cx_i_operation_alias: cross cp_i_operation, cp_i_alias;
  endgroup

  covergroup boundary_cg;
    option.per_instance = 1;

    cp_arith_op: coverpoint sample_op
      iff (sample_target && sample_boundary && sample_is_arithmetic) {
      bins add = {RI_ADD}; bins sub = {RI_SUB};
    }
    cp_signed_event: coverpoint sample_signed_event
      iff (sample_target && sample_boundary && sample_is_arithmetic) {
      bins normal = {0}; bins positive_overflow = {1};
      bins negative_overflow = {2};
    }
    cp_add_unsigned: coverpoint sample_unsigned_event
      iff (sample_target && sample_boundary && sample_op == RI_ADD) {
      bins normal = {0}; bins carry = {1};
    }
    cp_sub_unsigned: coverpoint sample_unsigned_event
      iff (sample_target && sample_boundary && sample_op == RI_SUB) {
      bins normal = {0}; bins borrow = {2};
    }
    cp_zero_result: coverpoint sample_result_zero
      iff (sample_target && sample_boundary && sample_is_arithmetic);

    cp_compare_op: coverpoint sample_op
      iff (sample_target && sample_boundary && sample_is_compare) {
      bins operations[] = {RI_SLT, RI_SLTU, RI_SLTI, RI_SLTIU};
    }
    cp_r_compare_op: coverpoint sample_op
      iff (sample_target && sample_boundary &&
           sample_op inside {RI_SLT, RI_SLTU}) {
      bins operations[] = {RI_SLT, RI_SLTU};
    }
    cp_relation: coverpoint sample_relation
      iff (sample_target && sample_boundary && sample_is_compare);
    cp_sign_pair: coverpoint sample_sign_pair
      iff (sample_target && sample_boundary &&
           sample_op inside {RI_SLT, RI_SLTU});

    cp_logic_op: coverpoint sample_op
      iff (sample_target && sample_boundary &&
           sample_op inside {RI_XOR, RI_OR, RI_AND}) {
      bins operations[] = {RI_XOR, RI_OR, RI_AND};
    }
    cp_logic_profile: coverpoint sample_logic_profile
      iff (sample_target && sample_boundary &&
           sample_op inside {RI_XOR, RI_OR, RI_AND});

    cp_nonshift_i_op: coverpoint sample_op
      iff (sample_target && sample_boundary && sample_is_nonshift_i) {
      bins operations[] = {RI_ADDI, RI_SLTI, RI_SLTIU,
                           RI_XORI, RI_ORI, RI_ANDI};
    }
    cp_imm_boundary: coverpoint sample_imm_signed
      iff (sample_target && sample_boundary && sample_is_nonshift_i) {
      bins min = {-2048}; bins min_plus1 = {-2047};
      bins neg_one = {-1}; bins zero = {0}; bins one = {1};
      bins max_minus1 = {2046}; bins max = {2047};
    }

    cp_shift_op: coverpoint sample_op
      iff (sample_target && sample_boundary && sample_is_shift) {
      bins operations[] = {RI_SLL, RI_SRL, RI_SRA,
                           RI_SLLI, RI_SRLI, RI_SRAI};
    }
    cp_effective_shamt: coverpoint sample_shamt
      iff (sample_target && sample_boundary && sample_is_shift) {
      bins zero = {0}; bins one = {1}; bins middle = {[2:29]};
      bins pre_max = {30}; bins max = {31};
    }
    cp_r_shift_op: coverpoint sample_op
      iff (sample_target && sample_boundary && sample_is_r_shift) {
      bins operations[] = {RI_SLL, RI_SRL, RI_SRA};
    }
    cp_r_rs2_upper: coverpoint sample_r_rs2_upper_nonzero
      iff (sample_target && sample_boundary && sample_is_r_shift);
    cp_shift_src: coverpoint sample_src_class
      iff (sample_target && sample_boundary && sample_is_shift) {
      bins zero = {RI_VAL_ZERO}; bins one = {RI_VAL_ONE};
      bins neg_one = {RI_VAL_NEG_ONE};
      bins signed_max = {RI_VAL_SIGNED_MAX};
      bins signed_min = {RI_VAL_SIGNED_MIN};
    }

    cx_arith_signed: cross cp_arith_op, cp_signed_event;
    cx_compare_relation: cross cp_compare_op, cp_relation;
    cx_compare_sign: cross cp_r_compare_op, cp_sign_pair;
    cx_logic_profile: cross cp_logic_op, cp_logic_profile;
    cx_immediate_boundary: cross cp_nonshift_i_op, cp_imm_boundary;
    cx_shift_amount: cross cp_shift_op, cp_effective_shamt;
    cx_r_shift_upper: cross cp_r_shift_op, cp_r_rs2_upper;
    cx_shift_source: cross cp_shift_op, cp_shift_src;
  endgroup

  covergroup operand_profile_cg;
    option.per_instance = 1;

    cp_r_operation: coverpoint sample_op
      iff (sample_target && sample_is_r) {
      bins operations[] = {[RI_ADD:RI_AND]};
    }
    cp_i_operation: coverpoint sample_op
      iff (sample_target && sample_is_i) {
      bins operations[] = {[RI_ADDI:RI_SRAI]};
    }
    cp_shift_i_operation: coverpoint sample_op
      iff (sample_target && sample_is_i && sample_is_shift) {
      bins operations[] = {RI_SLLI, RI_SRLI, RI_SRAI};
    }
    cp_src1_class: coverpoint sample_src_class
      iff (sample_target) {
      bins classes[] = {[RI_VAL_ZERO:RI_VAL_NEG_OTHER]};
    }
    cp_src2_class: coverpoint sample_src2_class
      iff (sample_target && sample_is_r) {
      bins classes[] = {[RI_VAL_ZERO:RI_VAL_NEG_OTHER]};
    }
    cp_shift_amount: coverpoint sample_shamt
      iff (sample_target && sample_is_i && sample_is_shift) {
      bins zero = {0}; bins one = {1}; bins low = {[2:7]};
      bins middle = {[8:23]}; bins high = {[24:30]}; bins max = {31};
    }

    cx_r_operation_src1: cross cp_r_operation, cp_src1_class;
    cx_r_operation_src2: cross cp_r_operation, cp_src2_class;
    cx_r_source_pair: cross cp_src1_class, cp_src2_class;
    // The pairwise crosses above cannot show whether a particular R operation
    // saw a particular ordered pair of source value classes together.
    cx_r_operation_source_pair: cross cp_r_operation, cp_src1_class,
                                      cp_src2_class;
    cx_i_operation_src1: cross cp_i_operation, cp_src1_class;
    cx_shift_i_amount: cross cp_shift_i_operation, cp_shift_amount;
  endgroup

  // Random-only metric. These crosses intentionally remain outside every
  // mandatory coverage gate so seed investment can be measured incrementally.
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

    cx_r_op_alias: cross cp_r_op, cp_alias;
    cx_r_op_dep: cross cp_r_op, cp_dep;
    cx_i_op_src1: cross cp_i_op, cp_src1;
    cx_r_op_src_alias: cross cp_r_op, cp_src1, cp_alias;
    cx_r_src_pair_dep: cross cp_src1, cp_src2, cp_dep;
  endgroup

  covergroup dependency_cg;
    option.per_instance = 1;
    cp_r_operation: coverpoint sample_op
      iff ((sample_target || sample_readback) && sample_is_r &&
           sample_dependency != RI_DEP_NONE) {
      bins operations[] = {[RI_ADD:RI_AND]};
    }
    cp_i_operation: coverpoint sample_op
      iff ((sample_target || sample_readback) && sample_is_i &&
           sample_dependency != RI_DEP_NONE) {
      bins operations[] = {[RI_ADDI:RI_SRAI]};
    }
    cp_r_dependency: coverpoint sample_dependency
      iff ((sample_target || sample_readback) && sample_is_r &&
           sample_dependency != RI_DEP_NONE) {
      bins rs1 = {RI_DEP_RS1}; bins rs2 = {RI_DEP_RS2};
      bins both = {RI_DEP_BOTH};
    }
    cp_i_dependency: coverpoint sample_dependency
      iff ((sample_target || sample_readback) && sample_is_i &&
           sample_dependency != RI_DEP_NONE) {
      bins rs1 = {RI_DEP_RS1};
    }
    cp_dependency: coverpoint sample_dependency
      iff ((sample_target || sample_readback) && sample_dependency != RI_DEP_NONE) {
      bins rs1 = {RI_DEP_RS1}; bins rs2 = {RI_DEP_RS2};
      bins both = {RI_DEP_BOTH};
    }
    cp_gap: coverpoint sample_dependency_gap
      iff ((sample_target || sample_readback) && sample_dependency != RI_DEP_NONE) {
      bins immediate = {0}; bins one_gap = {1}; bins two_gap = {2};
      bins long_gap = {[3:4095]};
    }
    cx_r_operation_dependency: cross cp_r_operation, cp_r_dependency;
    cx_i_operation_dependency: cross cp_i_operation, cp_i_dependency;
    cx_dependency_gap: cross cp_dependency, cp_gap;
    // All three coverpoints have the same TARGET/READBACK and non-NONE
    // eligibility guards, so these crosses contain only real dependencies.
    cx_r_operation_dependency_gap: cross cp_r_operation, cp_r_dependency,
                                         cp_gap;
    cx_i_operation_dependency_gap: cross cp_i_operation, cp_i_dependency,
                                         cp_gap;
  endgroup

  covergroup xprop_cg;
    option.per_instance = 1;
    cp_x_source: coverpoint sample_x_source iff (sample_xprop) {
      bins known = {0}; bins rs1 = {1}; bins rs2 = {2}; bins both = {3};
    }
    cp_control_known: coverpoint sample_control_known iff (sample_xprop) {
      bins known = {1}; illegal_bins unknown = {0};
    }
    cp_operation: coverpoint sample_op iff (sample_xprop) {
      bins exercised[] = {RI_ADD, RI_XOR, RI_ADDI};
    }
    cp_result_propagated: coverpoint sample_x_propagated
      iff (sample_xprop && sample_x_source != 0 &&
           sample_op inside {RI_ADD, RI_SUB, RI_XOR, RI_ADDI, RI_XORI}) {
      bins propagated = {1};
      illegal_bins lost = {0};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    instruction_cg = new();
    boundary_cg = new();
    operand_profile_cg = new();
    random_combo_cg = new();
    dependency_cg = new();
    xprop_cg = new();
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    commit_imp = new("commit_imp", this);
    program_imp = new("program_imp", this);
    reset_dependency_state();
  endfunction

  function void reset_dependency_state();
    sample_index = 0;
    for (int i = 0; i < 32; i++)
    begin
      last_writer[i] = -1;
      last_writer_role[i] = RI_SETUP;
    end
  endfunction

  function automatic ri_operation_e decode_operation(input logic [31:0] instr);
    if (instr[6:0] == OP_RTYPE)
      case (instr[14:12])
        3'b000: return instr[30] ? RI_SUB : RI_ADD;
        3'b001: return RI_SLL; 3'b010: return RI_SLT;
        3'b011: return RI_SLTU; 3'b100: return RI_XOR;
        3'b101: return instr[30] ? RI_SRA : RI_SRL;
        3'b110: return RI_OR; 3'b111: return RI_AND;
      endcase
    else if (instr[6:0] == OP_ITYPE)
      case (instr[14:12])
        3'b000: return RI_ADDI; 3'b010: return RI_SLTI;
        3'b011: return RI_SLTIU; 3'b100: return RI_XORI;
        3'b110: return RI_ORI; 3'b111: return RI_ANDI;
        3'b001: return RI_SLLI;
        3'b101: return instr[30] ? RI_SRAI : RI_SRLI;
      endcase
    return RI_OP_UNKNOWN;
  endfunction

  function automatic ri_value_class_e classify_value(input logic [31:0] value);
    case (value)
      32'h0000_0000: return RI_VAL_ZERO;
      32'h0000_0001: return RI_VAL_ONE;
      32'hffff_ffff: return RI_VAL_NEG_ONE;
      32'h7fff_ffff: return RI_VAL_SIGNED_MAX;
      32'h8000_0000: return RI_VAL_SIGNED_MIN;
      32'haaaa_aaaa: return RI_VAL_ALT_A;
      32'h5555_5555: return RI_VAL_ALT_5;
      default: return value[31] ? RI_VAL_NEG_OTHER : RI_VAL_POS_OTHER;
    endcase
  endfunction

  function automatic ri_alias_e classify_alias(
    input bit is_r, input int unsigned rs1,
    input int unsigned rs2, input int unsigned rd
  );
    if (!is_r) return (rd == rs1) ? RI_ALIAS_I_EQUAL : RI_ALIAS_I_DIFFERENT;
    if ((rd == rs1) && (rs1 == rs2)) return RI_ALIAS_ALL_EQUAL;
    if (rd == rs1) return RI_ALIAS_RD_RS1;
    if (rd == rs2) return RI_ALIAS_RD_RS2;
    if (rs1 == rs2) return RI_ALIAS_RS1_RS2;
    return RI_ALIAS_ALL_DIFFERENT;
  endfunction

  function automatic ri_sign_pair_e classify_sign_pair(
    input logic [31:0] a, input logic [31:0] b
  );
    if (a == 0 && b == 0) return RI_SIGN_ZERO_ZERO;
    if (a == 0) return b[31] ? RI_SIGN_ZERO_NEG : RI_SIGN_ZERO_POS;
    if (b == 0) return a[31] ? RI_SIGN_NEG_ZERO : RI_SIGN_POS_ZERO;
    if (!a[31] && !b[31]) return RI_SIGN_POS_POS;
    if (!a[31] && b[31]) return RI_SIGN_POS_NEG;
    if (a[31] && !b[31]) return RI_SIGN_NEG_POS;
    return RI_SIGN_NEG_NEG;
  endfunction

  function automatic ri_logic_profile_e classify_logic_profile(
    input logic [31:0] a, input logic [31:0] b
  );
    if (a == 0 && b == 0) return RI_LOGIC_ZERO_ZERO;
    if ((a == 0 && b == '1) || (a == '1 && b == 0)) return RI_LOGIC_ZERO_ONES;
    if (a == '1 && b == '1) return RI_LOGIC_ONES_ONES;
    if ((a == 32'haaaa_aaaa && b == 32'h5555_5555) ||
        (a == 32'h5555_5555 && b == 32'haaaa_aaaa)) return RI_LOGIC_ALT_COMPLEMENT;
    if ((a == 32'haaaa_aaaa && b == a) ||
        (a == 32'h5555_5555 && b == a)) return RI_LOGIC_ALT_SAME;
    if ((a == 32'h8000_0000 && b == 1) ||
        (a == 1 && b == 32'h8000_0000)) return RI_LOGIC_MSB_LSB;
    return RI_LOGIC_OTHER;
  endfunction

  virtual function void write_program(rv32i_program_item program_item);
    expected_roles.delete();
    expected_scenarios.delete();
    expected_case_ids.delete();
    foreach (program_item.instructions[i])
    begin
      expected_roles.push_back((i < program_item.roles.size()) ? program_item.roles[i] : RI_TARGET);
      expected_scenarios.push_back((i < program_item.scenarios.size()) ?
                                   program_item.scenarios[i] : RI_SCENARIO_SANITY);
      expected_case_ids.push_back((i < program_item.case_ids.size()) ?
                                  program_item.case_ids[i] : $sformatf("WORD_%0d", i));
      if (i < program_item.scenarios.size())
        scenario_seen[int'(program_item.scenarios[i])] = 1'b1;
      if ((i < program_item.roles.size()) &&
          (program_item.roles[i] inside {RI_TARGET, RI_XPROP}) &&
          (i < program_item.scenarios.size()) &&
          (program_item.scenarios[i] != RI_SCENARIO_RANDOM))
        planned_case[expected_case_ids[i]] = 1'b1;
    end
    reset_dependency_state();
  endfunction

  virtual function void write_commit(rv32i_commit_item actual);
    logic [32:0] unsigned_sum;
    logic [31:0] arithmetic_result;
    int rs1_gap, rs2_gap;
    bit rs1_dep, rs2_dep;

    if (actual.reset)
    begin
      reset_dependency_state();
      return;
    end
    if (sample_index >= expected_roles.size()) return;

    sample_role = expected_roles[sample_index];
    sample_scenario = expected_scenarios[sample_index];
    sample_op = decode_operation(actual.instr);
    sample_rs1 = actual.rs1;
    sample_rs2 = actual.rs2;
    sample_rd = actual.rd;
    sample_is_r = (actual.instr[6:0] == OP_RTYPE);
    sample_is_i = (actual.instr[6:0] == OP_ITYPE);
    sample_target = (sample_role == RI_TARGET);
    sample_readback = (sample_role == RI_READBACK);
    sample_xprop = (sample_role == RI_XPROP);
    sample_boundary = (sample_scenario == RI_SCENARIO_BOUNDARY);
    sample_is_nonshift_i = sample_is_i &&
      !(sample_op inside {RI_SLLI, RI_SRLI, RI_SRAI});
    sample_is_shift = sample_op inside {RI_SLL, RI_SRL, RI_SRA,
                                        RI_SLLI, RI_SRLI, RI_SRAI};
    sample_is_r_shift = sample_op inside {RI_SLL, RI_SRL, RI_SRA};
    sample_is_arithmetic = sample_op inside {RI_ADD, RI_SUB};
    sample_is_compare = sample_op inside {RI_SLT, RI_SLTU, RI_SLTI, RI_SLTIU};
    sample_is_logic = sample_op inside {RI_XOR, RI_OR, RI_AND,
                                        RI_XORI, RI_ORI, RI_ANDI};
    sample_imm_signed = $signed(actual.instr[31:20]);
    sample_shamt = sample_is_r ? actual.rs2_data[4:0] : actual.instr[24:20];
    sample_r_rs2_upper_nonzero = |actual.rs2_data[31:5];
    sample_src_class = classify_value(actual.rs1_data);
    sample_src2_class = classify_value(actual.rs2_data);
    sample_alias = classify_alias(sample_is_r, sample_rs1, sample_rs2, sample_rd);
    sample_sign_pair = classify_sign_pair(actual.rs1_data,
      sample_is_r ? actual.rs2_data : actual.immediate);
    sample_logic_profile = classify_logic_profile(actual.rs1_data,
      sample_is_r ? actual.rs2_data : actual.immediate);
    arithmetic_result = (sample_op == RI_SUB) ?
                        actual.rs1_data - actual.rs2_data :
                        actual.rs1_data + actual.rs2_data;
    sample_result_zero = (arithmetic_result == 0);
    sample_control_known = !$isunknown({actual.pc, actual.instr,
      actual.rd_we, actual.rd, actual.pc_en, actual.branch, actual.jal,
      actual.jalr, actual.rf_we, actual.alusrc_sel, actual.alu_control,
      actual.rf_srcsel, actual.transfer, actual.bus_we});
    sample_x_source = sample_is_r ?
                      {$isunknown(actual.rs2_data), $isunknown(actual.rs1_data)} :
                      {1'b0, $isunknown(actual.rs1_data)};
    sample_x_propagated = $isunknown(actual.alu_result) &&
                          $isunknown(actual.wb_data);

    if (sample_op inside {RI_SLT, RI_SLTI})
      sample_relation = ($signed(actual.rs1_data) < $signed(sample_is_r ? actual.rs2_data : actual.immediate)) ? RI_REL_LT :
                        ($signed(actual.rs1_data) == $signed(sample_is_r ? actual.rs2_data : actual.immediate)) ? RI_REL_EQ : RI_REL_GT;
    else
      sample_relation = (actual.rs1_data < (sample_is_r ? actual.rs2_data : actual.immediate)) ? RI_REL_LT :
                        (actual.rs1_data == (sample_is_r ? actual.rs2_data : actual.immediate)) ? RI_REL_EQ : RI_REL_GT;

    sample_signed_event = 0;
    sample_unsigned_event = 0;
    unsigned_sum = {1'b0, actual.rs1_data} + {1'b0, actual.rs2_data};
    if (sample_op == RI_ADD)
    begin
      if (!actual.rs1_data[31] && !actual.rs2_data[31] && arithmetic_result[31])
        sample_signed_event = 1;
      else if (actual.rs1_data[31] && actual.rs2_data[31] && !arithmetic_result[31])
        sample_signed_event = 2;
      if (unsigned_sum[32]) sample_unsigned_event = 1;
    end
    else if (sample_op == RI_SUB)
    begin
      if (!actual.rs1_data[31] && actual.rs2_data[31] && arithmetic_result[31])
        sample_signed_event = 1;
      else if (actual.rs1_data[31] && !actual.rs2_data[31] && !arithmetic_result[31])
        sample_signed_event = 2;
      if (actual.rs1_data < actual.rs2_data) sample_unsigned_event = 2;
    end

    rs1_dep = (sample_rs1 != 0) && (last_writer[sample_rs1] >= 0) &&
              (last_writer_role[sample_rs1] != RI_SETUP);
    rs2_dep = sample_is_r && (sample_rs2 != 0) &&
              (last_writer[sample_rs2] >= 0) &&
              (last_writer_role[sample_rs2] != RI_SETUP);
    sample_dependency = rs1_dep && rs2_dep ? RI_DEP_BOTH :
                        rs1_dep ? RI_DEP_RS1 : rs2_dep ? RI_DEP_RS2 : RI_DEP_NONE;
    rs1_gap = rs1_dep ? int'(sample_index) - last_writer[sample_rs1] - 1 : 32'h7fff_ffff;
    rs2_gap = rs2_dep ? int'(sample_index) - last_writer[sample_rs2] - 1 : 32'h7fff_ffff;
    sample_dependency_gap = (rs1_gap < rs2_gap) ? rs1_gap : rs2_gap;

    if (sample_role inside {RI_TARGET, RI_XPROP})
      hit_case[expected_case_ids[sample_index]] = 1'b1;

    // Store random cross hits as stable text keys for cross-seed merging.
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

    if (sample_xprop && sample_x_source != 0 &&
        sample_op inside {RI_ADD, RI_SUB, RI_XOR, RI_ADDI, RI_XORI} &&
        !sample_x_propagated)
      `uvm_error("XPROP_RESULT", $sformatf(
        "Source X did not reach both ALU/write-back: case=%s op=%0d ALU=%h WB=%h",
        expected_case_ids[sample_index], sample_op,
        actual.alu_result, actual.wb_data))

    instruction_cg.sample();
    boundary_cg.sample();
    operand_profile_cg.sample();
    random_combo_cg.sample();
    dependency_cg.sample();
    xprop_cg.sample();
    sample_count++;

    if (actual.rd_we && actual.rd != 0)
    begin
      last_writer[actual.rd] = sample_index;
      last_writer_role[actual.rd] = sample_role;
    end
    sample_index++;
  endfunction

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    foreach (planned_case[id])
      if (!hit_case.exists(id) || !hit_case[id])
        `uvm_error("COV_CASE", $sformatf("Planned case was not committed: %s", id))

    if (scenario_seen[int'(RI_SCENARIO_RF_ACCESS)] &&
        instruction_cg.get_inst_coverage() < 99.99)
      `uvm_error("COV_INSTRUCTION", $sformatf(
        "Mandatory instruction/RF coverage is %0.2f%%",
        instruction_cg.get_inst_coverage()))

    if (scenario_seen[int'(RI_SCENARIO_BOUNDARY)] &&
        boundary_cg.get_inst_coverage() < 99.99)
      `uvm_error("COV_BOUNDARY", $sformatf(
        "Mandatory boundary coverage is %0.2f%%",
        boundary_cg.get_inst_coverage()))

    if (scenario_seen[int'(RI_SCENARIO_OPERAND_PROFILE)] &&
        operand_profile_cg.get_inst_coverage() < 99.99)
      `uvm_error("COV_OPERAND_PROFILE", $sformatf(
        "Mandatory operand-profile coverage is %0.2f%%",
        operand_profile_cg.get_inst_coverage()))

    if (scenario_seen[int'(RI_SCENARIO_RF_ACCESS)] &&
        dependency_cg.get_inst_coverage() < 99.99)
      `uvm_error("COV_DEPENDENCY", $sformatf(
        "Mandatory dependency coverage is %0.2f%%",
        dependency_cg.get_inst_coverage()))

    if (scenario_seen[int'(RI_SCENARIO_XPROP)] &&
        xprop_cg.get_inst_coverage() < 99.99)
      `uvm_error("COV_XPROP", $sformatf(
        "Mandatory X-propagation coverage is %0.2f%%",
        xprop_cg.get_inst_coverage()))
  endfunction

  virtual function void report_phase(uvm_phase phase);
    int planned, hit;
    real case_rate;
    bit clean_scenario_seen;
    super.report_phase(phase);
    planned = 0;
    hit = 0;
    foreach (planned_case[id])
    begin
      planned++;
      if (hit_case.exists(id) && hit_case[id]) hit++;
    end
    case_rate = (planned == 0) ? 0.0 : 100.0 * hit / planned;
    clean_scenario_seen = scenario_seen[int'(RI_SCENARIO_SANITY)] ||
                          scenario_seen[int'(RI_SCENARIO_BOUNDARY)] ||
                          scenario_seen[int'(RI_SCENARIO_RF_ACCESS)] ||
                          scenario_seen[int'(RI_SCENARIO_OPERAND_PROFILE)] ||
                          scenario_seen[int'(RI_SCENARIO_RANDOM)];

    `uvm_info("COV_SUMMARY",
      "================ RV32I FUNCTIONAL COVERAGE SUMMARY ===================",
      UVM_LOW)
    `uvm_info("COV_SUMMARY", $sformatf(
      "SAMPLES:%0d  DIRECTED CASES:%0d/%0d (%0.2f%%)",
      sample_count, hit, planned, case_rate), UVM_LOW)

    if (clean_scenario_seen)
      `uvm_info("COV_SUMMARY", $sformatf(
        "instruction_cg : %6.2f%%", instruction_cg.get_inst_coverage()), UVM_LOW)
    else
      `uvm_info("COV_SUMMARY", "instruction_cg : NOT RUN", UVM_LOW)

    if (scenario_seen[int'(RI_SCENARIO_BOUNDARY)])
      `uvm_info("COV_SUMMARY", $sformatf(
        "boundary_cg    : %6.2f%%", boundary_cg.get_inst_coverage()), UVM_LOW)
    else
      `uvm_info("COV_SUMMARY", "boundary_cg    : NOT RUN", UVM_LOW)

    if (scenario_seen[int'(RI_SCENARIO_OPERAND_PROFILE)])
      `uvm_info("COV_SUMMARY", $sformatf(
        "operand_profile_cg: %6.2f%%",
        operand_profile_cg.get_inst_coverage()), UVM_LOW)
    else
      `uvm_info("COV_SUMMARY", "operand_profile_cg: NOT RUN", UVM_LOW)

    if (scenario_seen[int'(RI_SCENARIO_RF_ACCESS)])
      `uvm_info("COV_SUMMARY", $sformatf(
        "dependency_cg  : %6.2f%%", dependency_cg.get_inst_coverage()), UVM_LOW)
    else
      `uvm_info("COV_SUMMARY", "dependency_cg  : NOT RUN", UVM_LOW)

    if (scenario_seen[int'(RI_SCENARIO_XPROP)])
      `uvm_info("COV_SUMMARY", $sformatf(
        "xprop_cg       : %6.2f%%", xprop_cg.get_inst_coverage()), UVM_LOW)
    else
      `uvm_info("COV_SUMMARY", "xprop_cg       : NOT RUN (separate test)", UVM_LOW)

    if (scenario_seen[int'(RI_SCENARIO_RANDOM)])
      `uvm_info("COV_SUMMARY", $sformatf(
        "random_combo_cg: %6.2f%%  <- cross-seed metric (not a gate)",
        random_combo_cg.get_inst_coverage()), UVM_LOW)
    else
      `uvm_info("COV_SUMMARY", "random_combo_cg: NOT RUN", UVM_LOW)

    // Append all observed IDs. COMBO_* entries can be merged without a
    // simulator coverage database via sort -u across repeated runs.
    begin
      int dump_fd;
      dump_fd = $fopen("cov_combo_dump.txt", "a");
      if (dump_fd != 0)
      begin
        foreach (hit_case[id])
          if (hit_case[id]) $fdisplay(dump_fd, "%s", id);
        $fclose(dump_fd);
      end
      else
        `uvm_warning("COV_DUMP", "Could not open cov_combo_dump.txt")
    end

    `uvm_info("COV_SUMMARY",
      "======================================================================",
      UVM_LOW)
  endfunction
endclass

// =================================================================
// 13. UVM ENVIRONMENT
// =================================================================
class rv32i_env extends uvm_env;
  `uvm_component_utils(rv32i_env)

  rv32i_imem_agent    imem_agent;
  rv32i_probe_monitor probe_mon;
  rv32i_scoreboard    scb;
  rv32i_coverage      cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    imem_agent = rv32i_imem_agent::type_id::create("imem_agent", this);
    probe_mon  = rv32i_probe_monitor::type_id::create("probe_mon", this);
    scb        = rv32i_scoreboard::type_id::create("scb", this);
    cov        = rv32i_coverage::type_id::create("cov", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    probe_mon.commit_ap.connect(scb.commit_imp);
    probe_mon.commit_ap.connect(cov.commit_imp);
    imem_agent.drv.program_ap.connect(scb.program_imp);
    imem_agent.drv.program_ap.connect(cov.program_imp);
  endfunction
endclass

// =================================================================
// 14. R/I UVM TESTS
// =================================================================
class rv32i_ri_test extends uvm_test;
  `uvm_component_utils(rv32i_ri_test)

  rv32i_env                    env;
  rv32i_ri_sanity_sequence     sanity_seq;
  rv32i_ri_boundary_sequence   boundary_seq;
  rv32i_ri_rf_access_sequence  rf_access_seq;
  rv32i_ri_operand_profile_sequence operand_profile_seq;
  rv32i_ri_random_sequence     random_seq;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = rv32i_env::type_id::create("env", this);
    sanity_seq = rv32i_ri_sanity_sequence::type_id::create("sanity_seq");
    boundary_seq = rv32i_ri_boundary_sequence::type_id::create("boundary_seq");
    rf_access_seq = rv32i_ri_rf_access_sequence::type_id::create("rf_access_seq");
    operand_profile_seq = rv32i_ri_operand_profile_sequence::type_id::create(
      "operand_profile_seq");
    random_seq = rv32i_ri_random_sequence::type_id::create("random_seq");
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    int log_fd;
    string log_path;

    super.end_of_elaboration_phase(phase);
    if (uvm_config_db#(int)::get(this, "", "rv32i_uvm_log_fd", log_fd))
    begin
      rv32i_configure_hier_report(log_fd);
      if (!uvm_config_db#(string)::get(this, "", "rv32i_uvm_log_path", log_path))
        log_path = "<unknown>";
      `uvm_info("TB_LOG", $sformatf("UVM report log file: %s", log_path), UVM_LOW)
    end
    else
      `uvm_warning("TB_LOG", "No UVM log file handle configured; reports are display-only")
  endfunction

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
    run_one(random_seq);

    // Allow the final assertion and monitor activity to settle.
    phase.phase_done.set_drain_time(this, 20ns);
    phase.drop_objection(this);
  endtask
endclass

// Deterministic suite: one seed closes all mandatory directed gates.
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
    sanity_seq = rv32i_ri_sanity_sequence::type_id::create("sanity_seq");
    boundary_seq = rv32i_ri_boundary_sequence::type_id::create("boundary_seq");
    rf_access_seq = rv32i_ri_rf_access_sequence::type_id::create("rf_access_seq");
    operand_profile_seq = rv32i_ri_operand_profile_sequence::type_id::create(
      "operand_profile_seq");
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    int log_fd;
    string log_path;

    super.end_of_elaboration_phase(phase);
    if (uvm_config_db#(int)::get(this, "", "rv32i_uvm_log_fd", log_fd))
    begin
      rv32i_configure_hier_report(log_fd);
      if (!uvm_config_db#(string)::get(this, "", "rv32i_uvm_log_path", log_path))
        log_path = "<unknown>";
      `uvm_info("TB_LOG", $sformatf("UVM report log file: %s", log_path), UVM_LOW)
    end
    else
      `uvm_warning("TB_LOG", "No UVM log file handle configured; reports are display-only")
  endfunction

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

// Stochastic suite: run repeatedly with different simulator seeds. Directed
// coverage gates stay inactive because their scenarios are not observed.
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

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    int log_fd;
    string log_path;

    super.end_of_elaboration_phase(phase);
    if (uvm_config_db#(int)::get(this, "", "rv32i_uvm_log_fd", log_fd))
    begin
      rv32i_configure_hier_report(log_fd);
      if (!uvm_config_db#(string)::get(this, "", "rv32i_uvm_log_path", log_path))
        log_path = "<unknown>";
      `uvm_info("TB_LOG", $sformatf("UVM report log file: %s", log_path), UVM_LOW)
    end
    else
      `uvm_warning("TB_LOG", "No UVM log file handle configured; reports are display-only")
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    random_seq.start(env.imem_agent.sqr);
    env.scb.wait_for_commits(random_seq.instruction_count);
    phase.phase_done.set_drain_time(this, 20ns);
    phase.drop_objection(this);
  endtask
endclass

class rv32i_ri_illegal_test extends uvm_test;
  `uvm_component_utils(rv32i_ri_illegal_test)

  rv32i_env                 env;
  rv32i_ri_illegal_sequence illegal_seq;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = rv32i_env::type_id::create("env", this);
    illegal_seq = rv32i_ri_illegal_sequence::type_id::create("illegal_seq");
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    illegal_seq.start(env.imem_agent.sqr);
    env.scb.wait_for_commits(illegal_seq.instruction_count);
    phase.phase_done.set_drain_time(this, 20ns);
    phase.drop_objection(this);
  endtask
endclass

// X propagation is intentionally excluded from the clean functional test.
class rv32i_ri_xprop_test extends uvm_test;
  `uvm_component_utils(rv32i_ri_xprop_test)

  rv32i_env               env;
  rv32i_ri_xprop_sequence xprop_seq;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = rv32i_env::type_id::create("env", this);
    xprop_seq = rv32i_ri_xprop_sequence::type_id::create("xprop_seq");
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    int log_fd;
    string log_path;

    super.end_of_elaboration_phase(phase);
    if (uvm_config_db#(int)::get(this, "", "rv32i_uvm_log_fd", log_fd))
    begin
      rv32i_configure_hier_report(log_fd);
      if (!uvm_config_db#(string)::get(this, "", "rv32i_uvm_log_path", log_path))
        log_path = "<unknown>";
      `uvm_info("TB_LOG", $sformatf("UVM report log file: %s", log_path), UVM_LOW)
    end
    else
      `uvm_warning("TB_LOG", "No UVM log file handle configured; reports are display-only")
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    xprop_seq.start(env.imem_agent.sqr);
    env.scb.wait_for_commits(xprop_seq.instruction_count);
    phase.phase_done.set_drain_time(this, 20ns);
    phase.drop_objection(this);
  endtask
endclass

// =================================================================
// 15. SIMULATION TOP
// =================================================================
module tb_rv32i_uvm;
  logic clk = 1'b0;
  int    rv32i_uvm_log_fd;
  string rv32i_uvm_log_prefix;
  string rv32i_uvm_log_arg;
  string rv32i_uvm_log_path;

  always #5 clk = ~clk;

  rv32i_core_if core_vif(clk);

  rv32i_cpu dut (
    .clk        (clk),
    .rst_n      (core_vif.rst_n),
    .instr_code (core_vif.instr_code),
    .instr_addr (core_vif.instr_addr),
    .bus_rdata  (core_vif.bus_rdata),
    .ready      (core_vif.ready),
    .itype      (core_vif.itype),
    .bus_we     (core_vif.bus_we),
    .transfer   (core_vif.transfer),
    .bus_addr   (core_vif.bus_addr),
    .bus_wdata  (core_vif.bus_wdata)
  );

  initial
  begin
    string selected_test;

    // Scripts/sim.sh runs xsim below Vivado/<top>.  The default relative
    // prefix therefore places numbered logs in the project root:
    // rv32i_uvm_report_001.log, rv32i_uvm_report_002.log, ...
    rv32i_uvm_log_prefix = "../../rv32i_uvm_report";
    void'($value$plusargs("RV32I_UVM_LOG_PREFIX=%s", rv32i_uvm_log_prefix));
    if ($value$plusargs("RV32I_UVM_LOG=%s", rv32i_uvm_log_arg))
      rv32i_uvm_log_prefix = rv32i_strip_log_extension(rv32i_uvm_log_arg);

    rv32i_uvm_log_fd = rv32i_open_numbered_report_log(
      rv32i_uvm_log_prefix, rv32i_uvm_log_path);

    // A direct simulator launch may use another working directory.  Fall back
    // to that directory if the project-root-relative path cannot be opened.
    if (rv32i_uvm_log_fd == 0)
    begin
      rv32i_uvm_log_prefix = "rv32i_uvm_report";
      rv32i_uvm_log_fd = rv32i_open_numbered_report_log(
        rv32i_uvm_log_prefix, rv32i_uvm_log_path);
    end

    if (rv32i_uvm_log_fd == 0)
      $fatal(1, "[TB_LOG] Failed to open numbered UVM report log file");

    rv32i_configure_root_report(rv32i_uvm_log_fd);
    uvm_config_db#(int)::set(
      null, "uvm_test_top", "rv32i_uvm_log_fd", rv32i_uvm_log_fd);
    uvm_config_db#(string)::set(
      null, "uvm_test_top", "rv32i_uvm_log_path", rv32i_uvm_log_path);

    uvm_config_db#(virtual rv32i_core_if)::set(
      null, "uvm_test_top.env.imem_agent*", "vif", core_vif);

    // The probe interface instance is created below the DUT by rv32i_bind.sv.
    uvm_config_db#(virtual rv32i_probe_if)::set(
      null, "uvm_test_top.env.probe_mon", "vif",
      dut.u_rv32i_core_probe.probe_if);

    // Vivado 2020.2's xsim wrapper cannot reliably pass an '=' inside
    // -testplusarg. Keep standard UVM_TESTNAME support and provide flag-only
    // aliases for batch regression on this supported simulator version.
    if ($test$plusargs("RV32I_XPROP"))
      run_test("rv32i_ri_xprop_test");
    else if ($test$plusargs("RV32I_DIRECTED"))
      run_test("rv32i_ri_directed_test");
    else if ($test$plusargs("RV32I_RANDOM"))
      run_test("rv32i_ri_random_test");
    else if ($test$plusargs("RV32I_ILLEGAL"))
      run_test("rv32i_ri_illegal_test");
    else if ($value$plusargs("UVM_TESTNAME=%s", selected_test))
      run_test();
    else
      run_test("rv32i_ri_test");

    if (rv32i_uvm_log_fd != 0)
    begin
      $fdisplay(rv32i_uvm_log_fd, "[TB_LOG] Closed UVM report log file");
      $fclose(rv32i_uvm_log_fd);
    end
  end

  // Prevent a missing commit from hanging a batch regression indefinitely.
  initial
  begin
    #2ms;
    `uvm_fatal("TIMEOUT", "RV32I UVM test exceeded 2 ms")
  end
endmodule
