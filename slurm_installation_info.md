# Introduction
This document provides step-by-step instructions for installing and configuring Slurm—an open-source workload manager—inside a Docker container. It covers the installation of necessary tools, setting up MUNGE for authentication, building Slurm from source, generating a basic `slurm.conf`, and troubleshooting common errors.

# Using Docker for Slurm Testing
## Running an Ubuntu 20.04 Container
To test the Slurm installation in a Docker container, start by running:

```
docker run -it ubuntu:20.04 bash
``` 
## Installing Required Tools in Docker
Once inside the container, update the package lists and install basic networking and utility tools:
```
apt update && \
apt install -y munge libmunge-dev libmunge2 && \
apt install -y \
build-essential \
gcc \
g++ \
make \
python3 \
libssl-dev \
libpam0g-dev \
libhwloc-dev \
libnuma-dev \
libmysqlclient-dev \
libjson-c-dev \
libhttp-parser-dev \
liblz4-dev \
libfreeipmi-dev \
libyaml-dev \
man2html \
wget \
bzip2 \
nano \
wget
```

# MUNGE Setup
Start the MUNGE service:
```
service munge start
#munge -n | unmunge
```

# SLURM Installation
## Create the Slurm User and Directories:

```
useradd -m -d /var/lib/slurm -s /bin/bash slurm
mkdir -p /var/spool/slurmctld /var/log/slurm
chown slurm:slurm /var/spool/slurmctld /var/log/slurm
```
## Download and Build slurm:
```
wget https://download.schedmd.com/slurm/slurm-23.02.3.tar.bz2
tar xvf slurm-23.02.3.tar.bz2 
cd slurm-23.02.3
./configure --prefix=/usr/local/slurm --sysconfdir=/etc/slurm
make -j$(nproc)
make install
```
## Create the Slurm Configuration Directory:
```
mkdir -p /etc/slurm
```

# Configuring slurm.conf
You can generate a basic `slurm.conf` using [`generate_slurm_conf.sh`](https://github.com/SeqExplorer/slurm_configuration/blob/main/generate_slurm_conf.sh). For a more detailed configuration guide, check out the [Slurm Configurator](https://slurm.schedmd.com/configurator.html)


Below are some key configuration considerations:

## Checking and Configuring `StateSaveLocation`
The `StateSaveLocation` is where Slurm stores its state information. It must be:

Accessible by the Slurm user (slurm)
Writable by all SlurmctldHost nodes (if running in a multi-node setup)
Ideally on a shared filesystem (NFS, Lustre, etc., if multiple controllers exist)

## Process Tracking
**Cgroup** is the best choice because:

It creates a job container using Linux cgroups, ensuring that all job processes are properly tracked.
It prevents jobs from escaping Slurm’s control by restricting them within their assigned cgroup.
It allows better resource enforcement (e.g., CPU, memory limits).
It requires a cgroup.conf file, but Slurm provides a default.
```
mount | grep cgroup
```

If it returned:
```
cgroup2 on /sys/fs/cgroup type cgroup2 (rw,nosuid,nodev,noexec,relatime,nsdelegate,memory_recursiveprot)
``` 
then set `ProcTrackType=cgroup` 

If it was empty then install:
```
apt install -y libcgroup-dev
```

Create `cgroup.conf` in `/etc/slurm/cgroup.conf`:
```
AllowedRAMSpace=95
AllowedSwapSpace=0
ConstrainSwapSpace=yes
ConstrainDevices=yes
CgroupAutomount=yes
ConstrainCores=yes
ConstrainRAMSpace=yes
```


## `TaskPlugin`

`None` ❌ (Not Recommended)
- Slurm will not manage tasks beyond basic job scheduling.
- No CPU affinity or resource enforcement.
- Use only if you don’t need fine control over resources.

`Affinity` ✅ (Recommended in HPC setups)
- Controls CPU binding (pinning tasks to specific CPUs).
- Helps optimize performance for NUMA architectures.
- Allows srun to use --cpu-bind, --mem-bind, and -E options.

`Cgroup` ✅ (Best for resource management)
- Uses Linux cgroups to enforce resource allocation.
- Prevents jobs from using more CPU/memory than allocated.
- Essential in multi-user environments.

**Which one to choose?**
| TaskPlugin Option | Use Case |
|------------------|-----------|
| **`None`** | Minimal setup, not recommended for real workloads. |
| **`Affinity`** | Optimizes CPU performance, but doesn’t enforce limits. |
| **`Cgroup`** | Enforces resource constraints but doesn’t optimize CPU affinity. |
| **`Cgroup,Affinity`** | ✅ **Best choice:** Enforces limits AND optimizes CPU binding. |

## `JobCompType`
The best choice depends on how you want to store, analyze, and process job completion data.  

| **JobCompType**    | **Use Case**                               | **Pros**                                      | **Cons**                                    |
|--------------------|-------------------------------------------|----------------------------------------------|--------------------------------------------|
| **`None`**        | No job completion logging                 | Simple, no setup required                    | No job tracking                            |
| **`FileTxt`**     | Logs to a text file (default option)      | Easy to set up, human-readable               | Hard to search/query                       |
| **`MySQL`**       | Logs to a MySQL/MariaDB database          | Structured, supports queries & analytics     | Requires a running MySQL server            |
| **`Elasticsearch`** | Logs to an Elasticsearch server        | Scalable, real-time search & analytics       | Requires Elasticsearch setup               |
| **`Kafka`**       | Streams job logs to Kafka                 | Best for real-time distributed processing    | Requires Kafka setup                       |
| **`Lua`**        | Uses `jobcomp.lua` script for logging     | Highly customizable                          | Requires writing a Lua script              |
| **`Script`**     | Runs a custom script for logging          | Fully flexible, can integrate with any system | Requires scripting knowledge               |

`script` can be safer choice. 



## basic slurm.conf
```
ClusterName=single-node-cluster
SlurmctldHost=localhost
MpiDefault=none
ProctrackType=proctrack/linuxproc
ReturnToService=1
SlurmctldPort=6817
SlurmdPort=6818
AuthType=auth/munge
SlurmdSpoolDir=/var/spool/slurmctld
StateSaveLocation=/var/spool/slurmctld
SlurmdLogFile=/var/log/slurm/slurmd.log
SlurmctldLogFile=/var/log/slurm/slurmctld.log
NodeName=localhost CPUs=4 State=UNKNOWN
PartitionName=debug Nodes=ALL Default=YES MaxTime=INFINITE State=UP
```



# Troubleshooting Common Errors
## `bash: slurmctld: command not found`
Run the following to locate the Slurm command:
```
find / -name slurmctld 2>/dev/null
```

If you found `systemctld` in other pahts than expected (`/usr/local/slurm/bin/slurmctld`) then fix by updating environment variables:
```
echo 'export PATH=/usr/local/slurm/sbin:/usr/local/slurm/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/slurm/lib:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc
```


## `NodeName` issues 
Check the hostname by `hostname` and update `NodeName` and `SlurmctldHost` accordingly. 

## `slurmctld: fatal: Failed to initialize jobcomp plugin`
The issue is:
`slurmctld: error: jobcomp/script: failed to stat /etc/slurm/slurm_jobcomp_logger: No such file or directory` 

`slurm_jobcomp_logger` does not exist to write.  

Either create an excutable file:
```
nano /etc/slurm/slurm_jobcomp_logger
#!/bin/bash
echo "[$(date)] Job $SLURM_JOB_ID completed on $(hostname)" >> /var/log/slurm/jobcomp.log
exit 0
chmod +x /etc/slurm/slurm_jobcomp_logger
```
Or set `JonComp=none` .  


Then **restart slurm**.  


## `cgroup` issues
### Mounting 
Ensure cgroups are correctly mounted
```
mount | grep cgroup
#cgroup on /sys/fs/cgroup type cgroup2 (rw,nosuid,nodev,noexec,relatime)
```

Adjust the permission if required:
```
sudo chmod 777 /sys/fs/cgroup
```

### Plugin Failure
The Slurm cgroup plugin (task/cgroup) is failing, likely due to an incorrect or incomplete /etc/slurm/cgroup.conf setup.



### sinfo: error: resolve_ctls_from_dns_srv: res_nsearch error: Unknown host!; sinfo: error: fetch_config: DNS SRV lookup failed; sinfo: error: _establish_config_source: failed to fetch config; sinfo: fatal: Could not establish a configuration source 

#### `ClusterName` conflict:
-	cat /var/spool/slurmctld/clustername
-	cat /etc/hosts; should have `127.0.0.1 localhost` and the server ip address with hostname, if it was missing then try to update based on `hostname -I` output. 

#### `SlurmctldHost` 
- `SlurmctldHost=$(hostname)`
- 

#### Network:
- `ps -ef | grep slurmctld; netstat -tulnp | grep 6817` to check whether the port is listed or not.
  - if `netstat` was not installed, install it by: `apt update && apt install net-tools -y`
- Check firewall rules: `iptables -F` 
- Test connectivity from slurmd to slurmctld `scontrol ping` 


#### Permissions:
-	/var/run/slurmctld.pid

#### Typos:

