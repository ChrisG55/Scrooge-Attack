#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Christian Göttel

# Debug
#set -x

LC_ALL=C
export LC_ALL

readonly DATADIR="../../data/param"

# usage: generate_results
# ENVIRONMENT:
#   DIR  reads the current measurement directory
# FILES:
#   Results are written into dir/results.csv. The file is created if it does not
#   exist.
# RETURN VALUE:
#   0 if successful
#   1 if a new result was successfully added
generate_results()
{
    ls "$DIR"param_*.log >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
	for log in "$DIR"param_*.log
	do
	    measurement_id=$(printf "$log" | sed -e 's/^.\+_\([[:digit:]]\+\)\.log$/\1/')
	    [ -s "$DIR"results.csv ] && grep -q -e ^$measurement_id, "$DIR"results.csv
	    if [ $? -eq 1 ]
	    then
		# CSV format:
		# 1) Measurement ID
		# 2) UNIX timestamp [s]
		# 3) temperature [°C]
		if [ ! -s "$log" ]
		then
		    printf "$measurement_id,0,35\n" >>"$DIR"results.csv
		    continue
		fi
		csv="${log%log}csv"
		[ ! -s "$csv" ] && sed -e "N;s/temp=//;s/'C//;s/\n/,/" "$log" >"$csv"
		tailoffset=-1
		tail -n 1 "$csv" | grep -e , >/dev/null 2>&1
		[ $? -eq 1 ] && tailoffset=-2
		tstart=$(head -n 1 "$csv" | cut -d , -f 1)
		tstop=$(tail -n $tailoffset "$csv" | head -n 1 | cut -d , -f 1)
		T=$(tail -n $tailoffset "$csv" | head -n 1 | cut -d , -f 2)
		dt=$(printf "$tstop-$tstart\n" | bc)
		printf "$measurement_id,$dt,$T\n" >>"$DIR"results.csv
	    fi
	done
    fi
}

# Traverse measurement directory hierarchy.
# ENVIRONMENT:
#   DIR  sets the current measurement directory
traverse_measurements()
{
    for model_dir in $(ls -d "$1"/*/ 2>/dev/null)
    do
	#printf "$model_dir\n"
	for DIR in $(ls -d "$model_dir"*/ 2>/dev/null)
	do
	    printf "$DIR\n"
	    generate_results
	done
    done
}

usage()
{
    printf "Parameter plot generator\n"
    printf "usage: $0 [-v]\n"
}

. ../error.sh

if [ $# -gt 1 ]
then
    usage
    fail "main" "invalid number of arguments"
    exit 1
fi

[ "x$1" = "x-v" ] && LOGLEVEL="info"

[ ! -d "$DATADIR" ] && fail "main" "'$DATADIR' is not a directory"

traverse_measurements "$DATADIR"
[ $? -ne 0 ] && fail "traverse_measurements" "failure"
# plot()
