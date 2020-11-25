#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# Usage: ./run_reliability.sh <model> <freqency> <voltage offset> <sequence number>

# Debug
#set -x

LC_ALL=C
export LC_ALL

# Try stopping the processes gracefully before terminating them.
# usage: stop <PID>...
stop()
{
    [ $# -lt 1 ] && fail "stop" "invalid number of arguments $#"
    kill -INT $*
    sleep 3
    if [ $? -eq 0 ]
    then
	for pid in $*
	do
	    [ $(ps -p $pid | wc -l) -nq 1 ] && kill -KILL $pid
	done
    fi
}

shutdown()
{
    SHUTDOWN=1
}

usage()
{
    printf "$0 model freqency voltage_offset sequence_number\n"
    printf "  model            device model name\n"
    printf "  frequency        CPU frequency of the device in MHz\n"
    printf "  voltage_offset   voltage offset in mV\n"
    printf "  sequence_number  sequence number of the benchmark repetition\n"
}

if [ $# -ne 4 ]
then
    printf " [%7s] main: invalid number of arguments $#\n" "ERROR"
    usage
    exit 1
fi

[ -s ./dsn ] && fail "main" "could not find private SSH key"

. error.sh

model=$1
freq=$2
volt=$3
seqno=$4

prefix=""
IP=172.29.10.5
SHUTDOWN=0

trap shutdown INT QUIT TERM

hre_powerspy.sh &
powerspypid=$!
sleep 45
ssh -C -o ServerAliveInterval=40 pi@$IP BSC/src/run_stress.sh &
sshpid=$!

while [ $SHUTDOWN -eq 0 ] && [ $(ps -p $sshpid | wc -l) -eq 2 ]
do
    sleep 1
done

[ $SHUTDOWN -ne 0 ] && stop $powerspypid $sshpid && exit $SHUTDOWN
sleep 4
kill -INT $powerspypid && wait $powerspypid
rc=$(wait $sshpid)
if [ $rc -ne 0 ]
then
    prefix="failed/"
    ./power_switch.sh rst 2
    sleep 60
fi
[ ! -d "../data/reliability/${model}/f${freq}/dU${volt}/${prefix}" ] && mkdir -p "../data/reliability/${model}/f${freq}/dU${volt}/${prefix}"
[ -s hre-energy.log ] && mv "../data/reliability/${model}/f${freq}/dU${volt}/${prefix}powerspy_${seqno}.log"
[ -s l2ping.log ] && mv "../data/reliability/${model}/f${freq}/dU${volt}/${prefix}l2ping_${seqno}.log"

# Retrieve the stress-ng log from the Raspberry Pi
# NOTE: if deployed in critical state, the Raspberry Pi might not have booted because it froze or paniced
scprc=1
while [ $scprc -ne 0 ]
do
    scp -i ./dsn pi@${IP}:/home/pi/stress-ng.log "../data/reliability/${model}/f${freq}/dU${volt}/${prefix}stress-ng_${seqno}.log"
    scprc=$?
    [ $scprc -ne 0 ] && ./power_switch rst 2 && sleep 60
done

# Reboot the Raspberry Pi
# NOTE: if deployed in critical state, the Raspberry Pi might not have booted because it froze or paniced
sshrc=1
while [ $sshrc -ne 0 ]
do
    [ $rc -eq 0 ] && ssh -i ./dsn pi@$IP sudo reboot
    sshrc=$?
    [ $sshrc -ne 0 ] && ./power_switch rst 2 && sleep 60
done
