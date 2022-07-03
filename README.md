# HSCC
HSCC is a Switch-based Congestion Control Framework for Data Centre Networks. 
Specifically, it aims at expanding the short TCP loss cycles via hysteresis switching and the switch control law switches between two rate modes at the end-host (i.e., TCP mode and slow CBR mode) 

It is implemented as a C simulation code in ns2 and as a hardware prototype in NetFPGA platform using verilog hardware language.

# Installation Guide
Please Refer to the \[[InstallME](InstallME.md)\] file for more information about installation and possible usage scenarios.

The simulations and real experiments based on the traffic generator is illustrated next

# Running experiments

To run an experiment of HSCC, install endhost-wndscale module on the end-hosts then run the following scripts:

```
cd scripts
<!--./run_hscc.sh one 1110 1 7000 1000 conf/client_config_oneWEB.txt 172.16.0.1:8001 XMLRPC 1 28 0 0 0 1 0-->
./incast.sh $p1 $p2 $p3 $p4 $p5 $p6 $p7 $p8 $p9
```
Or to an experiment involving elephants
```
cd scripts
<!--./run_hscc_varparam.sh one 1110 10 7000 1000 conf/client_config_oneWEB.txt 172.16.0.1:8001 XMLRPC 1 28 0 0 0 0 7 1-->
./incast_elephant.sh $p1 $p2 $p3 $p4 $p5 $p6 $p7 $p8 $p9
```
The scripts requires the following inputs:
```
# 1 : folder path
# 2 : experiment runtime
# 3 : number of clients per host
# 4 : interval of iperf reporting
# 5 : tcp congestion used
# 6 : # of webpage requests
# 7 : # of concurrent connections
# 8 : # of repetation of apache test
# 9 : is HSCC or normal switch
```

#Feedback
I always welcome and love to have feedback on the program or any possible improvements, please do not hesitate to contact me by commenting on the code [Here](https://ahmedcs.github.io/HSCC-post/) or dropping me an email at [ahmedcs982@gmail.com](mailto:ahmedcs982@gmail.com). **PS: this is one of the reasons for me to share the software.**  

**This software will be constantly updated as soon as bugs, fixes and/or optimization tricks have been identified.**


# License
This software including (source code, scripts, .., etc) within this repository and its subfolders are licensed under CRAPL license.

**Please refer to the LICENSE file \[[CRAPL LICENCE](LICENSE)\] for more information**


# CopyRight Notice
The Copyright of this repository and its subfolders are held exclusively by "Ahmed Mohamed Abdelmoniem Sayed", for any inquiries contact me at ([ahmedcs982@gmail.com](mailto:ahmedcs982@gmail.com)).

Any USE or Modification to the (source code, scripts, .., etc) included in this repository has to cite the following PAPERS:  

1- Ahmed M Abdelmoniem, Brahim Bensaou, " Control Theory Based Hysteresis Switch for Congestion Control in Data Centers", Technical Report, HKUST-CS17-01, Hong Kong, 2017.  

**Notice, the COPYRIGHT and/or Author Information notice at the header of the (source, header and script) files can not be removed or modified.**


# Published Paper
To understand the framework and proposed solution, please read the technical report \[[HSCC Tech-Repo PDF](download/HSCC-Report.pdf)\]
