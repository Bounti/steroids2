# What?

USB3-to-JTag is a low latency USB3-based debugger.
It enables memory accesses for ARM processors using the Coresight design.
It has been tested on Cortex M3/M4 processors.

This project is based on sab4z, a example design for Zynq-based device.
For more details, please visit:
https://gitlab.telecom-paristech.fr/renaud.pacalet/sab4z

# How ?

To compile the design, we highly recommand you to use the dockerfile.
As Vivado is not present inside the container, you need to provide it using Docker volume.

```
sudo docker run -ti -v /path/to/Xilinx/:/media/vivado -t xilinx_zedboard /bin/bash
```

Once the docker started, run this command inside to build the design:
```
cd ~
bash ./build.sh
```

Then you need to copy the generated bit file on a SDCard and set Zedboard boot pins as follow:
```
JMP11 OFF
JMP10 ON
JMP9  On
JMP8  OFF
```

# Simulation

Simulation files are set for Modelsim only.

```
vlib work

vsim -do scripts/sim.do
```
