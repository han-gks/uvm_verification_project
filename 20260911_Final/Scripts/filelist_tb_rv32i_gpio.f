// GPIO system smoke-test file list
// Run: ./Scripts/sim.sh -f Scripts/filelist_tb_rv32i_gpio.f -top tb_rv32i_gpio

../../Src/pkg/rv32_pkg.sv
../../Src/data_path.sv
../../Src/control_unit.sv
../../Src/instruction_rom.sv
../../Src/apb_requester.sv
../../Src/apb_ram.sv
../../Src/GPI.sv
../../Src/GPO.sv
../../Src/GPIO.sv
../../Src/rv32i_cpu.sv

../../Testbench/tb_rv32i_gpio.sv
