// Passive observation interface used by the UVM monitor.
// It exposes bound core state without adding verification ports to the RTL.
interface rv32i_probe_if (
  input logic clk
);

  // Architectural observation points
  logic        rst_n;
  logic [2:0]  state;
  logic [31:0] pc;
  logic [31:0] instr;
  logic        commit_valid;
  logic        commit_rd_we;
  logic [4:0]  commit_rd;
  logic [31:0] commit_wdata;

  // Control-unit observation points
  logic        pc_en;
  logic        branch;
  logic        jal;
  logic        jalr;
  logic        rf_we;
  logic        alusrc_sel;
  logic [3:0]  alu_control;
  logic [2:0]  rf_srcsel;

  // Datapath observation points
  logic [31:0] rf_rd1;
  logic [31:0] rf_rd2;
  logic [31:0] imm_ext;
  logic [31:0] idex_rs1;
  logic [31:0] idex_rs2;
  logic [31:0] idex_imm;
  logic [31:0] alu_src2;
  logic [31:0] alu_result;
  logic [31:0] wb_data;

  // Core bus observation points
  logic        ready;
  logic [31:0] bus_rdata;
  logic        transfer;
  logic        bus_we;
  logic [2:0]  itype;
  logic [31:0] bus_addr;
  logic [31:0] bus_wdata;

  // The DUT commits R/I register writes on the edge that ends CPU_EXECUTE.
  // Sampling one simulator time-step before the edge observes the values that
  // are actually presented to the register file at that edge.
  clocking mon_cb @(posedge clk);
    default input #1step;

    input rst_n;
    input state;
    input pc;
    input instr;
    input commit_valid;
    input commit_rd_we;
    input commit_rd;
    input commit_wdata;

    input pc_en;
    input branch;
    input jal;
    input jalr;
    input rf_we;
    input alusrc_sel;
    input alu_control;
    input rf_srcsel;

    input rf_rd1;
    input rf_rd2;
    input imm_ext;
    input idex_rs1;
    input idex_rs2;
    input idex_imm;
    input alu_src2;
    input alu_result;
    input wb_data;

    input ready;
    input bus_rdata;
    input transfer;
    input bus_we;
    input itype;
    input bus_addr;
    input bus_wdata;
  endclocking

  modport monitor (clocking mon_cb);

endinterface
