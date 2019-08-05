# What?

USB3-to-JTag is a low latency USB3-based debugger.

# How ?

To compile the design, we highly recommand you to use the dockerfile.
As Vivado is not present inside the container, you need to provide it using Docker volume.

```
sudo docker run -ti -v /path/to/Xilinx/:/media/vivado -t xilinx_zedboard /bin/bash
```
