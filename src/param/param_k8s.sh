#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Christian Göttel

# Debug
#set -x

LC_ALL=C
export LC_ALL

check_ntp()
{
    val=$(timedatectl status | grep -e 'NTP synchronized:' | cut -d ' ' -f 3)
    if [ "x$val" = "xno" ]
    then
	sudo timedatectl set-ntp true
	if [ $? -ne 0 ]
	then
	    printf "check_ntp: failed to enable NTP\n" >&2
	    exit 1
	fi
    fi
}

if [ ! -x "./logger.sh" ]
then
    printf "ERROR: cannot find script ./logger.sh\n" >&2
    exit 1
fi

check_ntp
printf "NTP enabled\n"
sudo swapoff -a
sudo systemctl daemon-reload
printf "node joined k8s cluster\n"
cnt="N"
while [ "x$cnt" != "xY" ] && [ "x$cnt" != "xy" ]
do
    printf "node entered ready state [Y/N]? "
    read cnt
done
sudo cpupower frequency-set -g performance
until [ "x$gov" = "xperformance" ]
do
    gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
done
printf "cpufreq governor set to '$gov'\n"
sudo nice -n -12 ./logger.sh &
printf "logger started\n"
printf "infinite mulX_docker can be started\n"
