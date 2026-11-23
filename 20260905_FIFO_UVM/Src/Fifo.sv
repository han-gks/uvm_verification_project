/**************************************************************
 - Project          : 20260905_FIFO_UVM
 - File name        : Fifo.sv
 - Description      : Unified FIFO Module )
 - Owner            : Daegyu.Han
 - Revision history : 1) 2026.09.05 : Initial release in SV
**************************************************************/
`timescale 1ns / 1ps

module Fifo #(
    parameter ADDR_WIDTH = 2,
    parameter DATA_WIDTH = 8
)(
    input   logic                   iClk,
    input   logic                   iRst,

    input   logic                   iPush,
    input   logic                   iPop,
    input   logic [DATA_WIDTH-1:0]  iWrDt,

    output  logic [DATA_WIDTH-1:0]  oRdDt,
    output  logic                   oFull,
    output  logic                   oEmpty
);

    /***********************************************
    // Declarations
    ***********************************************/
    localparam DEPTH = 2 ** ADDR_WIDTH;

    // Memory array
    logic [DATA_WIDTH-1:0]  rMem [0:DEPTH-1];

    // Pointers & Flags
    logic [ADDR_WIDTH-1:0]  rWrPtr;
    logic [ADDR_WIDTH-1:0]  rRdPtr;
    logic                   rFull;
    logic                   rEmpty;

    /***********************************************
    // Control Signals & Enable Flags
    ***********************************************/
    wire wEnPushOnly = (iPush && !iPop && !rFull) || (iPush && iPop && rEmpty);
    // error test
    //wire wEnPushOnly = (iPush && !iPop) || (iPush && iPop && rEmpty);
    wire wEnPopOnly  = (!iPush && iPop && !rEmpty) || (iPush && iPop && rFull);
    wire wEnPushPop  = (iPush && iPop && !rFull && !rEmpty);

    wire wEnMemWrite = wEnPushOnly || wEnPushPop;


    /***********************************************
    // Datapath & Pointers 
    ***********************************************/
    always_ff @(posedge iClk, posedge iRst)
    begin
        if(iRst)
        begin
            rWrPtr <= 0;
            rRdPtr <= 0;
            rFull  <= 1'b0;
            rEmpty <= 1'b1;
        end
        else
        begin
            if(wEnPushOnly)
            begin
                rWrPtr <= rWrPtr + 1'b1;
                rEmpty <= 1'b0;
                if(rWrPtr + 1'b1 == rRdPtr)
                    rFull <= 1'b1;
            end
            
            else if(wEnPopOnly)
            begin
                rRdPtr <= rRdPtr + 1'b1;
                rFull  <= 1'b0;
                if(rWrPtr == rRdPtr + 1'b1)
                    rEmpty <= 1'b1;
            end
            
            else if(wEnPushPop)
            begin
                rWrPtr <= rWrPtr + 1'b1;
                rRdPtr <= rRdPtr + 1'b1;
            end
        end
    end

    /***********************************************
    // Memory (Register File)
    ***********************************************/
    always_ff @(posedge iClk)
    begin
        if(wEnMemWrite)
            rMem[rWrPtr] <= iWrDt;
    end

    /***********************************************
    // Output Assignments
    ***********************************************/
    assign oRdDt  = rMem[rRdPtr];
    assign oFull  = rFull;
    assign oEmpty = rEmpty;

endmodule
