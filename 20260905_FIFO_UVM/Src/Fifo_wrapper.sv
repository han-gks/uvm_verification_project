`timescale 1ns / 1ps

module Fifo_wrapper (
    input logic       iClk,
    input logic       iRst,
    input logic       iPush,
    input logic       iPop,
    input logic [7:0] iWrDt
);
    logic [7:0] oRdDt;
    logic       oFull;
    logic       oEmpty;

    Fifo #(
        .ADDR_WIDTH(2),
        .DATA_WIDTH(8)
    ) u_fifo (
        .iClk   (iClk),
        .iRst   (iRst),
        .iPush  (iPush),
        .iPop   (iPop),
        .iWrDt  (iWrDt),
        .oRdDt  (oRdDt),
        .oFull  (oFull),
        .oEmpty (oEmpty)
    );

    fifo_sva u_sva (
        .iClk   (iClk),
        .iRst   (iRst),
        .iPush  (iPush),
        .iPop   (iPop),
        .oRdDt  (oRdDt),
        .oFull  (oFull),
        .oEmpty (oEmpty)
    );

`ifdef FORMAL
    logic f_past_valid = 0;
    always @(posedge iClk) begin
        f_past_valid <= 1;
        if (!f_past_valid) begin
            assume(iRst == 1'b1);
        end
    end
`endif

endmodule
