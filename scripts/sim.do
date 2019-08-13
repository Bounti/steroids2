vcom /home/nasm/Projects/usb3-to-jtag/hdl/fifo_ram.vhd
vcom /home/nasm/Projects/usb3-to-jtag/hdl/inception_pkg.vhd
vcom /home/nasm/Projects/usb3-to-jtag/hdl/JTAG_Ctrl_Master.vhd
vcom /home/nasm/Projects/usb3-to-jtag/hdl/ring_buffer.vhd
vcom /home/nasm/Projects/usb3-to-jtag/hdl/tristate_simu.vhd
vcom /home/nasm/Projects/usb3-to-jtag/hdl/oddr2_simu.vhd
vcom /home/nasm/Projects/usb3-to-jtag/hdl/inception.vhd
vcom /home/nasm/Projects/usb3-to-jtag/hdl/inception_tb.vhd

vsim -novopt work.inception_tb

do ../scripts/wave.do

run 600000 ns
