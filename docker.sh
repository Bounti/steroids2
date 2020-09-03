#!/usr/bin/env bash
sudo docker stop $(sudo docker ps -a -q  --filter ancestor=xilinx_zedboard)
sudo docker rm $(sudo docker ps -a -q  --filter ancestor=xilinx_zedboard)

sudo docker run --network host -i -v /home/nasm/Tools/Xilinx/:/media/vivado -v /home/nasm/Projects/usb3-to-jtag/:/home/sab4z/usb3-to-jtag -t xilinx_zedboard /bin/bash
