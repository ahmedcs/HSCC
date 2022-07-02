# Prerequisites
To build the bitfile on the NetFPGA platform, you need to obtain the Ethernet MAC IP core specifically [Tri-Mode Ethernet Media Access Controller](https://www.xilinx.com/products/intellectual-property/temac.html) 

# Installation steps

change your current directory to to where the source and Makefile is located then issue:

```
git clone https://github.com/ahmedcs/HSCC.git
cd HSCC/synth
make
```

# OpenvSwitch version

You need to apply the patch that comes along with the source files to the "datapath" subfolder of the OpenvSwitch source directory. Notice that, the patch is customized to openvswitch version 2.4.0 and it may/may not work for other versions. If you are applying the patch to a different version, please read the patch file and update manually (few locations is updated).

The patch updates these files: (actions.c, datapath.c, datapath.h, Makefile.in, Module.mk)

Then you need to issue the patch command to patch (actions.c datapath.c, datapath.h, Makefile.in, Module.mk):

```
cd openvswitch-2.4.0/datapath
patch -p1 < hscc.patch
```

Copy the source and header files to the datapath folder (hscc.c and hscc.h), then we need to build and install the new openvswitch:

```
cd openvswtich-2.4.0
./configure --with-linux="/lib/modules/`uname -r`/build"
cd datapath
make clean
make
cd linux
sudo make modules_install
```

If the kernel module was not installed properly, it can be copied as follows (depending on the current location of the running OpenvSwitch):
```
cd openvswtich-2.4.0/datapath/linux
sudo cp openvswitch.ko /lib/modules/`uname -r`/kernel/net/openvswitch/openvswitch.ko
```

The location of the OpenvSwitch module can be found by the following:
```
modinfo openvswitch
```

# Kernel-Module Makefile update
If the source file has been changed, you need to update the name of the object file to match the new source file containing the module init_module and exit_module macros and the definition functions. SEE Makefile for more information.

Notice, you can include other source and header files but under the condition that there are a single source file containing the necessary init_module and exit_module macros and their function.


Now the output files is as follows:
```
hscc.o and hscc.ko
```
The file ending with .o is the object file while the one ending in .ko is the module file


# Run
To install the module into the kernel
```
sudo insmode hscc.ko
```
Now the module will do nothing until it is enabled by setting hygenicc_enable parameter as follows:   

```
sudo echo 1 > /sys/kernel/modules/iqm/parameters/hscc_enable;
```

Note that the parameters of the module are:  
1- hscc_enable: enable HSCC congestion control module, 0 is the default which disables packet interception.  

Also to call the module with different parameters issue the following:
```
sudo insmod hscc.ko hscc_enable=1;
```


# Stop

To stop the loss_probe module and free the resources issue the following command:

```
sudo rmmod -f hscc;
```

# SDN Controller Application

The simple layer 2 switch SDN controller has been adopted for implementing the HSCC SDN controller application.  
Another way to implement this is via leveraging the rich northbound API to sperate HSCC application from the real controller implementation (On-Going).

The Ryu Controller can be started on the Controller PC (which has to be connected to the switches under control) as follows:
```
cp HSCC/Controller-App/hscc_app.py ~/ryu/ryu/app/
cd ~/ryu
./bin/ryu-manager --verbose ryu/app/hscc_app.py
```

Now you need to ensure the switch is configured to connect to the controller and use the latest (preferably) openflow as follow:  
For example if the controller is located at 192.168.1.1 and want to use OF1.3
```
sudo ovs-vsctl set-controller ovsbr0 tcp:192.168.1.1:6633
sudo ovs-vsctl set bridge ovsbr0 protocols=OpenFlow13
```

Check out the configuration of the switch as follows:
```
sudo ovs-vsctl show
```

# For Tutorials on OvS and Ryu
Please check the following websites for more documentation and tutorials:  
```
https://osrg.github.io/ryu/
http://openvswitch.org
http://networkstatic.net/openflow-openvswitch-lab/
http://sdnhub.org/tutorials/ryu/
```