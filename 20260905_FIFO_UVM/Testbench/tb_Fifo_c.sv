/*******************************************************************
 - Project          : 20260905_FIFO_UVM
 - File name        : tb_Fifo_c.sv // [NEW] DPI-C reference model variant copied from tb_Fifo_simple.sv
 - Description      : UVM Testbench for tb_Fifo
 - Owner            : Daegyu.Han
 - Revision history : 1) 2026.09.05 : Initial release
                      2) 2026.09.05 : Split push/pop agents, add modports,
                                      and report scoreboard counts by sequence
                      3) 2026.09.06 : Print monitor functional coverage summary
                      4) 2026.09.06 : Add data sweep coverage and refine crosses
*******************************************************************/
/**************************************************************
 [ Verification Strategy & Scenarios ]
 1. Architecture : Split active agents.
                   - Push agent drives reset, push, and write data.
                   - Pop agent drives pop.
                   - A shared bus monitor samples the complete FIFO interface.
 2. Scoreboard   : Uses a DPI-C FIFO reference model and reports pass/fail/total // [NEW]
                   counts per scenario sequence.
 3. Modports     : Interface modports constrain driver/monitor access by role,
                   so the push and pop agents cannot accidentally drive each
                   other's signals.
 4. SVA          : SystemVerilog Assertions are bound to the DUT.
 5. Coverage     : Monitor includes command/state/sequence coverage.
 6. Sequences    : Reset, Fill-to-Full, Drain-to-Empty, data sweep,
                   and concurrent stress.
**************************************************************/
`ifndef UVM_REPORT_DISABLE_FILE_LINE
`define UVM_REPORT_DISABLE_FILE_LINE
`endif
`include "uvm_macros.svh"
import uvm_pkg::*;

// [NEW] DPI-C declarations for the FIFO reference model implemented in fifo_c_ref_model.c.
import "DPI-C" function void fifo_c_ref_init(input int depth);
import "DPI-C" function int fifo_c_ref_step(
    input  int rst,
    input  int push,
    input  int pop,
    input  int wr_data,
    output int exp_pre_full,
    output int exp_pre_empty,
    output int exp_pop_valid,
    output int exp_rd_data,
    output int exp_post_full,
    output int exp_post_empty,
    output int exp_size
);

typedef enum int unsigned {
    FIFO_SEQ_IDLE   = 0,
    FIFO_SEQ_RESET  = 1,
    FIFO_SEQ_FILL   = 2,
    FIFO_SEQ_DRAIN  = 3,
    FIFO_SEQ_DATA   = 4,
    FIFO_SEQ_STRESS = 5,
    FIFO_SEQ_MIXED  = 6
} fifo_seq_id_e;

function string fifo_seq_id_name(fifo_seq_id_e seq_id);
    case (seq_id)
        FIFO_SEQ_IDLE   : return "IDLE";
        FIFO_SEQ_RESET  : return "RESET";
        FIFO_SEQ_FILL   : return "FILL_TO_FULL";
        FIFO_SEQ_DRAIN  : return "DRAIN_TO_EMPTY";
        FIFO_SEQ_DATA   : return "DATA_SWEEP";
        FIFO_SEQ_STRESS : return "CONCURRENT_STRESS";
        FIFO_SEQ_MIXED  : return "MIXED";
        default         : return "UNKNOWN";
    endcase
endfunction

function fifo_seq_id_e fifo_resolve_active_seq_id(
    bit           rst,
    bit           push,
    bit           pop,
    fifo_seq_id_e push_seq_id,
    fifo_seq_id_e pop_seq_id
);
    if (rst)
        return FIFO_SEQ_RESET;

    if (push && pop)
    begin
        if (push_seq_id == pop_seq_id)
            return push_seq_id;
        if (push_seq_id == FIFO_SEQ_IDLE)
            return pop_seq_id;
        if (pop_seq_id == FIFO_SEQ_IDLE)
            return push_seq_id;
        return FIFO_SEQ_MIXED;
    end

    if (push)
        return push_seq_id;
    if (pop)
        return pop_seq_id;
    if (push_seq_id != FIFO_SEQ_IDLE)
        return push_seq_id;
    if (pop_seq_id != FIFO_SEQ_IDLE)
        return pop_seq_id;

    return FIFO_SEQ_IDLE;
endfunction

class fifo_short_report_server extends uvm_default_report_server;
    function new(string name = "fifo_short_report_server");
        super.new(name);
    endfunction

    virtual function string compose_report_message(
        uvm_report_message report_message,
        string             report_object_name = ""
    );
        uvm_severity severity;

        severity = report_message.get_severity();
        return $sformatf("%s @ %0t [%s] %s",
                         severity.name(),
                         $time,
                         report_message.get_id(),
                         report_message.get_message());
    endfunction
endclass

// -------------------------------
// 1. Interface with Modports
// -------------------------------
interface fifo_if(input logic iClk);
    logic         iRst;
    logic         iPush;
    logic         iPop;
    logic [7:0]   iWrDt;
    logic [7:0]   oRdDt;
    logic         oFull;
    logic         oEmpty;

    fifo_seq_id_e push_seq_id;
    fifo_seq_id_e pop_seq_id;

    initial
    begin
        iRst        = 1'b1;
        iPush       = 1'b0;
        iPop        = 1'b0;
        iWrDt       = '0;
        push_seq_id = FIFO_SEQ_IDLE;
        pop_seq_id  = FIFO_SEQ_IDLE;
    end

    // Push driver owns reset, push, and write data.
    clocking push_drv_cb @(posedge iClk);
        default input #1step output #1;
        output iRst, iPush, iWrDt, push_seq_id;
        input  oFull, oEmpty;
    endclocking

    // Pop driver owns only the pop request side.
    clocking pop_drv_cb @(posedge iClk);
        default input #1step output #1;
        output iPop, pop_seq_id;
        input  oFull, oEmpty;
    endclocking

    modport push_drv_mp (clocking push_drv_cb);
    modport pop_drv_mp  (clocking pop_drv_cb);
    modport mon_mp      (
        input iClk,
        input iRst, iPush, iPop, iWrDt,
        input oRdDt, oFull, oEmpty,
        input push_seq_id, pop_seq_id
    );

    // --- SVA (SystemVerilog Assertions) ---
    // @/Src/Fifo_sva.sv

endinterface

// -------------------------------
// 2. Sequence Items
// -------------------------------
class fifo_push_item extends uvm_sequence_item;
    rand bit       iRst;
    rand bit       iPush;
    rand bit [7:0] iWrDt;
         fifo_seq_id_e seq_id;

    constraint c_rst  { iRst  dist {0 := 95, 1 := 5}; }
    constraint c_push { iPush dist {0 := 50, 1 := 50}; }

    `uvm_object_utils_begin(fifo_push_item)
        `uvm_field_int(iRst,  UVM_DEFAULT)
        `uvm_field_int(iPush, UVM_DEFAULT)
        `uvm_field_int(iWrDt, UVM_DEFAULT)
        `uvm_field_enum(fifo_seq_id_e, seq_id, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "fifo_push_item");
        super.new(name);
        seq_id = FIFO_SEQ_IDLE;
    endfunction

    virtual function string convert2string();
        return $sformatf("Seq:%s Rst:%b Push:%b WrDt:%h",
                         fifo_seq_id_name(seq_id), iRst, iPush, iWrDt);
    endfunction
endclass

class fifo_pop_item extends uvm_sequence_item;
    rand bit iPop;
         fifo_seq_id_e seq_id;

    constraint c_pop { iPop dist {0 := 50, 1 := 50}; }

    `uvm_object_utils_begin(fifo_pop_item)
        `uvm_field_int(iPop, UVM_DEFAULT)
        `uvm_field_enum(fifo_seq_id_e, seq_id, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "fifo_pop_item");
        super.new(name);
        seq_id = FIFO_SEQ_IDLE;
    endfunction

    virtual function string convert2string();
        return $sformatf("Seq:%s Pop:%b", fifo_seq_id_name(seq_id), iPop);
    endfunction
endclass

class fifo_bus_item extends uvm_sequence_item;
    bit       iRst;
    bit       iPush;
    bit       iPop;
    bit [7:0] iWrDt;

    logic [7:0] pre_oRdDt;
    logic       pre_oFull;
    logic       pre_oEmpty;

    logic [7:0] post_oRdDt;
    logic       post_oFull;
    logic       post_oEmpty;

    fifo_seq_id_e push_seq_id;
    fifo_seq_id_e pop_seq_id;
    fifo_seq_id_e active_seq_id;

    `uvm_object_utils_begin(fifo_bus_item)
        `uvm_field_int(iRst,        UVM_DEFAULT)
        `uvm_field_int(iPush,       UVM_DEFAULT)
        `uvm_field_int(iPop,        UVM_DEFAULT)
        `uvm_field_int(iWrDt,       UVM_DEFAULT)
        `uvm_field_int(pre_oRdDt,   UVM_DEFAULT)
        `uvm_field_int(pre_oFull,   UVM_DEFAULT)
        `uvm_field_int(pre_oEmpty,  UVM_DEFAULT)
        `uvm_field_int(post_oRdDt,  UVM_DEFAULT)
        `uvm_field_int(post_oFull,  UVM_DEFAULT)
        `uvm_field_int(post_oEmpty, UVM_DEFAULT)
        `uvm_field_enum(fifo_seq_id_e, push_seq_id,   UVM_DEFAULT)
        `uvm_field_enum(fifo_seq_id_e, pop_seq_id,    UVM_DEFAULT)
        `uvm_field_enum(fifo_seq_id_e, active_seq_id, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "fifo_bus_item");
        super.new(name);
        push_seq_id   = FIFO_SEQ_IDLE;
        pop_seq_id    = FIFO_SEQ_IDLE;
        active_seq_id = FIFO_SEQ_IDLE;
    endfunction

    virtual function string convert2string();
        return $sformatf(
            "Seq:%s Rst:%b Push:%b Pop:%b WrDt:%h | Pre Rd:%h F:%b E:%b | Post Rd:%h F:%b E:%b",
            fifo_seq_id_name(active_seq_id), iRst, iPush, iPop, iWrDt,
            pre_oRdDt, pre_oFull, pre_oEmpty,
            post_oRdDt, post_oFull, post_oEmpty
        );
    endfunction
endclass

// -------------------------------
// 3. Sequences
// -------------------------------
class fifo_push_reset_sequence extends uvm_sequence #(fifo_push_item);
    `uvm_object_utils(fifo_push_reset_sequence)

    function new(string name = "fifo_push_reset_sequence");
        super.new(name);
    endfunction

    virtual task body();
        fifo_push_item req;

        repeat (2)
        begin
            req = fifo_push_item::type_id::create("req");
            // Drive reset cycles with push and write data inactive.
            start_item(req);
            if (!req.randomize() with { iRst == 1; iPush == 0; iWrDt == 0; })
                `uvm_error("SEQ", "Failed to randomize push reset item")
            req.seq_id = FIFO_SEQ_RESET;
            finish_item(req);
        end
    endtask
endclass

class fifo_push_fill_sequence extends uvm_sequence #(fifo_push_item);
    `uvm_object_utils(fifo_push_fill_sequence)

    function new(string name = "fifo_push_fill_sequence");
        super.new(name);
    endfunction

    virtual task body();
        fifo_push_item req;

        repeat (5)
        begin
            req = fifo_push_item::type_id::create("req");
            // Drive push-only traffic to fill the FIFO.
            start_item(req);
            if (!req.randomize() with { iRst == 0; iPush == 1; })
                `uvm_error("SEQ", "Failed to randomize fill item")
            req.seq_id = FIFO_SEQ_FILL;
            finish_item(req);
        end
    endtask
endclass

class fifo_pop_drain_sequence extends uvm_sequence #(fifo_pop_item);
    `uvm_object_utils(fifo_pop_drain_sequence)

    function new(string name = "fifo_pop_drain_sequence");
        super.new(name);
    endfunction

    virtual task body();
        fifo_pop_item req;

        repeat (5)
        begin
            req = fifo_pop_item::type_id::create("req");
            // Drive pop-only traffic to drain the FIFO.
            start_item(req);
            if (!req.randomize() with { iPop == 1; })
                `uvm_error("SEQ", "Failed to randomize drain item")
            req.seq_id = FIFO_SEQ_DRAIN;
            finish_item(req);
        end
    endtask
endclass

class fifo_push_data_sweep_sequence extends uvm_sequence #(fifo_push_item);
    `uvm_object_utils(fifo_push_data_sweep_sequence)

    function new(string name = "fifo_push_data_sweep_sequence");
        super.new(name);
    endfunction

    virtual task body();
        fifo_push_item req;

        for (int data = 0; data < 256; data++)
        begin
            req = fifo_push_item::type_id::create("req");
            // Sweep accepted write data values from 0x00 through 0xFF.
            start_item(req);
            req.iRst  = 1'b0;
            req.iPush = 1'b1;
            req.iWrDt = data[7:0];
            req.seq_id = FIFO_SEQ_DATA;
            finish_item(req);
        end
    endtask
endclass

class fifo_pop_data_sweep_sequence extends uvm_sequence #(fifo_pop_item);
    `uvm_object_utils(fifo_pop_data_sweep_sequence)

    function new(string name = "fifo_pop_data_sweep_sequence");
        super.new(name);
    endfunction

    virtual task body();
        fifo_pop_item req;

        repeat (257)
        begin
            req = fifo_pop_item::type_id::create("req");
            // Keep pop asserted long enough to read all swept data.
            start_item(req);
            req.iPop = 1'b1;
            req.seq_id = FIFO_SEQ_DATA;
            finish_item(req);
        end
    endtask
endclass

class fifo_push_stress_sequence extends uvm_sequence #(fifo_push_item);
    `uvm_object_utils(fifo_push_stress_sequence)

    function new(string name = "fifo_push_stress_sequence");
        super.new(name);
    endfunction

    virtual task body();
        fifo_push_item req;

        repeat (50)
        begin
            req = fifo_push_item::type_id::create("req");
            // Randomize reset-free push/write stimulus before corner cases.
            start_item(req);
            if (!req.randomize() with { iRst == 0; })
                `uvm_error("SEQ", "Failed to randomize push stress item")
            req.seq_id = FIFO_SEQ_STRESS;
            finish_item(req);
        end

        req = fifo_push_item::type_id::create("req");
        // Reset from the current random FIFO state.
        start_item(req);
        req.iRst = 1'b1;
        req.iPush = 1'b0;
        req.iWrDt = '0;
        req.seq_id = FIFO_SEQ_STRESS;
        finish_item(req);

        for (int data = 0; data < 2; data++)
        begin
            req = fifo_push_item::type_id::create("req");
            // Push two items to create a non-empty reset state.
            start_item(req);
            req.iRst = 1'b0;
            req.iPush = 1'b1;
            req.iWrDt = 8'hA0 + data[7:0];
            req.seq_id = FIFO_SEQ_STRESS;
            finish_item(req);
        end

        req = fifo_push_item::type_id::create("req");
        // Assert reset while FIFO is non-empty.
        start_item(req);
        req.iRst = 1'b1;
        req.iPush = 1'b0;
        req.iWrDt = '0;
        req.seq_id = FIFO_SEQ_STRESS;
        finish_item(req);

        req = fifo_push_item::type_id::create("req");
        // Release reset and keep push idle for one cycle.
        start_item(req);
        req.iRst = 1'b0;
        req.iPush = 1'b0;
        req.iWrDt = '0;
        req.seq_id = FIFO_SEQ_STRESS;
        finish_item(req);

        for (int data = 0; data < 4; data++)
        begin
            req = fifo_push_item::type_id::create("req");
            // Fill FIFO completely before reset.
            start_item(req);
            req.iRst = 1'b0;
            req.iPush = 1'b1;
            req.iWrDt = 8'hB0 + data[7:0];
            req.seq_id = FIFO_SEQ_STRESS;
            finish_item(req);
        end

        req = fifo_push_item::type_id::create("req");
        // Assert reset while FIFO is full.
        start_item(req);
        req.iRst = 1'b1;
        req.iPush = 1'b0;
        req.iWrDt = '0;
        req.seq_id = FIFO_SEQ_STRESS;
        finish_item(req);

        req = fifo_push_item::type_id::create("req");
        // Release reset before the full push-pop corner.
        start_item(req);
        req.iRst = 1'b0;
        req.iPush = 1'b0;
        req.iWrDt = '0;
        req.seq_id = FIFO_SEQ_STRESS;
        finish_item(req);

        for (int data = 0; data < 4; data++)
        begin
            req = fifo_push_item::type_id::create("req");
            // Fill FIFO completely before simultaneous push-pop.
            start_item(req);
            req.iRst = 1'b0;
            req.iPush = 1'b1;
            req.iWrDt = 8'hC0 + data[7:0];
            req.seq_id = FIFO_SEQ_STRESS;
            finish_item(req);
        end

        req = fifo_push_item::type_id::create("req");
        // Push while the pop side also asserts pop at full.
        start_item(req);
        req.iRst = 1'b0;
        req.iPush = 1'b1;
        req.iWrDt = 8'hCF;
        req.seq_id = FIFO_SEQ_STRESS;
        finish_item(req);

        repeat (50)
        begin
            req = fifo_push_item::type_id::create("req");
            // Resume reset-free random push/write stimulus after corner cases.
            start_item(req);
            if (!req.randomize() with { iRst == 0; })
                `uvm_error("SEQ", "Failed to randomize push stress item")
            req.seq_id = FIFO_SEQ_STRESS;
            finish_item(req);
        end
    endtask
endclass

class fifo_pop_stress_sequence extends uvm_sequence #(fifo_pop_item);
    `uvm_object_utils(fifo_pop_stress_sequence)

    function new(string name = "fifo_pop_stress_sequence");
        super.new(name);
    endfunction

    virtual task body();
        fifo_pop_item req;

        repeat (50)
        begin
            req = fifo_pop_item::type_id::create("req");
            // Randomize pop stimulus before corner cases.
            start_item(req);
            if (!req.randomize())
                `uvm_error("SEQ", "Failed to randomize pop stress item")
            req.seq_id = FIFO_SEQ_STRESS;
            finish_item(req);
        end

        repeat (5)
        begin
            req = fifo_pop_item::type_id::create("req");
            // Hold pop low while push side creates the non-empty reset corner.
            start_item(req);
            req.iPop = 1'b0;
            req.seq_id = FIFO_SEQ_STRESS;
            finish_item(req);
        end

        repeat (6)
        begin
            req = fifo_pop_item::type_id::create("req");
            // Hold pop low while push side creates the full reset corner.
            start_item(req);
            req.iPop = 1'b0;
            req.seq_id = FIFO_SEQ_STRESS;
            finish_item(req);
        end

        repeat (4)
        begin
            req = fifo_pop_item::type_id::create("req");
            // Hold pop low while push side fills FIFO for full push-pop.
            start_item(req);
            req.iPop = 1'b0;
            req.seq_id = FIFO_SEQ_STRESS;
            finish_item(req);
        end

        req = fifo_pop_item::type_id::create("req");
        // Assert pop with push side to exercise push-pop at full.
        start_item(req);
        req.iPop = 1'b1;
        req.seq_id = FIFO_SEQ_STRESS;
        finish_item(req);

        repeat (50)
        begin
            req = fifo_pop_item::type_id::create("req");
            // Resume random pop stimulus after corner cases.
            start_item(req);
            if (!req.randomize())
                `uvm_error("SEQ", "Failed to randomize pop stress item")
            req.seq_id = FIFO_SEQ_STRESS;
            finish_item(req);
        end
    endtask
endclass

// -------------------------------
// 4. Drivers & Monitor
// -------------------------------
class fifo_push_driver extends uvm_driver #(fifo_push_item);
    `uvm_component_utils(fifo_push_driver)
    virtual fifo_if.push_drv_mp vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        virtual fifo_if raw_vif;

        if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", raw_vif))
            `uvm_fatal("PUSH_DRV", "Failed to get push driver VIF")

        vif = raw_vif;
    endfunction

    virtual task run_phase(uvm_phase phase);
        fifo_push_item req;

        vif.push_drv_cb.iRst        <= 1'b1;
        vif.push_drv_cb.iPush       <= 1'b0;
        vif.push_drv_cb.iWrDt       <= '0;
        vif.push_drv_cb.push_seq_id <= FIFO_SEQ_IDLE;

        forever
        begin
            @(vif.push_drv_cb);
            req = null;
            seq_item_port.try_next_item(req);

            if (req == null)
            begin
                vif.push_drv_cb.iRst        <= 1'b0;
                vif.push_drv_cb.iPush       <= 1'b0;
                vif.push_drv_cb.iWrDt       <= '0;
                vif.push_drv_cb.push_seq_id <= FIFO_SEQ_IDLE;
            end
            else
            begin
                vif.push_drv_cb.iRst        <= req.iRst;
                vif.push_drv_cb.iPush       <= req.iPush;
                vif.push_drv_cb.iWrDt       <= req.iWrDt;
                vif.push_drv_cb.push_seq_id <= req.seq_id;
                seq_item_port.item_done();
            end
        end
    endtask
endclass

class fifo_pop_driver extends uvm_driver #(fifo_pop_item);
    `uvm_component_utils(fifo_pop_driver)
    virtual fifo_if.pop_drv_mp vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        virtual fifo_if raw_vif;

        if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", raw_vif))
            `uvm_fatal("POP_DRV", "Failed to get pop driver VIF")

        vif = raw_vif;
    endfunction

    virtual task run_phase(uvm_phase phase);
        fifo_pop_item req;

        vif.pop_drv_cb.iPop       <= 1'b0;
        vif.pop_drv_cb.pop_seq_id <= FIFO_SEQ_IDLE;

        forever
        begin
            @(vif.pop_drv_cb);
            req = null;
            seq_item_port.try_next_item(req);

            if (req == null)
            begin
                vif.pop_drv_cb.iPop       <= 1'b0;
                vif.pop_drv_cb.pop_seq_id <= FIFO_SEQ_IDLE;
            end
            else
            begin
                vif.pop_drv_cb.iPop       <= req.iPop;
                vif.pop_drv_cb.pop_seq_id <= req.seq_id;
                seq_item_port.item_done();
            end
        end
    endtask
endclass

class fifo_monitor extends uvm_monitor;
    `uvm_component_utils(fifo_monitor)
    virtual fifo_if.mon_mp vif;
    uvm_analysis_port #(fifo_bus_item) ap;
    fifo_bus_item sampled_req;
    int unsigned cov_sample_cnt;

    // --- Functional Coverage ---
    covergroup fifo_cg;
        option.per_instance = 1;
        // Track which scenario owns each sampled cycle.
        cp_seq   : coverpoint sampled_req.active_seq_id {
            ignore_bins mixed_seq = {FIFO_SEQ_MIXED};
        }
        // Track command and boundary flag values seen by the monitor.
        cp_push  : coverpoint sampled_req.iPush;
        cp_pop   : coverpoint sampled_req.iPop;
        cp_full  : coverpoint sampled_req.pre_oFull;
        cp_empty : coverpoint sampled_req.pre_oEmpty;
        // Track every accepted 8-bit write data value.
        cp_wr_data : coverpoint sampled_req.iWrDt iff (
            sampled_req.iPush && !sampled_req.iRst && !sampled_req.pre_oFull
        ) {
            bins all_values[] = {[8'h00:8'hFF]};
        }

        // Cross command activity with FIFO boundary states.
        cx_cmd_state : cross cp_push, cp_pop, cp_full, cp_empty {
            // binsof selects bins from a coverpoint; intersect keeps only listed values.
            ignore_bins illegal_state =
                binsof(cp_full) intersect {1} && binsof(cp_empty) intersect {1};
        }

        // Cross scenario ownership with command activity.
        cx_seq_cmd : cross cp_seq, cp_push, cp_pop {
            // Ignore combinations that are reserved or cannot be generated by directed scenarios.
            ignore_bins mixed_seq = binsof(cp_seq) intersect {FIFO_SEQ_MIXED};
            ignore_bins idle_push =
                binsof(cp_seq) intersect {FIFO_SEQ_IDLE} &&
                binsof(cp_push) intersect {1};
            ignore_bins idle_pop =
                binsof(cp_seq) intersect {FIFO_SEQ_IDLE} &&
                binsof(cp_pop) intersect {1};
            ignore_bins reset_push =
                binsof(cp_seq) intersect {FIFO_SEQ_RESET} &&
                binsof(cp_push) intersect {1};
            ignore_bins reset_pop =
                binsof(cp_seq) intersect {FIFO_SEQ_RESET} &&
                binsof(cp_pop) intersect {1};
            ignore_bins fill_no_push =
                binsof(cp_seq) intersect {FIFO_SEQ_FILL} &&
                binsof(cp_push) intersect {0};
            ignore_bins fill_pop =
                binsof(cp_seq) intersect {FIFO_SEQ_FILL} &&
                binsof(cp_pop) intersect {1};
            ignore_bins drain_push =
                binsof(cp_seq) intersect {FIFO_SEQ_DRAIN} &&
                binsof(cp_push) intersect {1};
            ignore_bins drain_no_pop =
                binsof(cp_seq) intersect {FIFO_SEQ_DRAIN} &&
                binsof(cp_pop) intersect {0};
            ignore_bins data_no_pop =
                binsof(cp_seq) intersect {FIFO_SEQ_DATA} &&
                binsof(cp_pop) intersect {0};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
        fifo_cg = new();
    endfunction

    virtual function void build_phase(uvm_phase phase);
        virtual fifo_if raw_vif;

        if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", raw_vif))
            `uvm_fatal("MON", "Failed to get monitor VIF")

        vif = raw_vif;
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever
        begin
            @(posedge vif.iClk);

            sampled_req = fifo_bus_item::type_id::create("sampled_req");
            sampled_req.iRst        = vif.iRst;
            sampled_req.iPush       = vif.iPush;
            sampled_req.iPop        = vif.iPop;
            sampled_req.iWrDt       = vif.iWrDt;
            sampled_req.pre_oRdDt   = vif.oRdDt;
            sampled_req.pre_oFull   = vif.oFull;
            sampled_req.pre_oEmpty  = vif.oEmpty;
            sampled_req.push_seq_id = vif.push_seq_id;
            sampled_req.pop_seq_id  = vif.pop_seq_id;
            sampled_req.active_seq_id = fifo_resolve_active_seq_id(
                vif.iRst, vif.iPush, vif.iPop, vif.push_seq_id, vif.pop_seq_id
            );

            #1step;

            sampled_req.post_oRdDt  = vif.oRdDt;
            sampled_req.post_oFull  = vif.oFull;
            sampled_req.post_oEmpty = vif.oEmpty;

            fifo_cg.sample();
            cov_sample_cnt++;
            ap.write(sampled_req);
        end
    endtask

    virtual function void report_phase(uvm_phase phase);
        real cov_pct;

        super.report_phase(phase);

        cov_pct = fifo_cg.get_inst_coverage();
        `uvm_info("COV_SUMMARY", "================ FIFO FUNCTIONAL COVERAGE SUMMARY ================", UVM_LOW)
        `uvm_info("COV_SUMMARY",
                  $sformatf("fifo_monitor.fifo_cg SAMPLE:%0d TOTAL:%0.2f%%",
                            cov_sample_cnt, cov_pct),
                  UVM_LOW)
        `uvm_info("COV_DETAIL",
                  $sformatf("cp_seq       : %0.2f%%", fifo_cg.cp_seq.get_inst_coverage()),
                  UVM_LOW)
        `uvm_info("COV_DETAIL",
                  $sformatf("cp_push      : %0.2f%%", fifo_cg.cp_push.get_inst_coverage()),
                  UVM_LOW)
        `uvm_info("COV_DETAIL",
                  $sformatf("cp_pop       : %0.2f%%", fifo_cg.cp_pop.get_inst_coverage()),
                  UVM_LOW)
        `uvm_info("COV_DETAIL",
                  $sformatf("cp_full      : %0.2f%%", fifo_cg.cp_full.get_inst_coverage()),
                  UVM_LOW)
        `uvm_info("COV_DETAIL",
                  $sformatf("cp_empty     : %0.2f%%", fifo_cg.cp_empty.get_inst_coverage()),
                  UVM_LOW)
        `uvm_info("COV_DETAIL",
                  $sformatf("cp_wr_data   : %0.2f%%", fifo_cg.cp_wr_data.get_inst_coverage()),
                  UVM_LOW)
        `uvm_info("COV_DETAIL",
                  $sformatf("cx_cmd_state : %0.2f%%", fifo_cg.cx_cmd_state.get_inst_coverage()),
                  UVM_LOW)
        `uvm_info("COV_DETAIL",
                  $sformatf("cx_seq_cmd   : %0.2f%%", fifo_cg.cx_seq_cmd.get_inst_coverage()),
                  UVM_LOW)
        `uvm_info("COV_SUMMARY", "==================================================================", UVM_LOW)
    endfunction
endclass

// -------------------------------
// 5. Agents
// -------------------------------
class fifo_push_agent extends uvm_agent;
    `uvm_component_utils(fifo_push_agent)
    fifo_push_driver drv;
    uvm_sequencer #(fifo_push_item) sqr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        drv = fifo_push_driver::type_id::create("drv", this);
        sqr = uvm_sequencer #(fifo_push_item)::type_id::create("sqr", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass

class fifo_pop_agent extends uvm_agent;
    `uvm_component_utils(fifo_pop_agent)
    fifo_pop_driver drv;
    uvm_sequencer #(fifo_pop_item) sqr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        drv = fifo_pop_driver::type_id::create("drv", this);
        sqr = uvm_sequencer #(fifo_pop_item)::type_id::create("sqr", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass

// -------------------------------
// 6. Scoreboard
// -------------------------------
class fifo_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(fifo_scoreboard)
    uvm_analysis_imp #(fifo_bus_item, fifo_scoreboard) ap_imp;

    // [NEW] The SV ref_q queue was removed; the C model owns the reference FIFO state.
    localparam int MAX_DEPTH = 4; // ADDR_WIDTH = 2 -> Depth 4

    int unsigned pass_cnt  [int unsigned];
    int unsigned fail_cnt  [int unsigned];
    int unsigned total_cnt [int unsigned];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        ap_imp = new("ap_imp", this);
        // [NEW] Initialize the DPI-C reference model with the DUT FIFO depth.
        fifo_c_ref_init(MAX_DEPTH);
        `uvm_info("SCB", $sformatf("Using DPI-C FIFO reference model. DEPTH:%0d", MAX_DEPTH), UVM_LOW)
    endfunction

    function void record_result(fifo_seq_id_e seq_id, bit passed);
        int unsigned id;

        if ((seq_id == FIFO_SEQ_IDLE) && passed)
            return;

        id = int'(seq_id);
        total_cnt[id]++;
        if (passed)
            pass_cnt[id]++;
        else
            fail_cnt[id]++;
    endfunction

    virtual function void write(fifo_bus_item req);
        // [NEW] These fields receive expected pre/post state from fifo_c_ref_step().
        int c_status;
        int exp_pre_full;
        int exp_pre_empty;
        int exp_pop_valid;
        int exp_rd_data;
        int exp_post_full;
        int exp_post_empty;
        int exp_size;
        bit exp_pre_full_b;
        bit exp_pre_empty_b;
        bit exp_post_full_b;
        bit exp_post_empty_b;
        bit [7:0] expected_rd_data;
        bit txn_pass;

        txn_pass = 1'b1;

        // [NEW] Advance the C reference model by one monitored FIFO cycle.
        c_status = fifo_c_ref_step(
            int'(req.iRst),
            int'(req.iPush),
            int'(req.iPop),
            int'(req.iWrDt),
            exp_pre_full,
            exp_pre_empty,
            exp_pop_valid,
            exp_rd_data,
            exp_post_full,
            exp_post_empty,
            exp_size
        );

        // [NEW] Catch unexpected DPI-side failures before comparing DUT outputs.
        if (c_status == 0)
        begin
            txn_pass = 1'b0;
            `uvm_error("SCB", "DPI-C reference model returned an error")
            record_result(req.active_seq_id, txn_pass);
            return;
        end

        // [NEW] Convert C int outputs into SV values used by the existing checks.
        exp_pre_full_b    = (exp_pre_full != 0);
        exp_pre_empty_b   = (exp_pre_empty != 0);
        exp_post_full_b   = (exp_post_full != 0);
        exp_post_empty_b  = (exp_post_empty != 0);
        expected_rd_data  = exp_rd_data[7:0];

        if (req.iRst)
        begin
            // [NEW] Reset expected flags now come from the C model.
            if (req.post_oFull !== exp_post_full_b)
            begin
                txn_pass = 1'b0;
                `uvm_error("SCB", $sformatf("[%s] Full flag mismatch during reset. Act:%b Exp:%b",
                                            fifo_seq_id_name(req.active_seq_id),
                                            req.post_oFull, exp_post_full_b))
            end

            if (req.post_oEmpty !== exp_post_empty_b)
            begin
                txn_pass = 1'b0;
                `uvm_error("SCB", $sformatf("[%s] Empty flag mismatch during reset. Act:%b Exp:%b",
                                            fifo_seq_id_name(req.active_seq_id),
                                            req.post_oEmpty, exp_post_empty_b))
            end

            record_result(req.active_seq_id, txn_pass);
            return;
        end

        // [NEW] Pre-state flag expectations now come from the C model.
        if (req.pre_oFull !== exp_pre_full_b)
        begin
            txn_pass = 1'b0;
            `uvm_error("SCB", $sformatf("[%s] Pre Full mismatch. Act:%b Exp:%b Q:%0d",
                                        fifo_seq_id_name(req.active_seq_id),
                                        req.pre_oFull, exp_pre_full_b, exp_size))
        end

        if (req.pre_oEmpty !== exp_pre_empty_b)
        begin
            txn_pass = 1'b0;
            `uvm_error("SCB", $sformatf("[%s] Pre Empty mismatch. Act:%b Exp:%b Q:%0d",
                                        fifo_seq_id_name(req.active_seq_id),
                                        req.pre_oEmpty, exp_pre_empty_b, exp_size))
        end

        // [NEW] The C model tells the scoreboard when read data should be compared.
        if (exp_pop_valid != 0)
        begin
            if (expected_rd_data !== req.pre_oRdDt)
            begin
                txn_pass = 1'b0;
                `uvm_error("SCB", $sformatf("[%s] Read data mismatch. Exp:%h Act:%h",
                                            fifo_seq_id_name(req.active_seq_id),
                                            expected_rd_data, req.pre_oRdDt))
            end
        end

        // [NEW] Post-state flag expectations now come from the C model.
        if (req.post_oFull !== exp_post_full_b)
        begin
            txn_pass = 1'b0;
            `uvm_error("SCB", $sformatf("[%s] Post Full mismatch. Act:%b Exp:%b Q:%0d",
                                        fifo_seq_id_name(req.active_seq_id),
                                        req.post_oFull, exp_post_full_b, exp_size))
        end

        if (req.post_oEmpty !== exp_post_empty_b)
        begin
            txn_pass = 1'b0;
            `uvm_error("SCB", $sformatf("[%s] Post Empty mismatch. Act:%b Exp:%b Q:%0d",
                                        fifo_seq_id_name(req.active_seq_id),
                                        req.post_oEmpty, exp_post_empty_b, exp_size))
        end

        record_result(req.active_seq_id, txn_pass);

        if (txn_pass && (req.active_seq_id != FIFO_SEQ_IDLE))
            `uvm_info("SCB", $sformatf("[%s] PASS %s",
                                       fifo_seq_id_name(req.active_seq_id),
                                       req.convert2string()), UVM_HIGH)
    endfunction

    virtual function void report_phase(uvm_phase phase);
        int unsigned id;
        int unsigned grand_pass;
        int unsigned grand_fail;
        int unsigned grand_total;
        fifo_seq_id_e sid;

        grand_pass  = 0;
        grand_fail  = 0;
        grand_total = 0;

        `uvm_info("SCB_SUMMARY", "================ FIFO SCOREBOARD SUMMARY BY SEQUENCE ================", UVM_LOW)

        for (id = int'(FIFO_SEQ_IDLE); id <= int'(FIFO_SEQ_MIXED); id++)
        begin
            sid = fifo_seq_id_e'(id);
            if (total_cnt.exists(id))
            begin
                grand_pass  += pass_cnt[id];
                grand_fail  += fail_cnt[id];
                grand_total += total_cnt[id];
                `uvm_info("SCB_SUMMARY",
                          $sformatf("%-18s PASS:%0d FAIL:%0d TOTAL:%0d",
                                    fifo_seq_id_name(sid), pass_cnt[id], fail_cnt[id], total_cnt[id]),
                          UVM_LOW)
            end
        end

        `uvm_info("SCB_SUMMARY",
                  $sformatf("%-18s PASS:%0d FAIL:%0d TOTAL:%0d",
                            "ALL", grand_pass, grand_fail, grand_total),
                  UVM_LOW)
        `uvm_info("SCB_SUMMARY", "=====================================================================", UVM_LOW)
    endfunction
endclass

// -------------------------------
// 7. Env, Test, and Top Module
// -------------------------------
class fifo_env extends uvm_env;
    `uvm_component_utils(fifo_env)
    fifo_push_agent push_agt;
    fifo_pop_agent  pop_agt;
    fifo_monitor    mon;
    fifo_scoreboard scb;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        push_agt = fifo_push_agent::type_id::create("push_agt", this);
        pop_agt  = fifo_pop_agent::type_id::create("pop_agt", this);
        mon      = fifo_monitor::type_id::create("mon", this);
        scb      = fifo_scoreboard::type_id::create("scb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        mon.ap.connect(scb.ap_imp);
    endfunction
endclass

class fifo_test extends uvm_test;
    `uvm_component_utils(fifo_test)
    fifo_env env;

    fifo_push_reset_sequence  reset_seq;
    fifo_push_fill_sequence   fill_seq;
    fifo_pop_drain_sequence   drain_seq;
    fifo_push_data_sweep_sequence push_data_seq;
    fifo_pop_data_sweep_sequence  pop_data_seq;
    fifo_push_stress_sequence push_stress_seq;
    fifo_pop_stress_sequence  pop_stress_seq;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        env = fifo_env::type_id::create("env", this);

        reset_seq       = fifo_push_reset_sequence::type_id::create("reset_seq");
        fill_seq        = fifo_push_fill_sequence::type_id::create("fill_seq");
        drain_seq       = fifo_pop_drain_sequence::type_id::create("drain_seq");
        push_data_seq   = fifo_push_data_sweep_sequence::type_id::create("push_data_seq");
        pop_data_seq    = fifo_pop_data_sweep_sequence::type_id::create("pop_data_seq");
        push_stress_seq = fifo_push_stress_sequence::type_id::create("push_stress_seq");
        pop_stress_seq  = fifo_pop_stress_sequence::type_id::create("pop_stress_seq");
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        reset_seq.start(env.push_agt.sqr);
        fill_seq.start(env.push_agt.sqr);
        drain_seq.start(env.pop_agt.sqr);

        fork
            push_data_seq.start(env.push_agt.sqr);
            pop_data_seq.start(env.pop_agt.sqr);
        join

        fork
            push_stress_seq.start(env.push_agt.sqr);
            pop_stress_seq.start(env.pop_agt.sqr);
        join

        phase.phase_done.set_drain_time(this, 30);
        phase.drop_objection(this);
    endtask
endclass

module tb_Fifo_c; // [NEW] Separate top module for the DPI-C reference model run.
    logic iClk = 0;
    fifo_short_report_server short_report_server;

    always #5
    begin
        iClk = ~iClk;
    end

    fifo_if vif(iClk);

    Fifo #(
        .ADDR_WIDTH(2),
        .DATA_WIDTH(8)
    ) DUT (
        .iClk   (iClk),
        .iRst   (vif.iRst),
        .iPush  (vif.iPush),
        .iPop   (vif.iPop),
        .iWrDt  (vif.iWrDt),
        .oRdDt  (vif.oRdDt),
        .oFull  (vif.oFull),
        .oEmpty (vif.oEmpty)
    );

    // --- Bind SVA Module to DUT ---
    bind Fifo fifo_sva u_fifo_sva (
        .iClk   (iClk),
        .iRst   (iRst),
        .iPush  (iPush),
        .iPop   (iPop),
        .oRdDt  (oRdDt),
        .oFull  (oFull),
        .oEmpty (oEmpty)
    );

    initial
    begin
        short_report_server = new();
        uvm_report_server::set_server(short_report_server);

        // $dumpfile("wave_fifo.vcd");
        // $dumpvars(0, tb_Fifo_c); // [NEW]

        // Also support FSDB for conventional EDA tools
        // $fsdbDumpfile("wave.fsdb");
        // $fsdbDumpvars(0);

        uvm_config_db#(virtual fifo_if)::set(null, "uvm_test_top.env.*", "vif", vif);

        run_test("fifo_test");
    end
endmodule
