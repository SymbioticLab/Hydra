Hydra : Resilient and Highly Available Remote Memory
====
Hydra is a low-latency, low-overhead, and highly available resilience mechanism for remote memory. 
It can access erasure-coded remote memory within a single-digit microsecond read/write latency, significantly improving the performance-efficiency tradeoff over the state-of-the-art – it performs similar to in-memory replication with 1.6X lower memory overhead. 
Hydra emplys CodingSets, a novel coding group placement algorithm for erasure-coded data, that provides load balancing while reducing the probability of data loss under correlated failures by an order of magnitude. 
With Hydra, even when only 50% memory is local, unmodified memory-intensive applications achieve performance close to that of the fully in-memory case in the presence of remote failures and outperforms the state-of-the-art remote-memory solutions by up to 4.35X. 

Detailed design and performance benchmarks are available in our [FAST'22 paper](https://www.usenix.org/conference/fast22/presentation/lee).

Prerequisites
-----------

The following prerequisites are required to use Hydra:  

* Software  
  * Operating system: Ubuntu 14.04 (kernel 3.13.0, also tested on 4.4.0/4.11.0)
  * Container: LXC (or any other container technologies) with cgroup (memory and swap) enabled  
  * RDMA NIC driver: [MLNX_OFED 3.2/3.3/3.4/4.1](http://www.mellanox.com/page/products_dyn?product_family=26), and select the right version for your operating system. 

* Hardware  
   * Mellanox ConnectX-3/4 (InfiniBand)
   * An empty and unused disk partition

Code Organization
-----------
The Hydra codebase is organized under three directories.

* `resilience_manager`: Hydra Resilience Manager (kernel module).
* `resource_monitor`: Hydra Resource Monitor (user-level process) that exposes its local memory as remote memory.
* `setup`: setup scripts.

Important Parameters
-----------

Some important parameters in Hydra using erasure coding for fault-tolerance:  
* `resilience_manager/infiniswap.h`

Uncomment macro below /\*EC setup\*/  
  * `NDATAS` [num of splits]    
  * `NDISKS` [num of splits+parity]    
    It define the easure coding parameters.  
 * `DATASIZE_G` [size in GB]    
    It defines the size of a Resilience Manager.  
  
```c
#define NDATAS 8 //number of splits 
#define NDISKS (NDATAS + 2) //number of splits+parity
#define DATASIZE_G 8 //size of each Resilience Manager in GB
```  
  * `MAX_SGL_LEN` [num of pages]    
    It specifies how many pages can be included in a single swap-out request (IO request).  
  * `BIO_PAGE_CAP` [num of pages]    
    It limits the maximum value of MAX_SGL_LEN.  
  * `MAX_MR_SIZE_GB` [size]  
    It sets the maximum number of slabs from a single Resource Monitor. Each slab is 1GB.
```c
#define MAX_SGL_LEN 1 
#define BIO_PAGE_CAP 32
#define MAX_MR_SIZE_GB 32 //this Hydra Resilience Manager can get 32 slabs from each Resource Monitor.
```

* `resource_monitor/rdma-common.h`
  * `MAX_FREE_MEM_GB` [size]   
    It is the maximum size (in GB) of remote memory this Resource Monitor can provide (from free memory of the local host).     
  * `MAX_MR_SIZE_GB` [size]   
    It limits the maximum number of slabs this Resource Monitor can provide to a single Resilience Manager.   
    This value should be the same of "MAX_MR_SIZE_GB" in "infiniswap.h".    
  * `MAX_CLIENT` [number]   
    It defines how many Resilience Manager a single Resource Monitor can connect to.     
  * `FREE_MEM_EVICT_THRESHOLD` [size in GB]   
    This is the "HeadRoom" mentioned in our paper.   
    When the remaining free memory of the host machines is lower than this threshold, Hydra Resource Monitor will start to evict mapped slabs.     
```c
// example, in "rdma-common.h" 
#define MAX_CLIENT 32     

/* Followings should be assigned based on 
 * memory information (DRAM capacity, regular memory usage, ...) 
 * of the host machine of Hydra Resource Monitor.    
 */
#define MAX_FREE_MEM_GB 32    
#define MAX_MR_SIZE_GB  32    
#define FREE_MEM_EVICT_THRESHOLD 8    
```

How to Build and Install
-----------

In a simple one-to-one experiment, we have two machines (M1 and M2).  
Applications run in container on M1. 
M1 needs remote memory from M2.  
We need to install Resilience Manager on M1, and install Resource Monitor on M2.  

1. Setup InfiniBand NIC on both machines:  
```bash  
cd setup  
# ./ib_setup.sh <ip>    
# assume all IB NICs are connected in the same LAN (192.168.0.x)
# M1:192.168.0.11, M2:192.168.0.12
sudo ./ib_setup.sh 192.168.0.11
```
2. Compile Resource Monitor on M2:
```bash  
cd resource_monitor
make
```
3. Install Resilience Manager on M1:  
```bash  	
cd resilience_manager  
./autogen.sh
./configure
make  
sudo make install
```

How to Run
-----------
1. Start Resource Monitor on M2:  
```bash  	
cd resource_monitor   
# ./resource_monitor <ip> <port> 
# pick up an unused port number
./resource_monitor 192.168.0.12 9400
```
2. Prepare server (portal) list on M1:  
```  
# Edit the port.list file (<Hydra path>/setup/portal.list)
# portal.list format, the port number of each server is assigned above.  
Line1: number of servers
Line2: <server1 ip>:<port>  
Line3: <server2 ip>:<port>
Line4: ...
```
```bash  
# in this example, M1 only has one server
1
192.168.0.12:9400
```
3. Disable existing swap partitions on M1:
```bash  	
# check existing swap partitions
sudo swapon -s

# disable existing swap partitions
sudo swapoff <swap partitions>
```
4. Create a Resilience Manager on M1:  
```bash  	
cd setup
# create Resilience Manager: nbdx-hydra0
# make nbdx-hydra0 a swap partition
sudo ./resilience_manager_setup.sh
```

```bash  	
# If you have the error: 
#   "insmod: ERROR: could not insert module hydra.ko: Invalid parameters"
# or get the following message from kernel (dmesg):
#   "hydra: disagrees about version of symbol: xxxx"
# You need a proper Module.symvers file for the MLNX_OFED driver
#
cd resilience_manager
make clean
cd ../setup
# Solution 1 (copy the Module.symvers file from MLNX_OFED):
./get_module.symvers.sh
# Or solution 2 (generate a new Module.symvers file)
#./create_Module.symvers.sh
# Then, recompile Hydra Resilience Manager from step 3 in "How to Build and Install"
```

5. Configure memory limitation of container (LXC)  
```bash  	
# edit "memory.limit_in_bytes" in "config" file of container (LXC)

# For example, this container on M1 can use 5GB local memory at most.
# Additional memory data will be stored in the remote memory provided by M2.   
lxc.cgroup.memory.limit_in_bytes = 5G
```

Now, you can start your applications (in container).     
The extra memory data from applications will be stored in remote memory.   

FAQ
----------
1. Does Hydra support transparent huge page?   
**Yes.**
Hydra relies on the swap mechanism in the original Linux kernel.
Current kernel (we have tested up to 4.10) splits the huge page into basic pages (4KB) before swapping out the huge page.  
(In `mm/vmscan.c`, `shrink_page_list()` calls `split_huge_page_to_list()` to split the huge page.)   
Therefore, whether transparent huge page is enabled or not makes no difference for Hydra.   

2. Can we use Docker container, other than LXC?    
**Yes.**
Hydra requires container-based environment. 
However, it has no dependency on LXC. Any container technologies that can limit memory resource and enable swapping should be feasible.  
We haven't tried Docker yet. If you find any problems when running Hydra in a Docker environment, please contact us.  

3. Invalid parameters error when insert module?
There are two ways of compiling Hydra; using 1) inbox driver 2) Mellanox OFED
When you use inbox driver, you can compile/link against kernel headers/modules.
When you use Mellanox OFED, you need to compile/link against OFED headers/modules.
This should be handled by configure file, and refer the Makefile that links OFED modules.


Contact
-----------
This work is by [Youngmoon Lee](https://sites.google.com/umich.edu/youngmoonlee/home), [Hasan Al Maruf](https://web.eecs.umich.edu/~hasanal/), [Mosharaf Chowdhury](http://www.mosharaf.com/), [Kang G. Shin](https://web.eecs.umich.edu/~kgshin/), and [Asaf Cidon](https://www.asafcidon.com/). 
You can email us at `infiniswap at umich dot edu`, file issues, or submit pull requests.
