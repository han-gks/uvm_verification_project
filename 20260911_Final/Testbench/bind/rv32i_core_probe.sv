// Bridge between internal rv32i_cpu signals and the passive probe interface.
// It also hosts the assertion checker so the synthesizable RTL stays unchanged.
module rv32i_core_probe
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

  input logic        ready,
  input logic [31:0] bus_rdata,
  input logic        transfer,
  input logic        bus_we,
  input logic [2:0]  itype,
  input logic [31:0] bus_addr,
  input logic [31:0] bus_wdata
);

  rv32i_probe_if probe_if(clk);

  assign probe_if.rst_n        = rst_n;
  assign probe_if.state        = state;
  assign probe_if.pc           = pc;
  assign probe_if.instr        = instr;
  // R/I instructions retire on the clock edge that ends CPU_EXECUTE.
  assign probe_if.commit_valid = (state == CPU_EXECUTE) &&
                                 ((instr[6:0] == OP_RTYPE) ||
                                  (instr[6:0] == OP_ITYPE));

  // x0 discards writes, so only nonzero destinations are architectural writes.
  assign probe_if.commit_rd_we = probe_if.commit_valid &&
                                 rf_we && (instr[11:7] != 5'd0);

  // The destination register and write-back value form the commit transaction.
  assign probe_if.commit_rd    = instr[11:7];
  assign probe_if.commit_wdata = wb_data;

  assign probe_if.pc_en        = pc_en;
  assign probe_if.branch       = branch;
  assign probe_if.jal          = jal;
  assign probe_if.jalr         = jalr;
  assign probe_if.rf_we        = rf_we;
  assign probe_if.alusrc_sel   = alusrc_sel;
  assign probe_if.alu_control  = alu_control;
  assign probe_if.rf_srcsel    = rf_srcsel;

  assign probe_if.rf_rd1       = rf_rd1;
  assign probe_if.rf_rd2       = rf_rd2;
  assign probe_if.imm_ext      = imm_ext;
  assign probe_if.idex_rs1     = idex_rs1;
  assign probe_if.idex_rs2     = idex_rs2;
  assign probe_if.idex_imm     = idex_imm;
  assign probe_if.alu_src2     = alu_src2;
  assign probe_if.alu_result   = alu_result;
  assign probe_if.wb_data      = wb_data;

  assign probe_if.ready        = ready;
  assign probe_if.bus_rdata    = bus_rdata;
  assign probe_if.transfer     = transfer;
  assign probe_if.bus_we       = bus_we;
  assign probe_if.itype        = itype;
  assign probe_if.bus_addr     = bus_addr;
  assign probe_if.bus_wdata    = bus_wdata;

  rv32i_core_assertions u_assertions (
    .clk         (clk),
    .rst_n       (rst_n),
    .state       (state),
    .pc          (pc),
    .instr       (instr),
    .pc_en       (pc_en),
    .branch      (branch),
    .jal         (jal),
    .jalr        (jalr),
    .rf_we       (rf_we),
    .alusrc_sel  (alusrc_sel),
    .alu_control (alu_control),
    .rf_srcsel   (rf_srcsel),
    .rf_rd1      (rf_rd1),
    .rf_rd2      (rf_rd2),
    .imm_ext     (imm_ext),
    .idex_rs1    (idex_rs1),
    .idex_rs2    (idex_rs2),
    .idex_imm    (idex_imm),
    .alu_src2    (alu_src2),
    .alu_result  (alu_result),
    .wb_data     (wb_data),
    .transfer    (transfer),
    .bus_we      (bus_we)
  );

endmodule
