#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020-2021 Christian Göttel

# Debug
#set -x

LC_ALL=C
export LC_ALL

readonly DATADIR="../../data/guardband"

# usage: var val...
append()
{
    var=$1
    shift
    eval "$var=\"\$$var $*\""
}

# usage: parse_erroneous_measurements dir
parse_erroneous_measurements()
{
    i=1
    n=0
    # NOTE: increase the limit if there are more files in the error directory
    while [ $i -lt 100 ]
    do
	ls "$1"/*_${i}.csv >/dev/null 2>&1
	if [ $? -eq 0 ]
	then
	    n=$((n+1))
	    printf "csv='${1}/*_${i}.csv'\n"
	else
	    ls "$1"*_${i}.log >/dev/null 2>&1
	    [ $? -eq 0 ] && n=$((n+1)) && printf "log='${1}/*_${i}.log'\n"
	fi
	i=$((i+1))
    done
    printf "err: n=$n\n"
}

# usage: parse_failed_measurements dir
# STDOUT: number of failed measurements
# STDERR: debug output
parse_failed_measurements()
{
    n=0
    for log in "$1"/kernel_*.log
    do
	printf "csv='$log'\n" >&2
	n=$((n+1))
    done
    printf "fai: n=$n\n" >&2
    printf "$n\n"
}

# usage: parse_regular_measurements dir temperature
# STDOUT: a tripple with the average temerature and voltage as well as the
#         number of regular measurements
# STDERR: debug output
parse_regular_measurements()
{
    N=0
    Tavg="${2}.0"
    Vavg="nan"
    # First test if there is a regular measurement
    ls "$1"benchmark_*.csv >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
	for csv in "$1"benchmark_*.csv
	do
	    printf "csv='$csv'\n" >&2
	    temperatures="${temperatures}
$(cut -d , -f 22 "$csv")"
	    voltages="${voltages}
$(cut -d , -f 21 "$csv")"
	    N=$((N+1))
	done
	Tout=$(printf "$temperatures\n" | sed -e '/^$/d' | ../stats.m cln)
	Vout=$(printf "$voltages\n" | sed -e '/^$/d' | ../stats.m cln)
	outliers=$(printf "$Tout\n$Vout\n" | sed -e '/^$/d' | sort -bdu | sed -e 's/^\([[:digit:]]\+\)$/\1d/g' | sed -e ':a;N;$!ba;s/\n/;/g' | sed -e 's/^/-e /')
	temperatures=$(printf "$temperatures\n" | sed -e '/^$/d' $outliers)
	voltages=$(printf "$voltages\n" | sed -e '/^$/d' $outliers)
	n=$(printf "$temperatures\n" | wc -l)
	rv=$(printf "$temperatures\n" | ../stats.m sta 1)
	Tavg=${rv%%,*}
	Tstd=${rv##*,}
	rv=$(printf "$voltages\n" | ../stats.m sta 4)
	Vavg=${rv%%,*}
	Vstd=${rv##*,}
	printf "reg: " >&2
	printf "T_avg=$Tavg\t" >&2
	printf "T_std=$Tstd\t" >&2
	printf "V_avg=$Vavg\t" >&2
	printf "V_std=$Vstd\t" >&2
	printf "n=$n\n" >&2
    fi
    # Append first five elements of the point tuple. The sixth element
    # (percentage) is appended in the calling function generate_csv().
    # Print a tuple with the average temperature, the temperature standard
    # deviation, the average voltage, the voltage standard deviation and the
    # number of regular measurements in the specified directory.
    printf "$Tavg,$Tstd,$Vavg,$Vstd,$N\n"
}

# usage: print_points model
# ENVIRONMENT: changes the value of the global variable DU
print_points()
{
    V=0
    while [ $V -ge -400 ]
    do
	DU="$(printf "dU$V\n" | tr '-' 'n')"
	if [ "x$1" = "x3B+" ]
	then
	    eval "[ -n \"\$$DU\" ] && printf \"$DU=\$$DU\$${DU}SL60\n$DU=\$$DU\$${DU}SL70\n\""
	    unset $DU ${DU}SL60 ${DU}SL70
	else
	    eval "[ -n \"\$$DU\" ] && printf \"$DU=\$$DU\n\""
	    unset $DU
	fi
	V=$((V-25))
    done
}

# usage: generate_csv dir temperature
# ENVIRONMENT: append to the global variable DU
generate_csv()
{
    nfail=0
    ret=$(parse_regular_measurements "$1" $2)
    nreg=${ret##*,}
    [ -d "${1}failures" ] && nfail=$(parse_failed_measurements "${1}failures")
    [ -d "${1}errors" ] && parse_erroneous_measurements "${1}errors"
    pct=$(printf "scale=2; $nreg/($nreg+$nfail)\n" | bc)
    # Append the third element closing the tuple.
    append $DU "(${ret%,*},$pct)"
    printf "%%=$pct\n"
}

# usage: traverse_soft_limit dir temperature
# ENVIRONMENT: changes the value of the global variable DU
traverse_soft_limit()
{
    for soft_limit in $(ls -d "$1"*/ 2>/dev/null)
    do
	sl=$(printf "$soft_limit\n" | sed -e 's/^.\+\(SL[[:digit:]]\+\).*/\1/')
	DU="${DU%SL*}$sl"
	generate_csv "$soft_limit" $2
	eval "printf \"$DU=\$$DU\n\""
    done
}

# usage: traverse_measurements dir
# ENVIRONMENT: changes the value of the global variable DU
traverse_measurements()
{
    for model in $(ls -d "$1"/*/ 2>/dev/null)
    do
	printf "$model\n"
	#m=$(printf "$temperature\n" | sed -e 's%^.\+guardband/\([+[:alnum:]]\+\)/.\+$%\1%')
	m="${model%/}"
	m="${m##*/}"
	for frequency in $(ls -d "$model"*/ 2>/dev/null)
	do
	    printf "$frequency\n"
	    # The overvoltage has to be traversed in descending order
	    #volts=0
	    #while [ -d "${frequency}"dU$volts ]
	    for overvoltage in $(ls -d "$frequency"*/ 2>/dev/null)
	    do
		#DU="$(printf "dU$volts\n" | sed -e 's/-/n/')"
		DU="${overvoltage%/}"
		DU="$(printf "${DU##*/}" | tr '-' 'n')"
		#for temperature in $(ls -d "${frequency}"dU${volts}/*/ 2>/dev/null)
		for temperature in $(ls -d "$overvoltage"*/ 2>/dev/null)
		do
		    T=$(printf "$temperature\n" | sed -e 's/^.\+T\([[:digit:]]\+\).*$/\1/')
		    # The Raspberry Pi 3B+ has a soft limit starting at 60°C and
		    # needs an additional directory level. The first temperature
		    # to include this addtional directory level is 59°C.
		    if [ "x$m" = "x3B+" ] && [ $T -ge 59 ]
		    then
			traverse_soft_limit "$temperature" $T
		    else
			generate_csv "$temperature" $T
		    fi
		done
		#volts=$((volts-25))
	    done
	    print_points $m
        done
    done
}

usage()
{
    printf "Guardband plot generator\n"
    printf "usage: $0\n"
}

. ../error.sh

if [ $# -ne 0 ]
then
    usage
    fail "main" "invalid number of arguments"
    exit 1
fi

[ ! -d "$DATADIR" ] && fail "main" "'$DATADIR' is not a directory"

traverse_measurements "$DATADIR"
[ $? -ne 0 ] && fail "traverse_measurements" "could not find ciritcal region"
# plot()
