// Connects the verification probe to one rv32i_cpu instance without RTL edits.
// Simulation-only binding. Keep this file out of synthesis file lists.
bind rv32i_cpu rv32i_core_probe u_rv32i_core_probe (
  .clk         (clk),
  .rst_n       (rst_n),
  .state       (u_control_unit.rState),
  .pc          (instr_addr),
  .instr       (instr_code),

  .pc_en       (wPcEn),
  .branch      (wBranch),
  .jal         (wJal),
  .jalr        (wJalr),
  .rf_we       (wRfWe),
  .alusrc_sel  (wAluSrcSel),
  .alu_control (wAluCtrl),
  .rf_srcsel   (wWbSel),

  .rf_rd1      (u_datapath.wRfRd1),
  .rf_rd2      (u_datapath.wRfRd2),
  .imm_ext     (u_datapath.wImmExt),
  .idex_rs1    (u_datapath.rIdExRs1),
  .idex_rs2    (u_datapath.rIdExRs2),
  .idex_imm    (u_datapath.rIdExImm),
  .alu_src2    (u_datapath.wAluSrc2),
  .alu_result  (u_datapath.wAluResult),
  .wb_data     (u_datapath.wWbData),

  .ready       (ready),
  .bus_rdata   (bus_rdata),
  .transfer    (transfer),
  .bus_we      (bus_we),
  .itype       (itype),
  .bus_addr    (bus_addr),
  .bus_wdata   (bus_wdata)
);
