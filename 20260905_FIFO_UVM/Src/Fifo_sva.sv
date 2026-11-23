// Fifo_sva.sv
`ifndef FORMAL
import uvm_pkg::*;
`endif

module fifo_sva (
    input logic       iClk,
    input logic       iRst,
    input logic       iPush,
    input logic       iPop,
    input logic [7:0] oRdDt,
    input logic       oFull,
    input logic       oEmpty
);

`ifndef FORMAL
    // =================================================================
    // 1. UVM 시뮬레이션용 원본 SVA (SBY 정형검증 시에는 무시됨)
    // =================================================================
    
    // 1. Mutex Check: Full and Empty cannot be High simultaneously
    property p_mutex_full_empty;
        @(posedge iClk) disable iff(iRst) 
        !(oFull && oEmpty);
    endproperty
    A_MUTEX_FLAGS: assert property(p_mutex_full_empty) 
        else begin
            uvm_report_error("SVA_MUTEX_FLAGS",
                             "Full and Empty asserted simultaneously!",
                             UVM_LOW);
        end

    // 2. Overflow Protection Check
    property p_overflow_protect;
        @(posedge iClk) disable iff(iRst)
        (oFull && iPush && !iPop) |=> oFull;
    endproperty
    A_OVERFLOW: assert property(p_overflow_protect)
        else begin
            uvm_report_error("SVA_OVERFLOW",
                             "Overflow protection failed!",
                             UVM_LOW);
        end

    // 3. Underflow Protection Check
    property p_underflow_protect;
        @(posedge iClk) disable iff(iRst)
        (oEmpty && iPop && !iPush) |=> oEmpty;
    endproperty
    A_UNDERFLOW: assert property(p_underflow_protect)
        else begin
            uvm_report_error("SVA_UNDERFLOW",
                             "Underflow protection failed!",
                             UVM_LOW);
        end

    // 4. Data Stability Check
    property p_data_stability;
        @(posedge iClk) disable iff(iRst)
        (!$past(iPop) && !$past(oEmpty)) |-> $stable(oRdDt);
    endproperty
    A_DATA_STABILITY: assert property(p_data_stability)
        else begin
            uvm_report_error("SVA_DATA_STABILITY",
                             "Read data changed without a Pop!",
                             UVM_LOW);
        end

`else
    // =================================================================
    // 2. SBY 정형검증용 즉각 어서션 (Yosys 파서 최적화)
    // =================================================================
    logic f_past_valid = 0;
    always @(posedge iClk) begin
        f_past_valid <= 1;
    end

    always @(posedge iClk) begin
        // 리셋이 풀려있고, $past 데이터를 신뢰할 수 있는 2번째 클럭부터 검사 시작
        if (f_past_valid && !iRst) begin
            
            // 1. Mutex Check
            assert(!(oFull && oEmpty));

            // 이전 클럭에서도 리셋이 풀려있었을 때만 상태 천이(Transition) 검사
            if ($past(!iRst)) begin
                
                // 2. Overflow Protection
                if ($past(oFull) && $past(iPush) && !$past(iPop)) begin
                    assert(oFull);
                end
                
                // 3. Underflow Protection
                if ($past(oEmpty) && $past(iPop) && !$past(iPush)) begin
                    assert(oEmpty);
                end
                
                // 4. Data Stability
                if (!$past(iPop) && !$past(oEmpty)) begin
                    assert($stable(oRdDt));
                end
            end
        end
    end
`endif

endmodule
