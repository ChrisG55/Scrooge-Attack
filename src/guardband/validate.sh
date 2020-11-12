#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# Validate the measurements.

# Debug
#set -x

LC_ALL=C
export LC_ALL

DATADIR=../../data/guardband

fail()
{
    printf "ERROR: $*\n" >&2
    exit 1
}

warn()
{
    printf "WARNING: $*\n" >&2
}

check_directories()
{
    if [ -n "$*" ]
    then
	for d in $*
	do
	    if [ ! -d "$d" ]
	    then
		fail "'$d' is not a directory"
	    fi
	done
    else
	fail "no directories found"
    fi
}

filter()
{
    pat=$1
    shift
    for v; do
        eval "case '$v' in $pat) printf '%s ' '$v' ;; esac"
    done
}

filter_out()
{
    pat=$1
    shift
    for v; do
        eval "case '$v' in $pat) ;; *) printf '%s ' '$v' ;; esac"
    done
}

# The last line of the PowerSpy log file should be complete and should not be missing any columns due to a SIGINT.
# usage: powerspy_format <PowerSpy log>
powerspy_format()
{
    ll=$(cat "$1" | tail -n 1)
    cols=$(printf "$ll" | sed -e 's/[^[:space:]]\+/a/g' -e 's/[[:space:]]\+//g' | wc -m)
    if [ $cols -lt 6 ]
    then
	warn "$1 has incomplete last line"
    elif [ $cols -eq 6 ]
    then
	if [ -z "$(printf "$ll" | grep -e '^\([[:digit:]]\+\.[[:digit:]]\+[[:space:]]\+\)\{5\}[[:digit:]]\+\.[[:digit:]]\+$')" ]
	then
	    warn "$1 has badly formated last line"
	elif [ -n "$(tail -c 1 "$1")" ]
	then
	     warn "$1 is missing a newline at the end of the file"
	fi
    else
	warn "$1 has too many columns in last line"
    fi
}

# usage: non_empty_file <file>
non_empty_file()
{
    if [ ! -s "$1" ]
    then
	warn "$1 is empty"
    fi
}

# Check that the available measurement files and count the number of
# repetitions.
# usage: check_failed_measurements <measurement dir>
check_failed_measurements()
{
    files=$(printf "%s\n" ${1}/*\.* | sed -e 's%^.\+/\*\.\*$%%' -e ':a;N;$!ba;s/\n/ /g')
    repetitions=0
    while [ -n "$files" ]
    do
	f1=$(printf "%s\n" "$files" | cut -d ' ' -f 1)
	pat=$(printf "%s\n" $f1 | sed -e 's/^\([^_]\+\)\(_.\+\)$/*\2/' -e 's/^\([^_]\+_[[:digit:]]\+\.\).\+$/\1*/')
	measurement=$(filter $pat $files)
	files=$(filter_out $pat $files)
	found=0
	for mfile in $measurement
	do
	    non_empty_file "$mfile"
	    case $(basename $mfile) in
		benchmark_*.csv) found=$((found+1)) ;;
		benchmark_*.log) found=$((found+2)) ;;
		l2ping_*.log) found=$((found+4)) ;;
		powerspy_*.log)
		    powerspy_format "$mfile"
		    found=$((found+8)) ;;
		kernel_*.log) found=$((found+16)) ;;
		*) warn "unknown measurement file '$mfile'"
	    esac
	done

	repetition=$(printf "%s\n" $(basename $mfile) | sed -e 's/^[^_]\+_\([[:digit:]]\+\)\..\+$/\1/')
	if [ $found -lt 16 ]
	then
	    fail "kernel log is missing for measurement '$(dirname $f1)' repetition $repetition"
	fi
	# NOTE: benchmark log and benchmark CSV might not be available if the
	# system failed during the benchmark. In that case powerspy and l2ping
	# logs are not very useful. For this reason only the kernel log is
	# mandatory.

	repetitions=$((repetitions+1))
    done

    printf "$repetitions\n"
}

# Check that all measurement files are availble and count the number of
# repetitions.
# usage: check_regular_measurements <measurement dir>
check_regular_measurements()
{
    files=$(printf "%s\n" ${1}/*\.* | sed -e 's%^.\+/\*\.\*$%%' -e ':a;N;$!ba;s/\n/ /g')
    repetitions=0
    while [ -n "$files" ]
    do
	f1=$(printf "%s\n" "$files" | cut -d ' ' -f 1)
	pat=$(printf "%s\n" $f1 | sed -e 's/^\([^_]\+\)\(_.\+\)$/*\2/' -e 's/^\([^_]\+_[[:digit:]]\+\.\).\+$/\1*/')
	measurement=$(filter $pat $files)
	files=$(filter_out $pat $files)
	found=0
	for mfile in $measurement
	do
	    non_empty_file "$mfile"
	    case $(basename $mfile) in
		benchmark_*.csv) found=$((found+1)) ;;
		benchmark_*.log) found=$((found+2)) ;;
		l2ping_*.log) found=$((found+4)) ;;
		powerspy_*.log)
		    powerspy_format "$mfile"
		    found=$((found+8)) ;;
		*) warn "unknown measurement file '$mfile'"
	    esac
	done

	repetition=$(printf "%s\n" $(basename $mfile) | sed -e 's/^[^_]\+_\([[:digit:]]\+\)\..\+$/\1/')
	if [ $found -lt 8 ]
	then
	    fail "PowerSpy2 log is missing for measurement '$(dirname $f1)' repetition $repetition"
	elif [ $found -lt 12 ]
	then
	    fail "l2ping log is missing for measurement '$(dirname $f1)' repetition $repetition"
	elif [ $found -lt 14 ]
	then
	    fail "benchmark log is missing for measurement '$(dirname $f1)' repetition $repetition"
	elif [ $found -lt 15 ]
	then
	    fail "benchmark CSV is missing for measurement '$(dirname $f1)' repetition $repetition"
	fi

	repetitions=$((repetitions+1))
    done

    printf "$repetitions\n"
}

# Identify if we have baseline measurements, regular measurements or failed
# measurements.
# usage: identify_measurements <dir> <baseline>
# STDOUT: dir
identify_measurements()
{
    # Distinguish between the following cases:
    # 1) check for 10 valid regular measurements (i.e., baseline $2=1)
    # 2) check for 10 valid possibly regular measurements and failed measurements
    # 3) check for at least one valid regular measurement
    repetitions=$(check_regular_measurements "$1")
 
    printf "$1\n"

    if [ $repetitions -eq 0 ] && [ ! -d "${1}/failures" ]
    then
	fail "no files for measurement '$1'"
    elif [ $repetitions -lt 10 ] && [ $2 -eq 1 ]
    then
	warn "measurement '$1' is missing $((10-$repetitions)) regular repetitions"
    elif [ $repetitions -lt 10 ] && [ -d "${1}/failures" ]
    then
	fail_rep=$(check_failed_measurements "${1}/failures")
	repetitions=$((repetitions+fail_rep))
	if [ $repetitions -lt 10 ]
	then
	    warn "measurement '$1' is missing $((10-$repetitions)) repetitions"
	fi
    fi
}

# Not POSIX compliant find option 'maxdepth': find . -maxdepth 1 -type d
devices=$(ls -d "$DATADIR"/*/ 2>/dev/null)
check_directories $devices
for device in $devices
do
    case $(basename "$device") in
	[34]B | 3B+ ) ;;
	*) fail "invalid device '$(basename "$device")' found"
	   exit 1
    esac

    frequencies=$(ls -d ${device}*/ 2>/dev/null)
    check_directories $frequencies
    for f in $frequencies
    do
	temp=${f#$device}
	case ${temp%%/*} in
	    f900) ;;
	    f1[0245]00) ;;
	    *) fail "invalid frequency '${temp%%/*}' found"
	esac

	voltages=$(ls -d ${f}*/ 2>/dev/null)
	check_directories $voltages
	for dU in $voltages
	do
	    baseline=0
	    temp=${dU##$f}
	    case ${temp%/*} in
		dU0) baseline=1 ;;
		dU-50) ;;
		dU-[27]5) ;;
		dU-[123][05]0) ;;
		dU-[123][27]5) ;;
		dU-400) ;;
		*) fail "invalid voltage '${temp%/*}' found"
	    esac

	    temperatures=$(ls -d ${dU}*/ 2>/dev/null | sed -e 's%/[[:space:]]% %g' -e 's%/$%%')
	    check_directories $temperatures
	    for T in $temperatures
	    do
		temp=${T##${dU}T}
		# NOTE: apparently the Broadcom SoCs qualified temperature range
		# is between -40°C to +85°C. The upper limit can be empirically
		# confirmed by the firmware behavior.
		if [ $temp -lt 0 ] || [ 85 -lt $temp ]
		then
		    fail "temperature '$temp°C' out of range"
		fi

		# Soft limit (3B+ only)
		# NOTE: the soft limit is only applicable between 60-80°C.
		if [ "x$(basename "$device")" = "x3B+" ] && [ 60 -le $temp ] && [ $temp -le 80 ]
		then
		    softlimits=$(ls -d ${T}/* 2>/dev/null)
		    check_directories $softlimits
		    for SL in $softlimits
		    do
			identify_measurements "$SL" $baseline
		    done
		else
		    identify_measurements "$T" $baseline
		fi
	    done

	    # File naming convention:
	    # The files generated during a measurement follow the following
	    # naming convention:
	    #   <software>_<number>.<suffix>
	    #   software   the software that produced the log
	    #   number     a sequence number to distinguish repeated
	    #              measurements
	    #   suffix     is either 'csv' or 'log'
	    
	    baseline=0
	done
    done
done
