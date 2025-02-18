vcom ./hdl/fifo_ram.vhd
vcom ./hdl/fifo_ram_32_to_64.vhd
vcom ./hdl/inception_pkg.vhd
vcom ./hdl/JTAG_Ctrl_Master.vhd
vcom ./hdl/tristate_simu.vhd
vcom ./hdl/oddr2_simu.vhd
vcom ./hdl/inception.vhd
vcom ./hdl/inception_tb.vhd

vsim -novopt work.inception_tb

do ./scripts/wave.do

run 600000 ns
