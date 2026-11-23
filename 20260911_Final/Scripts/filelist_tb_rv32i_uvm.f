// RV32I core-only UVM file list

// RTL: package first, then datapath/control and core wrapper
../../Src/pkg/rv32_pkg.sv
../../Src/data_path.sv
../../Src/control_unit.sv
../../Src/rv32i_cpu.sv
../../Src/GPI.sv
../../Src/GPO.sv
../../Src/GPIO.sv

// Verification bind infrastructure
../../Testbench/bind/rv32i_probe_if.sv
../../Testbench/bind/rv32i_core_assertions.sv
../../Testbench/bind/rv32i_core_probe.sv
../../Testbench/bind/rv32i_bind.sv

// UVM top
../../Testbench/tb_rv32i_uvm.sv
