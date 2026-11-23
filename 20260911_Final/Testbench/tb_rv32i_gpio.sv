`timescale 1ns / 1ps

// Minimal GPIO system smoke test.
// It only loads rom_code_gpio.mem, releases reset, and lets the CPU run.
module tb_rv32i_gpio;

  localparam time CLK_PERIOD = 10ns;
  localparam time RUN_TIME   = 10us;

  logic       clk;
  logic       rst_n;
  logic [7:0] iSw;
  logic [7:0] oLed;

  rv32i_top #(
    .ROM_FILE ("../../Src/rom_code_gpio.mem")
  ) dut (
    .clk   (clk),
    .rst_n (rst_n),
    .iSw   (iSw),
    .oLed  (oLed)
  );

  always #(CLK_PERIOD / 2) clk = ~clk;

  initial begin
    clk   = 1'b0;
    rst_n = 1'b0;
    iSw   = 8'h00;

    repeat (2) @(posedge clk);
    rst_n = 1'b1;

    #(RUN_TIME);
    $display("[TB_GPIO] completed at %0t, iSw=0x%02h, oLed=0x%02h",
             $time, iSw, oLed);
    $finish;
  end

endmodule
