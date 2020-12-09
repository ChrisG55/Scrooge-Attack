#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# Debug
#set -x

LC_ALL=C
export LC_ALL

readonly DATADIR="../../data/reliability"
readonly PSTMP="/tmp/PowerSpy.csv"
N=0

# usage: append var value...
append()
{
    var=$1
    shift
    eval "$var=\"\$$var $*\""
}

# usage: is_in value var...
is_in()
{
    value=$1
    shift
    for var in $*; do
        [ $var = $value ] && return 0
    done
    return 1
}

# usage: parse_regular_measurements dir
# STDOUT: number of regular measurements
parse_regular_measurements()
{
    #printf "%s\n" "$1"stress-ng_*.log
    n=0
    strezzor_list=""
    ls "$1"stress-ng_*.log >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
	for log in "$1"stress-ng_*.log
	do
	    # Get UNIX timestamp
	    pslog="${1}powerspy_${log##*_}"
	    pscsv="${pslog%log}csv"
	    [ ! -s "$pslog" ] && fail "parse_regular_measurements" "$pslog does not exist"
	    [ ! -s "$pscsv" ] && ../powerspy_log2csv.sh "$pslog"
	    # tsps: timestamp in seconds in PowerSpy log
	    # tst0: timestamp in seconds at 00:00:00
	    tsps=$(sed -n -e '2 s/^\([[:digit:]]\+\)\..\+$/\1/p' "$pslog")
	    tst0=$(date -d @$tsps | awk '{ split($4, arr, ":"); for (i in arr) { sub("^0", "", arr[i]) }; print ts - (arr[1] * 3600 + arr[2] * 60 + arr[3]) }' ts=$tsps)
	    # Stressor's start and end times (sed version)
	    # 1) extract the start time and put it in hold space before
	    #    appending to it the stressor's name.
	    # 2) delete all lines up to the first "starting stressor" to avoid
	    #    processed entries before the first stressor.
	    # 3) extract the end time, append it to the hold space, exchange the
	    #    hold space with the pattern space and reorder the fields
	    # 4) extract the end time for the last stressor, append it to the
	    #    hold space, exchange the hold space with the pattern space and
	    #    reorder the fields
	    # 5) delete any other line
	    awk -v ts=$tst0 'BEGIN { a=0 }; /4 stressors started/ { split($2, ta, ":"); for (i in ta) { sub("^0", "", ta[i]) }; getline; l=length($5)-11; s=substr($5, 11, l); if (a == 0) a=1 }; /starting stressors/ { if (a == 1) { split($2, to, ":"); for (i in to) { sub("^0", "", to[i]) }; printf("%s,%.2f,%.2f\n", s, ts + ta[1] * 3600 + ta[2] * 60 + ta[3], ts + to[1] * 3600 + to[2] * 60 + to[3]) } }; /run completed in/ { split($2, to, ":"); for (i in to) { sub("^0", "", to[i]) }; printf("%s,%.2f,%.2f\n", s, ts + ta[1] * 3600 + ta[2] * 60 + ta[3], ts + to[1] * 3600 + to[2] * 60 + to[3]) }' "$log" >/tmp/energy.csv
	    throughput=$(awk 'BEGIN { OFS=","; a=0 }; /run completed in/ { getline; getline; getline; a=1 }; /debug/ { a=0 }; /run time/ { a=0 }; { if (a == 1) { print $5, $6, $7, $8, $9, $10, $11 } }' "$log")
	    while read line
	    do
		stressor=${line%%,*}
		strezzor=$(printf "$line\n" | sed -e 's/^\([-[:alnum:]]\+\),.\+$/\1/;y/-/_/')
		is_in $strezzor $strezzor_list
		[ $? -eq 1 ] && append strezzor_list $strezzor
		printf "$stressor:\n"
		../powerspy_extractor.m "$pscsv" "$PSTMP" $(printf "$line\n" | cut -d , -f 2) ${line##*,}
		E=$(../powerspy_p2E.m "$PSTMP")
		eval "[ -z \"\$${strezzor}E\" ] && ${strezzor}E=0"
		eval "${strezzor}E=\$${strezzor}E+${E##* }"
		eval "[ -z \"\$${strezzor}O\" ] && ${strezzor}O=0"
		eval "${strezzor}O=\$${strezzor}O+$(printf "$throughput\n" | grep -e ^$stressor, | cut -d , -f 2)"
		eval "[ -z \"\$${strezzor}T\" ] && ${strezzor}T=0"
		eval "${strezzor}T=\$${strezzor}T+$(printf "$throughput\n" | grep -e ^$stressor, | cut -d , -f 6)"
		rm -f "$PSTMP"
	    done </tmp/energy.csv
	    rm -f /tmp/energy.csv
	    n=$((n+1))
	done
	N=$((N+n))
	for strezzor in $strezzor_list
	do
	    eval "val=\$${strezzor}E"
	    n=$(printf "$val\n" | sed -e 's/[^+]\+//g' | wc -c)
	    Eavg=$(printf "($val)/($n-1)\n" | bc)
	    eval "val=\$${strezzor}O"
	    n=$(printf "$val\n" | sed -e 's/[^+]\+//g' | wc -c)
	    Oavg=$(printf "($val)/($n-1)\n" | bc)
	    eval "val=\$${strezzor}T"
	    n=$(printf "$val\n" | sed -e 's/[^+]\+//g' | wc -c)
	    Tavg=$(printf "($val)/($n-1)\n" | bc)
	    printf "$strezzor,$Eavg,$Oavg,$Tavg,$(printf "scale=9; $Eavg/$Oavg\n" | bc)\n"
	done
    fi
    #printf "$n\n"
}

# usage: generate_csv dir
generate_csv()
{
    #ret=$(parse_regular_measurements "$1")
    parse_regular_measurements "$1"
}

traverse_measurements()
{
    for model in $(ls -d "$1"/*/ 2>/dev/null)
    do
	#printf "$model\n"
	m="${model%/}"
	m="${m##*/}"
	for frequency in $(ls -d "$model"*/ 2>/dev/null)
	do
	    #printf "$frequency\n"
	    for overvoltage in $(ls -d "$frequency"*/ 2>/dev/null)
	    do
		#printf "$overvoltage\n"
		for cooling in $(ls -d "$overvoltage"*/ 2>/dev/null)
		do
		    printf "$cooling\n"
		    generate_csv "$cooling"
		done
	    done
	done
    done
}

usage()
{
    printf "Reliability plot generator\n"
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
[ $? -ne 0 ] && fail "traverse_measurements" "failure"
# plot()
printf "N=$N\n"
