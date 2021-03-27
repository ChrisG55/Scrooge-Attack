#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# Debug
#set -x

LC_ALL=C
export LC_ALL

readonly DATADIR=../../data/guardband

# usage: count_failures
# ENVIRONMENT:
#   DIR       directory to work in
#   FAILURES  set number of failed measurements
count_failures()
{
    [ ! -d "$DIR" ] && { FAILURES=0; warn "count_failures" "'$DIR' is not a directory"; }
    FAILURES=$(find "$DIR" -name 'kernel_*\.log' -type f | wc -l)
}

# usage: count_successes
# ENVIRONMENT:
#   DIR        directory to work in
#   SUCCESSES  set number of successful measurements
count_successes()
{
    [ ! -d "$DIR" ] && { SUCCESSES=0; warn "count_failures" "'$DIR' is not a directory"; }
    SUCCESSES=$(find "$DIR" -name 'benchmark_*\.log' -type f | wc -l)
}

# usage: generate_csv
# ENVIRONMENT: 
#   DIR        directory to work in
#   FAILURES   set number of failed measurements
#   SUCCESSES  set number of successful measurements
generate_csv()
{
    count_successes
    DIR="${DIR}failures"
    if [ -d "$DIR" ]
    then
	count_failures
    else
	FAILURES=0
    fi
    printf "SUCCESSES=$SUCCESSES\tFAILURES=$FAILURES\n"
    if [ $SUCCESSES -eq 0 ] && [ $FAILURES -eq 0 ]
    then
        ratio=0
    else
	ratio=$(printf "scale=2; $FAILURES/($SUCCESSES+$FAILURES)\n" | bc)
    fi
    printf "$MODEL,$FREQUENCY,$DU,$TEMPERATURE,$SUCCESSES,$FAILURES,$((SUCCESSES+FAILURES)),$ratio\n" >>failure_ratio.csv
}

# usage: traverse_soft_limit temperature
# ENVIRONMENT:
#   DIR          set the measurement directory for subsequent function calls
#   DU           set the overvoltage level
traverse_soft_limit()
{
    for DIR in $(ls -d "$DIR"*/ 2>/dev/null)
    do
	sl=$(printf "$DIR\n" | sed -e 's/^.\+\(SL[[:digit:]]\+\).*/\1/')
	DU="${DU%SL*}$sl"
	generate_csv "$DIR"
	#eval "printf \"$DU=\$$DU\n\""
    done
}

# usage: traverse_measurements
# ENVIRONMENT:
#   DATADIR      use as base directory
#   DIR          set the measurement directory for subsequent function calls
#   DU           set the overvoltage level
#   FREQUENCY    set the processor frequency
#   MODEL        set the Raspberry Pi model
#   TEMPERATURE  set the package temperature
traverse_measurements()
{
    for mdir in $(ls -d "$DATADIR"/*/ 2>/dev/null)
    do
	printf "$mdir\n"
	MODEL="${mdir%/}"
	MODEL="${MODEL##*/}"
	for fdir in $(ls -d "$mdir"*/ 2>/dev/null)
	do
	    printf "$fdir\n"
	    FREQUENCY=$(printf "$fdir\n" | sed -e 's/^.\+f\([[:digit:]]\+\).*$/\1/')
	    # The overvoltage has to be traversed in descending order
	    for ovdir in $(ls -d "$fdir"*/ 2>/dev/null)
	    do
		printf "$ovdir\n"
		DU="${ovdir%/}"
		DU="$(printf "${DU##*/}" | tr '-' 'n')"
		for DIR in $(ls -d "$ovdir"*/ 2>/dev/null)
		do
		    printf "$DIR\n"
		    TEMPERATURE=$(printf "$DIR\n" | sed -e 's/^.\+T\([[:digit:]]\+\).*$/\1/')
		    # The Raspberry Pi 3B+ has a soft limit starting at 60°C and
		    # needs an additional directory level. The first temperature
		    # to include this addtional directory level is 59°C.
		    if [ "x$MODEL" = "x3B+" ] && [ $TEMPERATURE -ge 59 ]
		    then
			traverse_soft_limit "$DIR" $TEMPERATURE
		    else
			generate_csv "$DIR"
		    fi
		done
	    done
	done
    done
}

usage()
{
    printf "Failure rate generator\n"
    printf "usage: $0\n"
}

. ../error.sh

[ "x$1" = "x-v" ] && LOGLEVEL="info"

[ ! -d "$DATADIR" ] && fail "main" "'$DATADIR' is not a directory"

traverse_measurements
