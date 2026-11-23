/*******************************************************************
 - Project          : 20260905_FIFO_UVM
 - File name        : tb_Fifo.sv
 - Description      : UVM Testbench for tb_Fifo
 - Owner            : Daegyu.Han
 - Revision history : 1) 2026.09.05 : Initial release
                      2) 2026.09.05 : Split push/pop agents, add modports,
                                      and report scoreboard counts by sequence
                      3) 2026.09.05 : Add UVM report verbosity and file logging
                      4) 2026.09.06 : Use numbered UVM log files and reduce
                                      UVM internal phase log noise
                      5) 2026.09.06 : Print monitor functional coverage summary
*******************************************************************/
/**************************************************************
 [ Verification Strategy & Scenarios ]
 1. Architecture : Split active agents.
                   - Push agent drives reset, push, and write data.
                   - Pop agent drives pop.
                   - A shared bus monitor samples the complete FIFO interface.
 2. Scoreboard   : Uses an SV queue ([$]) as a reference model and reports
                   pass/fail/total counts per scenario sequence.
 3. Modports     : Interface modports constrain driver/monitor access by role,
                   so the push and pop agents cannot accidentally drive each
                   other's signals.
 4. SVA          : SystemVerilog Assertions are bound to the DUT.
 5. Coverage     : Monitor includes command/state/sequence coverage.
 6. Sequences    : Reset, Fill-to-Full, Drain-to-Empty, and concurrent stress.
**************************************************************/
`include "uvm_macros.svh"
import uvm_pkg::*;

// what?
// 각 transaction이 어느 시나리오(sequence)에서 나온 것인지 표시하기 위한 ID이다.
// scoreboard는 이 값을 기준으로 RESET/FILL/DRAIN/STRESS별 pass/fail/total을 따로 누적한다.
// push와 pop agent가 분리되어 있기 때문에, 한 cycle 안에 push sequence와 pop sequence가
// 동시에 존재할 수 있다. 그래서 단순한 string 대신 enum으로 고정된 분류값을 둔다.
typedef enum int unsigned {
    FIFO_SEQ_IDLE   = 0,
    FIFO_SEQ_RESET  = 1,
    FIFO_SEQ_FILL   = 2,
    FIFO_SEQ_DRAIN  = 3,
    FIFO_SEQ_STRESS = 4,
    FIFO_SEQ_MIXED  = 5
} fifo_seq_id_e;

// what?
// enum 값은 로그나 scoreboard summary에 그대로 찍으면 숫자로 보인다.
// 이 함수는 enum을 사람이 읽기 좋은 문자열로 바꿔서 UVM log에 출력하기 위한 변환 함수이다.
// 예를 들어 FIFO_SEQ_FILL은 "FILL_TO_FULL"로 출력된다.
function string fifo_seq_id_name(fifo_seq_id_e seq_id);
    case (seq_id)
        FIFO_SEQ_IDLE   : return "IDLE";
        FIFO_SEQ_RESET  : return "RESET";
        FIFO_SEQ_FILL   : return "FILL_TO_FULL";
        FIFO_SEQ_DRAIN  : return "DRAIN_TO_EMPTY";
        FIFO_SEQ_STRESS : return "CONCURRENT_STRESS";
        FIFO_SEQ_MIXED  : return "MIXED";
        default         : return "UNKNOWN";
    endcase
endfunction

function fifo_seq_id_e fifo_resolve_active_seq_id(
    bit           rst,
    bit           push,
    bit           pop,
    // what?
    // push_seq_id는 push agent가 현재 drive 중인 sequence ID이고,
    // pop_seq_id는 pop agent가 현재 drive 중인 sequence ID이다.
    // 두 agent가 독립적으로 움직이기 때문에 scoreboard가 한 cycle을 어느 sequence로
    // 집계할지 결정하려면 두 ID를 함께 봐야 한다.
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

// what?
// run_test() 전에 uvm_top 자체에 report 정책을 먼저 걸어두는 함수이다.
// UVM component가 전부 만들어지기 전에도 일부 report가 발생할 수 있으므로,
// root report 설정을 먼저 적용해서 INFO/WARNING/ERROR/FATAL이 같은 log file로 가게 한다.
// UVM_HIGH까지 열어 scoreboard의 PASS 로그는 보이게 하고, UVM_FULL/UVM_DEBUG 수준의
// UVM 내부 phase trace는 숨겨서 로그가 지나치게 시끄러워지지 않게 한다.
function void fifo_configure_root_report(int log_fd);
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

// what?
// build/elaboration이 끝난 뒤 생성된 모든 UVM component 계층에 report 정책을 다시 적용한다.
// root에만 설정하면 이미 만들어진 component나 component별 reporter 설정이 다르게 남을 수 있다.
// 그래서 end_of_elaboration_phase에서 hier 함수를 호출해 test/env/agent/driver/monitor/scoreboard
// 전체가 동일한 verbosity, action, file handle을 쓰도록 맞춘다.
function void fifo_configure_hier_report(int log_fd);
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

// what?
// simulation을 여러 번 실행할 때 이전 log를 덮어쓰지 않도록 numbered log file을 여는 함수이다.
// log_prefix가 "../../fifo_uvm_report"이면 아래 순서로 비어 있는 파일명을 찾는다.
//   ../../fifo_uvm_report_001.log
//   ../../fifo_uvm_report_002.log
//   ../../fifo_uvm_report_003.log
// 이미 존재하는 파일은 read mode로 열어 존재 여부만 확인하고 바로 닫는다.
// 처음으로 없는 번호를 찾으면 write mode로 열고, 열린 file descriptor와 실제 경로를 반환한다.
function int fifo_open_numbered_report_log(input string log_prefix, output string log_path);
    int idx;
    int probe_fd;
    int log_fd;
    string candidate;

    for (idx = 1; idx <= 999; idx++)
    begin
        candidate = $sformatf("%s_%03d.log", log_prefix, idx);
        probe_fd = $fopen(candidate, "r");

        if (probe_fd != 0)
        begin
            $fclose(probe_fd);
        end
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

// what?
// 사용자가 plusarg로 "+FIFO_UVM_LOG=my.log"처럼 확장자까지 넣었을 때를 위한 보정 함수이다.
// numbered log 정책은 prefix 뒤에 "_001.log"를 붙이는 방식이라서,
// "my.log_001.log"가 아니라 "my_001.log"가 되도록 끝의 ".log"를 제거한다.
// "+FIFO_UVM_LOG_PREFIX=my"를 쓰는 경우에는 이 함수가 필요 없지만, 기존 plusarg 이름도
// 어느 정도 호환되도록 남겨둔 작은 helper이다.
function string fifo_strip_log_extension(input string log_path);
    int path_len;

    path_len = log_path.len();
    if ((path_len > 4) && (log_path.substr(path_len - 4, path_len - 1) == ".log"))
        return log_path.substr(0, path_len - 5);

    return log_path;
endfunction

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
        // what?
        // seq_id도 UVM field automation에 등록한다.
        // 이렇게 해두면 print/copy/compare/record 같은 UVM 기본 기능에서 pop item의
        // sequence 출처까지 함께 다룰 수 있다. 특히 convert2string 외의 UVM printer를 쓸 때
        // 단순히 iPop만 보이는 것이 아니라 어떤 sequence가 만든 pop인지 추적하기 쉽다.
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

// what?
// driver가 만든 "의도한 transaction"이 아니라 monitor가 실제 bus에서 관찰한 transaction이다.
// push agent와 pop agent는 서로 독립적으로 움직이지만 FIFO 동작은 한 clock cycle 안에서
// push/pop/reset/write-data/full/empty/read-data가 함께 해석되어야 한다.
// 그래서 monitor는 한 cycle의 전체 관찰값을 fifo_bus_item 하나로 묶어 scoreboard에 보낸다.
// pre_* 값은 clock edge 직후 DUT 상태 변화가 반영되기 전의 관찰값이고,
// post_* 값은 #1step 뒤 DUT의 NBA update가 반영된 후의 관찰값이다.
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
            start_item(req);
            // what?
            // drain sequence는 FIFO를 비우는 directed scenario이다.
            // 그래서 randomize를 쓰더라도 iPop은 반드시 1로 고정한다.
            // FIFO depth가 4인데 5번 pop을 보내므로, 앞의 4번은 정상 pop이고 마지막 1번은
            // empty 상태에서 pop을 넣는 underflow 방어 동작 확인용이다.
            if (!req.randomize() with { iPop == 1; })
                `uvm_error("SEQ", "Failed to randomize drain item")
            req.seq_id = FIFO_SEQ_DRAIN;
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

            // what?
            // try_next_item()은 blocking이 아니라 "지금 받을 item이 있으면 받고, 없으면 null"을 반환한다.
            // push sequence가 실행 중이 아닐 때 driver가 멈춰 있으면 이전 push 값이 bus에 남을 수 있다.
            // 그래서 req가 null이면 reset/push/write-data/seq_id를 idle 값으로 계속 drive한다.
            // 이렇게 해야 pop-only scenario에서 push 쪽 신호가 깨끗하게 0으로 유지된다.
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
        cp_seq   : coverpoint sampled_req.active_seq_id;
        cp_push  : coverpoint sampled_req.iPush;
        cp_pop   : coverpoint sampled_req.iPop;
        cp_full  : coverpoint sampled_req.pre_oFull;
        cp_empty : coverpoint sampled_req.pre_oEmpty;

        cx_cmd_state : cross cp_push, cp_pop, cp_full, cp_empty {
            ignore_bins illegal_state =
                binsof(cp_full) intersect {1} && binsof(cp_empty) intersect {1};
        }

        cx_seq_cmd : cross cp_seq, cp_push, cp_pop;
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
                  $sformatf("fifo_monitor.fifo_cg SAMPLE:%0d COVERAGE:%0.2f%%",
                            cov_sample_cnt, cov_pct),
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

    bit [7:0] ref_q [$];
    localparam int MAX_DEPTH = 4; // ADDR_WIDTH = 2 -> Depth 4

    // what?
    // sequence ID별 pass/fail/total 카운터이다.
    // associative array를 쓰기 때문에 모든 sequence ID에 대해 미리 배열 크기를 잡을 필요가 없다.
    // key는 fifo_seq_id_e를 int로 변환한 값이고, 값은 해당 sequence에서 누적된 개수이다.
    // scoreboard는 transaction 하나를 검사한 뒤 record_result()를 호출해서 이 배열들을 갱신한다.
    int unsigned pass_cnt  [int unsigned];
    int unsigned fail_cnt  [int unsigned];
    int unsigned total_cnt [int unsigned];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        ap_imp = new("ap_imp", this);
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
        bit is_full;
        bit is_empty;
        bit eff_push;
        bit eff_pop;
        bit [7:0] expected_rd_data;
        bit txn_pass;

        txn_pass = 1'b1;

        if (req.iRst)
        begin
            ref_q.delete();

            if (req.post_oFull !== 1'b0)
            begin
                txn_pass = 1'b0;
                `uvm_error("SCB", $sformatf("[%s] Full flag mismatch during reset. Act:%b Exp:0",
                                            fifo_seq_id_name(req.active_seq_id), req.post_oFull))
            end

            if (req.post_oEmpty !== 1'b1)
            begin
                txn_pass = 1'b0;
                `uvm_error("SCB", $sformatf("[%s] Empty flag mismatch during reset. Act:%b Exp:1",
                                            fifo_seq_id_name(req.active_seq_id), req.post_oEmpty))
            end

            record_result(req.active_seq_id, txn_pass);
            return;
        end

        is_full  = (ref_q.size() == MAX_DEPTH);
        is_empty = (ref_q.size() == 0);

        if (req.pre_oFull !== is_full)
        begin
            txn_pass = 1'b0;
            `uvm_error("SCB", $sformatf("[%s] Pre Full mismatch. Act:%b Exp:%b Q:%0d",
                                        fifo_seq_id_name(req.active_seq_id), req.pre_oFull, is_full, ref_q.size()))
        end

        if (req.pre_oEmpty !== is_empty)
        begin
            txn_pass = 1'b0;
            `uvm_error("SCB", $sformatf("[%s] Pre Empty mismatch. Act:%b Exp:%b Q:%0d",
                                        fifo_seq_id_name(req.active_seq_id), req.pre_oEmpty, is_empty, ref_q.size()))
        end

        eff_push = 1'b0;
        eff_pop  = 1'b0;

        if (req.iPush && !req.iPop && !is_full)
            eff_push = 1'b1;
        else if (!req.iPush && req.iPop && !is_empty)
            eff_pop = 1'b1;
        else if (req.iPush && req.iPop)
        begin
            if (is_empty)
                eff_push = 1'b1;
            else if (is_full)
                eff_pop = 1'b1;
            else
            begin
                eff_push = 1'b1;
                eff_pop  = 1'b1;
            end
        end

        if (eff_pop)
        begin
            expected_rd_data = ref_q[0];
            if (expected_rd_data !== req.pre_oRdDt)
            begin
                txn_pass = 1'b0;
                `uvm_error("SCB", $sformatf("[%s] Read data mismatch. Exp:%h Act:%h",
                                            fifo_seq_id_name(req.active_seq_id),
                                            expected_rd_data, req.pre_oRdDt))
            end
            ref_q.pop_front();
        end

        if (eff_push)
            ref_q.push_back(req.iWrDt);

        if (req.post_oFull !== (ref_q.size() == MAX_DEPTH))
        begin
            txn_pass = 1'b0;
            `uvm_error("SCB", $sformatf("[%s] Post Full mismatch. Act:%b Exp:%b Q:%0d",
                                        fifo_seq_id_name(req.active_seq_id),
                                        req.post_oFull, (ref_q.size() == MAX_DEPTH), ref_q.size()))
        end

        if (req.post_oEmpty !== (ref_q.size() == 0))
        begin
            txn_pass = 1'b0;
            `uvm_error("SCB", $sformatf("[%s] Post Empty mismatch. Act:%b Exp:%b Q:%0d",
                                        fifo_seq_id_name(req.active_seq_id),
                                        req.post_oEmpty, (ref_q.size() == 0), ref_q.size()))
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
        push_stress_seq = fifo_push_stress_sequence::type_id::create("push_stress_seq");
        pop_stress_seq  = fifo_pop_stress_sequence::type_id::create("pop_stress_seq");
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        int log_fd;
        string log_path;

        super.end_of_elaboration_phase(phase);

        if (uvm_config_db#(int)::get(this, "", "fifo_uvm_log_fd", log_fd))
        begin
            fifo_configure_hier_report(log_fd);
            if (!uvm_config_db#(string)::get(this, "", "fifo_uvm_log_path", log_path))
                log_path = "<unknown>";
            `uvm_info("TB_LOG", $sformatf("UVM report log file: %s", log_path), UVM_LOW)
        end
        else
        begin
            uvm_top.set_report_verbosity_level_hier(UVM_HIGH);
            `uvm_warning("TB_LOG", "No UVM log file handle configured; reports are display-only")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        reset_seq.start(env.push_agt.sqr);
        fill_seq.start(env.push_agt.sqr);
        drain_seq.start(env.pop_agt.sqr);

        fork
            push_stress_seq.start(env.push_agt.sqr);
            pop_stress_seq.start(env.pop_agt.sqr);
        join

        phase.phase_done.set_drain_time(this, 30);
        phase.drop_objection(this);
    endtask
endclass

module tb_Fifo;
    logic iClk = 0;
    int fifo_uvm_log_fd;
    string fifo_uvm_log_prefix;
    string fifo_uvm_log_arg;
    string fifo_uvm_log_path;
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
        // $dumpfile("wave_fifo.vcd");
        // $dumpvars(0, tb_Fifo);

        // Also support FSDB for conventional EDA tools
        // $fsdbDumpfile("wave_fifo.fsdb");
        // $fsdbDumpvars(0);

        // what?
        // UVM report log 파일을 여는 초기화 구간이다.
        // 기본 prefix는 "../../fifo_uvm_report"이고, sim script가 Vivado/<top>에서 실행되므로
        // 실제 파일은 project root의 fifo_uvm_report_001.log, fifo_uvm_report_002.log처럼 생성된다.
        // FIFO_UVM_LOG_PREFIX plusarg가 있으면 사용자가 원하는 prefix를 쓰고,
        // FIFO_UVM_LOG plusarg가 있으면 기존 호환을 위해 ".log" 확장자를 제거한 뒤 numbered log로 만든다.
        // 열린 file descriptor는 UVM config_db를 통해 fifo_test로 전달되고,
        // fifo_test의 end_of_elaboration_phase에서 모든 UVM component에 계층 적용된다.
        fifo_uvm_log_prefix = "../../fifo_uvm_report";
        void'($value$plusargs("FIFO_UVM_LOG_PREFIX=%s", fifo_uvm_log_prefix));
        if ($value$plusargs("FIFO_UVM_LOG=%s", fifo_uvm_log_arg))
            fifo_uvm_log_prefix = fifo_strip_log_extension(fifo_uvm_log_arg);
        fifo_uvm_log_fd = fifo_open_numbered_report_log(fifo_uvm_log_prefix, fifo_uvm_log_path);

        if (fifo_uvm_log_fd == 0)
        begin
            fifo_uvm_log_prefix = "fifo_uvm_report";
            fifo_uvm_log_fd = fifo_open_numbered_report_log(fifo_uvm_log_prefix, fifo_uvm_log_path);
        end

        if (fifo_uvm_log_fd == 0)
            $fatal(1, "[TB_LOG] Failed to open numbered UVM report log file");

        fifo_configure_root_report(fifo_uvm_log_fd);
        uvm_config_db#(int)::set(null, "uvm_test_top", "fifo_uvm_log_fd", fifo_uvm_log_fd);
        uvm_config_db#(string)::set(null, "uvm_test_top", "fifo_uvm_log_path", fifo_uvm_log_path);
        uvm_config_db#(virtual fifo_if)::set(null, "uvm_test_top.env.*", "vif", vif);

        run_test("fifo_test");

        if (fifo_uvm_log_fd != 0)
        begin
            $fdisplay(fifo_uvm_log_fd, "[TB_LOG] Closed UVM report log file");
            $fclose(fifo_uvm_log_fd);
        end
    end
endmodule
