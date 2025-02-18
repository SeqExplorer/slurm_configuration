#!/bin/bash
set -e

echo "Extracting system information..."

# CPUs
CPUs=$(nproc)

# Boards (typically 1 for a single machine)
Boards=1

# Get number of CPU sockets
SocketsPerBoard=$(lscpu | awk '/Socket\(s\)/ {print $2}')

# Get number of cores per socket
CoresPerSocket=$(lscpu | awk '/Core\(s\) per socket/ {print $4}')

# Get number of threads per core
ThreadsPerCore=$(lscpu | awk '/Thread\(s\) per core/ {print $4}')

# Get available real memory in MB
RealMemory=$(free -m | awk '/Mem:/ {print $2}')

# Get node name from hostname
NodeName=$(hostname)

echo "Boards=$Boards"
echo "SocketsPerBoard=$SocketsPerBoard"
echo "CoresPerSocket=$CoresPerSocket"
echo "ThreadsPerCore=$ThreadsPerCore"
echo "RealMemory=$RealMemory"
echo "CPUs=$CPUs"
echo "NodeName=$NodeName"

# Optionally save these values to a file
cat <<EOL > slurm_config_values.txt
Boards=$Boards
SocketsPerBoard=$SocketsPerBoard
CoresPerSocket=$CoresPerSocket
ThreadsPerCore=$ThreadsPerCore
RealMemory=$RealMemory
CPUs=$CPUs
NodeName=$NodeName
EOL

echo "Checking MPI Type for Slurm..."

# Default MPI setting
MpiDefault="none"

# Check if mpirun is installed and determine MPI type
if command -v mpirun &>/dev/null; then
    if ldd "$(command -v mpirun)" 2>/dev/null | grep -q libpmi2; then
        MpiDefault="mpi-pmi2"
    elif ldd "$(command -v mpirun)" 2>/dev/null | grep -q libpmix; then
        MpiDefault="mpi-pmix"
    fi
fi

echo "MpiDefault=$MpiDefault"
echo "MpiDefault=$MpiDefault" > mpi_config.txt

echo "Generating slurm.conf without cgroup resource management..."

cat <<EOF > slurm.conf
ClusterName=Hulk
SlurmctldHost=Hulk
MpiDefault=${MpiDefault}
ProctrackType=proctrack/linuxproc

AuthType=auth/munge
CredType=cred/munge

SlurmctldPort=6817
SlurmdPort=6818

SlurmctldPidFile=/var/run/slurmctld.pid
SlurmdPidFile=/var/run/slurmd.pid
SlurmdSpoolDir=/var/lib/slurm/slurmd

SlurmUser=slurm
StateSaveLocation=/var/lib/slurm/slurmctld

SwitchType=switch/none

# cgroup resource management has been removed per requirements
#TaskPlugin=task/cgroup
TaskPlugin=task/none

# Timer settings
InactiveLimit=0
KillWait=30
MinJobAge=300
SlurmctldTimeout=120
SlurmdTimeout=300
Waittime=0

# Scheduling settings
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory

# Logging settings
SlurmctldDebug=info
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdDebug=info
SlurmdLogFile=/var/log/slurm/slurmd.log
SlurmctldSyslogDebug=error
SlurmdSyslogDebug=error

# Define the node using extracted values
NodeName=${NodeName} CPUs=${CPUs} RealMemory=${RealMemory} Sockets=${SocketsPerBoard} CoresPerSocket=${CoresPerSocket} ThreadsPerCore=${ThreadsPerCore} State=IDLE

# Define partitions
PartitionName=main Nodes=${NodeName} Default=YES MaxTime=10-0 State=UP
EOF

echo "slurm.conf generated successfully."
