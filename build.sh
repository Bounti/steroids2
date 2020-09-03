#!/bin/bash
export PATH=/media/vivado/Vivado/2018.3/bin/:$PATH
export PATH=/media/vivado/SDK/2018.3/bin/:$PATH

cd ~/usb3-to-jtag
make vv-clean vv-all
if [ $? -eq 0 ]
then
  echo "building bitfile --> ok"
else
  echo "Could not create bitfile" >&2
fi


make VVBUILD=/opt/build/vv DTSBUILD=/opt/build/dts XDTS=/opt/downloads/device-tree-xlnx dts
if [ $? -eq 0 ]
then
  echo "exporting device tree --> ok"
else
  echo "Could not export device tree" >&2
fi

cd /opt/build
export PATH=/opt/build/dts:$PATH
dtc -I dts -O dtb -o devicetree.dtb dts/system.dts
if [ $? -eq 0 ]
then
  echo "building system.dts --> ok"
else
  echo "Could not create file" >&2
fi

####
# First Stage Boot Loader (FSBL)
####
cd ~/usb3-to-jtag
export PATH=/media/vivado:$PATH
make VVBUILD=/opt/build/vv FSBLBUILD=/opt/build/fsbl fsbl
if [ $? -eq 0 ]
then
  echo "Building fsbl --> ok"
else
  echo "Could not create fsbl" >&2
fi

make -C /opt/build/fsbl
if [ $? -eq 0 ]
then
  echo "Build fsbl"
else
  echo "Could not create fsbl" >&2
fi

####
# Zynq boot image
####
cd /opt
bootgen -w -image /opt/downloads/sab4z/scripts/boot.bif -o boot.bin

cp /opt/boot.bin /media/vivado/boot_files/boot_v2_latest.bin
