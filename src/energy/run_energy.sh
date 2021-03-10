#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Christian Göttel

# Run a CPU and a memory bound stress-ng stressor on a sever-grade machine to
# measure the energy gap to a Raspberry Pi.
# Usage: ./run_energy.sh <pdu> <server> <sequence number> <ssh_key> <ssh_user>

# Debug
#set -x

LC_ALL=C
export LC_ALL

DIR="scrooge/src"

# Try stopping the processes gracefully before terminating them.
# usage: stop <PID>...
stop()
{
    [ $# -lt 1 ] && fail "stop" "invalid number of arguments $#/1+"
    kill -INT $*
    sleep 3
    if [ $? -eq 0 ]
    then
	for pid in $*
	do
	    [ $(ps -p $pid | wc -l) -ne 1 ] && kill -KILL $pid
	done
    fi
}

shutdown()
{
    SHUTDOWN=1
}

usage()
{
    printf "$0 <pdu> <server> <sequence_number> <ssh_key> <ssh_user>\n"
    printf "  pdu              PDU FQDN\n"
    printf "  server           server FQDN\n"
    printf "  sequence_number  sequence number of the benchmark repetition\n"
    printf "  ssh_key          SSH key to log on server\n"
    printf "  ssh_user         SSH user to log on server\n"
}

if [ $# -ne 5 ]
then
    printf " [%7s] main: invalid number of arguments $#/5\n" "ERROR"
    usage
    exit 1
fi

. ../error.sh

pdu=$1
server=$2
seqno=$3
ssh_key=$4
ssh_user=$5

prefix=""
SHUTDOWN=0

[ ! -s "$ssh_key" ] && fail "main" "could not find private SSH key"

trap shutdown INT QUIT TERM

python3 pdu-power-parser.py pdu.csv "$pdu" 1 >pdu.log 2>&1 &
pythonpid=$!
sleep 45
ssh -C -i "$ssh_key" -o ServerAliveInterval=40 ${ssh_user}@$server "$DIR"/run_stress.sh energy &
sshpid=$!

while [ $SHUTDOWN -eq 0 ] && [ $(ps -p $sshpid | wc -l) -eq 2 ]
do
    sleep 1
done

stop $pythonpid
[ $SHUTDOWN -ne 0 ] && stop $sshpid && exit $SHUTDOWN
sleep 4
kill -INT $pythonpid && wait $pythonpid
rc=$(wait $sshpid)
[ ! -d "../../data/energy/${server}/${prefix}" ] && mkdir -p "../../data/energy/${server}/${prefix}"
[ -s pdu.csv ] && mv pdu.csv "../../data/energy/${server}/${prefix}pdu_${seqno}.csv"
[ -s pdu.log ] && mv pdu.log "../../data/energy/${server}/${prefix}pdu_${seqno}.log"

# Retrieve the stress-ng log from the server
scprc=1
while [ $scprc -ne 0 ]
do
    scp -i "$ssh_key" ${ssh_user}@${server}:/home/${ssh_user}/$DIR/stress-ng.log "../../data/energy/${server}/${prefix}stress-ng_${seqno}.log"
    scprc=$?
done
