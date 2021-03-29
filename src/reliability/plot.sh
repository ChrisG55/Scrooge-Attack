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

# Compute the results for one measurement.
# usage: compute_measurement_results
# ENVIRONMENT:
#   LOG  read stress-ng log file path
# STDERR:
#   The standard error shall be used only for diagnostic messages.
# STDOUT:
#   The standard output shall be a comma separated list of energy and duration.
#   The energy field will contain n/a, if the PowerSpy log file is not available.
# RETURN VALUE:
#   0 if successful
#   1 if PowerSpy log file is not available
compute_measurement_results()
{
    tmpE=/tmp/energy.csv
    # Get UNIX timestamp
    pslog="${LOG%/*}/powerspy_${LOG##*_}"
    pscsv="${pslog%log}csv"
    [ ! -s "$pslog" ] && fail "compute_measurement_results" "$pslog does not exist"
    [ ! -s "$pscsv" ] && ../powerspy_log2csv.sh "$pslog"
    # tsps: timestamp in seconds in PowerSpy log
    # tst0: timestamp in seconds at 00:00:00
    # NOTE: timestamps of measurements done at midnight are fixed later
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
    awk -v ts=$tst0 'BEGIN { a=0 }; /4 stressors started/ { split($2, ta, ":"); for (i in ta) { sub("^0", "", ta[i]) }; getline; l=length($5)-11; s=substr($5, 11, l); if (a == 0) a=1 }; /starting stressors/ { if (a == 1) { split($2, to, ":"); for (i in to) { sub("^0", "", to[i]) }; printf("%s,%.2f,%.2f\n", s, ts + ta[1] * 3600 + ta[2] * 60 + ta[3], ts + to[1] * 3600 + to[2] * 60 + to[3]) } }; /run completed in/ { split($2, to, ":"); for (i in to) { sub("^0", "", to[i]) }; printf("%s,%.2f,%.2f\n", s, ts + ta[1] * 3600 + ta[2] * 60 + ta[3], ts + to[1] * 3600 + to[2] * 60 + to[3]) }' "$LOG" >$tmpE
    throughput=$(awk 'BEGIN { OFS=","; a=0 }; /run completed in/ { getline; getline; getline; a=1 }; /debug/ { a=0 }; /run time/ { a=0 }; { if (a == 1) { print $5, $6, $7, $8, $9, $10, $11 } }' "$LOG")
    stressor_list=$(grep -e 'child died' -e 'out of memory at' "$LOG" | head -n 10 | cut -d ' ' -f 5 | sed -e 's/^stress-ng-\([^:]\+\):$/\1/' | sort -u -d | sed -e ':a;N;$!ba;s/\n/ /g')
    strezzor_list="brk hdd seek"
    while read line
    do
	stressor=${line%%,*}
	is_in $stressor $stressor_list && { info "compute_measurement_results" "stressor $stressor had an issue and is skipped"; continue; }
	is_in $stressor $strezzor_list && { info "compute_measurement_results" "stressor $stressor is force skipped"; continue; }
	printf "$stressor:\n" >&2
	op=$(printf "$throughput\n" | grep -e ^$stressor, | cut -d , -f 2)
	[ -z "$op" ] && op="n/a"
	opps=$(printf "$throughput\n" | grep -e ^$stressor, | cut -d , -f 6)
	[ -z "$opps" ] && opps="n/a"
	if [ ! -s "$pslog" ]
	then
	    printf "$stressor,n/a,$op,$opps\n"
	    warn "compute_measurement_results" "$pslog does not exist"
	    continue
	fi
	# NOTE: fixing timestamps of measurements done at midnight
	tsfirst=$(printf "$line\n" | cut -d , -f 2)
	tslast=${line##*,}
	# FIXME: if the machine operates in CEST timezone 3600 seconds have to
	# be substracted from the timestamps!
	ts=$(awk -v tsps=$tsps -v tsfirst=$tsfirst -v tslast=$tslast 'BEGIN { if ((tsfirst < tsps) && (tslast < tsps)) { tsfirst+=86400; tslast+=86400 }; if (tslast - tsfirst < 0) tslast+=86400; printf("%.2f %.2f\n", tsfirst, tslast) }')
	../powerspy_extractor.m "$pscsv" "$PSTMP" $ts
	E=$(../powerspy_p2E.m "$PSTMP" | sed -e 's/^ans =[[:space:]]\+\([[:digit:]]\+\)\(\.[[:digit:]]\+\)\{0,1\}$/\1\2/')
	printf "$stressor,$E,$op,$opps\n"
	rm -f "$PSTMP"
    done <$tmpE
    rm -f $tmpE
    n=$((n+1))
}

# usage: parse_regular_measurements
# ENVIRONMENT:
#   DIR   read the current work directory
#   LOG   set stress-ng log file path
# FILES:
#   Results are written into dir/results.csv. The file is created if it does not
#   exist.
# STDERR:
#   The standard error shall be used only for diagnostic messages.
# RETURN VALUE:
#   0 if successful
#   1 if a new result was successfully added
parse_regular_measurements()
{
    new_result=0
    n=0
    ls "$DIR"stress-ng_*.log >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
	for LOG in "$DIR"stress-ng_*.log
	do
	    measurement_id=$(printf "$LOG" | sed -e 's/^[^_]\+_\([[:digit:]]\+\)\.log$/\1/')
	    [ -s "$DIR"results.csv ] && grep -q -e ^$measurement_id, "$DIR"results.csv
	    rc=$?
	    if [ $rc -eq 1 ]
	    then
		# CSV format:
		# 1) measurement ID
		# 2) measurement exit status (0 = success)
		# 3) stressor
		# 4) energy in joule [J]
		# 5) number of operations
		# 6) throughput [op/s]
		compute_measurement_results | while read line
		do
		    printf "$measurement_id,0,$line\n" >>"$DIR"results.csv
		done
		new_result=1
	    elif [ $rc -gt 1 ]
	    then
		fail "parse_regular_measurements" "An error occured while searching \"$DIR\"results.csv for measurement id $measurement_id"
	    fi
	done
    fi
    return $new_result
}

# usage: generate_averages dir
# ENVIRONMENT:
#   DIR   read the current work directory
# STDERR:
#   The standard error shall be used only for diagnostic messages.
# RETURN VALUE:
#   0 if successful
#   1 if dir/results.csv is not available
#   2 if no average can be computed from dir/results.csv because of incomplete
#     data
generate_averages()
{
    #ret=$(parse_regular_measurements)
    parse_regular_measurements
    recompute_average=$?
    if [ ! -s "$DIR"results.csv ]
    then
	info "generate_averages" "${DIR}results.csv could not be generated"
	return 1
    fi
    stressor_list=$(cut -d , -f 3 "$DIR"results.csv | sort -u -d)
    for stressor in $stressor_list
    do
	[ -s "$DIR"averages.csv ] && grep -q -e ^$stressor, "$DIR"averages.csv
	if [ $? -eq 1 ] || [ $recompute_average -eq 1 ]
	then
	    results=$(grep -e ,$stressor, "$DIR"results.csv | sed -e '/,n\/a/d')
	    if [ -z "$results" ]
	    then
		info "generate_averages" "no average for stressor $stressor because of incomplete data in ${DIR}results.csv"
		continue
	    fi
	    n=$(printf "$results\n" | wc -l)
	    SE=$(printf "$results\n" | cut -d , -f 4 | sed -e ':a;N;$!ba;s/\n/+/g')
	    Eavg=$(printf "scale=6; ($SE)/$n\n" | bc)
	    SO=$(printf "$results\n" | cut -d , -f 5 | sed -e ':a;N;$!ba;s/\n/+/g')
	    Oavg=$(printf "scale=2; ($SO)/$n\n" | bc)
	    SOps=$(printf "$results\n" | cut -d , -f 6 | sed -e ':a;N;$!ba;s/\n/+/g')
	    Opsavg=$(printf "scale=2; ($SOps)/$n\n" | bc)
	    if [ "x$Oavg" = "x0" ] || [ "x$Oavg" = "x0.00" ]
	    then
		Epopavg=$Oavg
	    else
		Epopavg=$(printf "scale=9; $Eavg/$Oavg\n" | bc)
	    fi
	    [ $recompute_average -eq 1 ] && sed -e "/^$stressor,/d" "$DIR"averages.csv >/tmp/averages.csv && mv /tmp/averages.csv "$DIR"averages.csv
	    # CSV format:
	    # 1) stressor
	    # 2) average consumed energy in joule [J]
	    # 3) average number of operations [op]
	    # 4) average throughput in operations per second [op/s]
	    # 5) average consumed energy per operation [J/op]
	    printf "$stressor,$Eavg,$Oavg,$Opsavg,$Epopavg\n" >>"$DIR"averages.csv
	fi
    done
}

# usage: traverse_measurements
# ENVIRONMENT:
#   DATADIR  read the dataset directory
#   DIR      set the current work directory
# STDERR:
#   The standard error shall be used only for diagnostic messages.
traverse_measurements()
{
    for mdir in $(ls -d "$DATADIR"/*/ 2>/dev/null)
    do
	#printf "$mdir\n"
	MODEL="${mdir%/}"
	MODEL="${MODEL##*/}"
	for fdir in $(ls -d "$mdir"*/ 2>/dev/null)
	do
	    #printf "$fdir\n"
	    for ovdir in $(ls -d "$fdir"*/ 2>/dev/null)
	    do
		#printf "$ovdir\n"
		for DIR in $(ls -d "$ovdir"*/ 2>/dev/null)
		do
		    printf "$DIR\n"
		    # cooling=$(printf "$DIR\n" | ...)
		    generate_averages
		done
	    done
	done
    done
}

# usage: plot dir_base dir_under
#   dir_base   directory with baseline measurement
#   dir_under  directory with undervolted measurement
plot()
{
    fail "plot" "not yet implemented"
    # grep -e ^atomic, -e ^bigheap, -e ^bsearch, -e ^clock, -e ^cpu, -e ^fork, -e ^futex, -e ^get, -e ^hrtimers, -e ^hsearch, -e ^kcmp, -e ^lsearch, -e ^mergesort, -e ^mq, -e ^msg, -e ^pipe, -e ^poll, -e ^seek, -e ^sigsegv, -e ^urandom, -e ^vm-rw, "$2"averages.csv | cut -d , -f 4-5 | sed -e '/,$/d' -e 's%^\([^,]\+\),\([^,]\+\)$%\2/\1%' | while read line; do printf "scale=16; $line\n" | bc; done)
}

usage()
{
    printf "Reliability plot generator\n"
    printf "usage: $0 [-v]\n"
}

. ../error.sh

if [ $# -gt 1 ]
then
    usage
    fail "main" "invalid number of arguments"
fi

[ "x$1" = "x-v" ] && LOGLEVEL="info"

[ ! -d "$DATADIR" ] && fail "main" "'$DATADIR' is not a directory"

traverse_measurements "$DATADIR"
[ $? -ne 0 ] && fail "traverse_measurements" "failure"
# plot()
# printf "N=$N\n"
