#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# Debug
#set -x

LC_ALL=C
export LC_ALL

readonly DATADIR="../../data/etr"
readonly PSTMP="/tmp/PowerSpy.csv"

# usage: parse_regular_measurements dir
# STDOUT: number of regular measurements
parse_regular_measurements()
{
    n=0
    ls "$1"benchmark_*.csv >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
	Eavg=0
	tavg=0
	for csv in "$1"benchmark_*.csv
	do
	    # Get UNIX timestamp
	    pscsv="${1}powerspy_${csv##*_}"
	    pslog="${pscsv%csv}log"
	    [ ! -s "$pslog" ] && fail "parse_regular_measurements" "$pslog does not exist"
	    [ ! -s "$pscsv" ] && ../powerspy_log2csv.sh "$pslog"
	    ts=$(cut -d , -f 24-25 "$csv")
	    ../powerspy_extractor.m "$pscsv" "$PSTMP" ${ts%%,*} ${ts##*,}
	    E=$(../powerspy_p2E.m "$PSTMP" | sed -e 's/^.\+ \([[:digit:]]\+\.[[:digit:]]\+\)$/\1/')
	    t=$(cut -d , -f 32 "$csv")
	    Esum="$Eavg+$E"
	    tsum="$tavg+$t"
	    rm -f "$PSTMP"
	    n=$((n+1))
	done
	Eopavg=$(printf "scale=9; ($Esum)/$n/1000000000\n" | bc)
	tputavg=$(printf "scale=3; 1000000000/($tsum)*$n\n" | bc)
	printf "$tputavg,$Eopavg\n"
    fi
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
	for overvoltage in $(ls -d "$model"*/ 2>/dev/null)
	do
	    #printf "$overvoltage\n"
	    for frequency in $(ls -d "$overvoltage"*/ 2>/dev/null)
	    do
		printf "$frequency\n"
		generate_csv "$frequency"
	    done
	done
    done
}

usage()
{
    printf "ETR plot generator\n"
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
