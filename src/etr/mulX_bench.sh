#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Christian Göttel

# Debug
#set -x

# Default Raspberry Pi 3B+ configurations:
# over_voltage_avs=? (cannot be set by user)
# over_voltage=0
# over_voltage_min=0
# gpu_freq=400

LC_ALL=C
export LC_ALL

readonly CSV="${0%sh}csv"
readonly LOG="${0%sh}log"

# Check if the command is available
# Usage: check_cmd <cmd>
check_cmd()
{
    if [ $# -ne 1 ]
    then
	printf "check_cmd: invalid number of arguments\n" >&2
	exit 1
    fi

    which $1 2>&1 >/dev/null
    if [ $? -ne 0 ]
    then
	printf "check_cmd: $1 command is not available\n" >&2
	exit 1
    fi
}

check_config()
{
    if [ ! -s /boot/config.txt ]
    then
	printf "check_config: /boot/config.txt is not available\n" >&2
	exit 1
    fi
}

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

check_systemd_run()
{
    check_cmd systemd-run
    systemd_ver=$(systemd-run --version | grep -e systemd | sed -e 's/^[[:alpha:]]\+[[:space:]]\+\([[:digit:]]\+\)[^[:digit:]]\{0,1\}.*$/\1/')
    if [ $systemd_ver -lt 241 ]
    then
	printf "ERROR: at least systemd-run version 241 is required (found $systemd_ver)\n" >&1
	exit 1
    fi
}

# Wait for the SoC to cool down to a specified temperature (might involve active cooling)
# NOTE: the operating temperature of the Raspberry Pi is about 50°C
# Usage: cooldown <T>
cooldown()
{
    if [ $# -ne 1 ]
    then
	printf "cooldown: invalid number of arguments\n" >&2
	exit 1
    fi
    target=$1
    target=$((target-1))
    temp=$(run_vcgencmd measure_temp | sed -e 's/^[^=]\+=\([[:digit:]]\+\)\..\+$/\1/')
    until [ $temp -le $target ]
    do
	sleep 1
	temp=$(run_vcgencmd measure_temp | sed -e 's/^[^=]\+=\([[:digit:]]\+\)\..\+$/\1/')
    done
    printf "Temperature of ${temp}°C reached\n" | tee -a "$LOG"
}

# Run vcgencmd, check for errors and print the output
# Usage: run_vcgencmd <cmd> [<option>]
# NOTE: the return code of vcgencmd is always zero
run_vcgencmd()
{
    if [ $# -lt 1 ] || [ 2 -lt $# ]
    then
	printf "run_vcgencmd: invalid number of arguments $#\n" >&2
	exit 1
    fi
    val=$(vcgencmd $1 $2)
    type=$(printf "$val" | sed -e 's/^\([^=]\+\)=.*$/\1/')
    if [ "x$type" = "xerror" ]
    then
	printf "run_vcgencmd: $val\n" >&2
	exit 1
    fi
    printf "$val\n"
}

get_config()
{
    for opt in arm_freq arm_freq_min core_freq core_freq_min gpu_freq gpu_freq_min h264_freq h264_freq_min isp_freq isp_freq_min v3d_freq v3d_freq_min over_voltage over_voltage_min
    do
	val=$(run_vcgencmd get_config $opt | sed -e 's/^[^=]\+=\([-[:digit:]]\+\)$/\1/')
	printf "%i," $val >>"$CSV"
    done
}

get_measure()
{
    for opt in arm core h264 isp v3d
    do
	val=$(run_vcgencmd measure_clock $opt | sed -e 's/^[^=]\+=\([[:digit:]]\+\)$/\1/')
	printf "$val," >>"$CSV"
    done
    val=$(run_vcgencmd measure_volts core | sed -e 's/^[^=]\+=\([[:digit:]]\+\.[[:digit:]]\+\)V$/\1/')
    printf "$val," >>"$CSV"
    val=$(run_vcgencmd measure_temp | sed -e 's/^[^=]\+=\([[:digit:]]\+\.[[:digit:]]\+\).\+$/\1/')
    printf "$val," >>"$CSV"
}

# Increase the temperature of the SoC to a specified value
# Usage: heatup <temp>
heatup()
{
    if [ $# -ne 1 ]
    then
	printf "heatup: invalid number of arguements\n" >&2
	exit 1
    elif [ 80 -lt $1 ]
    then
	printf "heatup: temperature out of range 50-80°C\n" >&2
	exit 1
    fi

    pid=""
    sudo ./mulX_bench -i &
    pid="$!"

    temp=$(run_vcgencmd measure_temp | sed -e 's/^[^=]\+=\([[:digit:]]\+\)\..\+$/\1/')
    until [ $temp -ge $1 ]
    do
	sleep 1
	# Check that none of the infinite loops have crashed
	cpids="$(ps -o "ppid user group comm pid" | grep -e "$$[[:space:]]\+root[[:space:]]\+root[[:space:]]\+mulX_bench" | sed -e 's/^.\+[[:space:]]\([[:digit:]]\+\)$/\1/' | sed ':a;N;$!ba;s/\n/ /g')"
	if [ $(printf "$cpids\n" | wc -w) -lt $(nproc) ]
	then
	    printf "$cpids\n" | grep -e $pid 2>&1 >/dev/null
	    if [ $? -eq 1 ]
	    then
		printf "heatup: infinite multiplication loop $pid has crashed, starting $!\n" | tee -a "$LOG"
		sudo ./mulX_bench -i &
		pid="$!"
	    fi
	fi
	temp=$(run_vcgencmd measure_temp | sed -e 's/^[^=]\+=\([[:digit:]]\+\)\..\+$/\1/')
    done
    kill -9 $pid
    printf "Temperature of ${temp}°C reached\n" | tee -a "$LOG"
}

# Set the over_voltage in config.txt
# Usage: set_over_voltage <val>
set_over_voltage()
{
    if [ $# -ne 1 ]
    then
	printf "set_over_voltage: invalid number of arguments\n" >&2
	exit 1
    elif [ $1 -lt -16 ] || [ 0 -lt $1 ]
    then
	printf "set_over_voltage: invalid range for under-volting\n" >&2
	exit 1
    fi

    sudo sed -i "s/^\(over_voltage[^=]*\)=[-[:digit:]]\+$/\1=$1/" /boot/config.txt
    rc=$?
    if [ $rc -eq 0 ]
    then
	printf "set_over_voltage: over_voltage set to $1\n" | tee -a "$LOG"
    else
	printf "set_over_voltage: could not substitute over_voltage $rc\n" >&2
    fi
}

# FIXME: this shell script is only partially executed when using systemd-run
schedule()
{
    # Start immediatetly after bootup
    sudo systemd-run --on-startup=30 --working-directory=$HOME --uid=$(id -u) --gid=$(id -g) sudo ${HOME}/mulX_bench.sh run 2>&1 | tee -a "$LOG"
    sync
    sudo reboot
}

# Run the benchmark and if necessary at a specific temperature.
# Usage: run [-t <T>]
run()
{
    printf "run: $(date)\n" | tee -a "$LOG"
    # NOTE: the cpufreq governor is reset after a reboot
    if [ $# -eq 2 ]
    then
	temp=$(run_vcgencmd measure_temp | sed -e 's/^[^=]\+=\([[:digit:]]\+\)\..\+$/\1/')
	if [ $2 -le $temp ]
	then
	    cooldown $2
            sudo cpupower frequency-set -g performance 2>&1 | tee -a "$LOG"
	else
            sudo cpupower frequency-set -g performance 2>&1 | tee -a "$LOG"
	    heatup $2
	fi
    else
	sudo cpupower frequency-set -g performance 2>&1 | tee -a "$LOG"
    fi
    until [ "x$gov" = "xperformance" ]
    do
	gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
    done
    printf "run: cpufreq governor set to '$gov'\n" | tee -a "$LOG"
    get_config
    # NOTE: configuration over_voltage_avs can be decimal or hexadecimal
    val=$(vcgencmd get_config over_voltage_avs | sed -e 's/^[^=]\+=\(-\)\{0,1\}\([[:alnum:]]\+\)$/\1\2/')
    case $val in
	0x* ) val=$(printf "${val#0x}\n" | tr abcdef ABCDEF)
	      val=$(printf "ibase=16; $val\n" | bc) ;;
    esac
    printf "%i," $val >>"$CSV"
    get_measure
    val=$(run_vcgencmd get_throttled | sed -e 's/^[^=]\+=\([[:alnum:]]\+\)$/\1/')
    printf "$val," >>"$CSV"
    sudo ./mulX_bench -l 2>&1 | tee -a "$LOG"
    rc=$?
    over_voltage=$(vcgencmd get_config over_voltage | sed -e 's/^[^=]\+=\([-[:digit:]]\+\)$/\1/')
    if [ $over_voltage -gt -16 ] && [ $rc -eq 0 ]
    then
	set_over_voltage $((over_voltage-1))
	# NOTE: for some reason this script cannot be scheduled
	#schedule
	printf "run: system is ready for reboot and next run\n" | tee -a "$LOG"
    else
	printf "Test finised: over_voltage = $over_voltage, rc = $rc\n" | tee -a "$LOG"
    fi
}

usage()
{
    printf "Multithreaded temperature-based multiplication benchmark\n"
    printf "usage: $0 help\n$0 precool <T>\n$0 preheat <T>\n$0 run [-t <T>]\n" #$0 schedule\n"
    printf "  help       print usage information\n"
    printf "  precool T  cool the SoC down to temperature T (>25°C)\n"
    printf "  preheat T  heat the SoC up to temperature T (<80°C)\n"
    printf "  run        run the multithreaded multiplication benchmark\n"
    printf "    -t T     tempering the SoC to temperature T (25-80°C)\n"
    # printf "  schedule  schedule the DVFS batch\n"
    # printf "NOTE: the Raspberry Pi will reboot automatically inbetween DVFS test runs\n"
}

if [ $# -lt 1 ] || [ 3 -lt $# ]
then
    printf "ERROR: invalid number of arguments\n" >&2
    usage
    exit 1
fi

case $1 in
    help) usage ;;
    precool) shift
	     cooldown $1 ;;
    preheat) shift
	     heatup $1 ;;
    run) shift
	# NOTE: check_* functions are necessary while schedule does not work
	check_systemd_run
	check_cmd cpupower
	check_cmd timedatectl	
	check_cmd vcgencmd
	check_config
	check_ntp
	run $@ ;;
    # schedule) check_systemd_run
    # 	      check_cmd vcgencmd
    # 	      check_config
    # 	      run
    # 	      schedule ;;
    *) printf "ERROR: invalid argument '$1'\n" >&2
       usage
       exit 1
esac
