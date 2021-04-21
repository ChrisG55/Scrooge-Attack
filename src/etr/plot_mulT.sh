#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# Debug
#set -x

LC_ALL=C
export LC_ALL

readonly DATADIR="../../data/etr"
readonly PSTMP="/tmp/PowerSpy.csv"

# Compute the results for one measurement.
# usage: compute_measurement_results benchmark_*.csv
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
    Dt=$(cut -d , -f 32 "$1")
    pscsv="${1%/*}/powerspy_${1##*_}"
    pslog="${pscsv%csv}log"
    if [ ! -s "$pslog" ]
    then
	printf "n/a,$Dt\n"
	warn "compute_measurement_results" "$pslog does not exist"
	return 1
    fi
    [ ! -s "$pscsv" ] && ../powerspy_log2csv.sh "$pslog"
    timestamps=$(cut -d , -f 24-25 "$1")
    ../powerspy_extractor.m "$pscsv" "$PSTMP" ${timestamps%%,*} ${timestamps##*,}
    E=$(../powerspy_p2E.m "$PSTMP" | sed -e 's/^.\+ \([[:digit:]]\+\.[[:digit:]]\+\)$/\1/')
    rm -f "$PSTMP"
    printf "$E,$Dt\n"
}

# usage: parse_regular_measurements dir
# FILES:
#   Results are written into dir/results.csv. The file is created if it does not
#   exist.
# RETURN VALUE:
#   0 if successful
#   1 if a new result was successfully added
parse_regular_measurements()
{
    new_result=0
    n=0
    ls "$1"benchmark_*.csv >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
	for csv in "$1"benchmark_*.csv
	do
	    measurement_id=$(printf "$csv" | sed -e 's/^[^_]\+_\([[:digit:]]\+\)\.csv$/\1/')
	    [ -s "$1"results.csv ] && grep -q -e ^$measurement_id, "$1"results.csv
	    if [ $? -eq 1 ]
	    then
		# CSV format:
		# 1) measurement ID
		# 2) measurement exit status (0 = success)
		# 3) energy in joule [J]
		# 4) duration in seconds [s]
		printf "$measurement_id,0,$(compute_measurement_results "$csv")\n" >>"$1"results.csv
		new_result=1
	    fi
	done
    fi
    return $new_result
}

# usage: generate_average_results dir
# STDERR:
#   The standard error shall be used only for diagnostic messages.
# RETURN VALUE:
#   0 if successful
#   1 if dir/results.csv is not available
#   2 if no average can be computed from dir/results.csv because of incomplete
#     data
generate_average_results()
{
    #ret=$(parse_regular_measurements "$1")
    parse_regular_measurements "$1"
    recompute_average=$?
    if [ ! -s "$1"results.csv ]
    then
	info "generate_average_results" "${1}results.csv is not available"
	return 1
    fi
    results=$(grep -v -e ',n/a' "$1"results.csv)
    if [ $? -eq 1 ]
    then
	info "generate_average_results" "no average because of incomplete data in ${1}results.csv"
	return 2
    fi
    # The frequency is used as identifier in the averaged results
    f=$(printf "$1\n" | sed -e 's%^.\+/f\([[:digit:]]\+\)/$%\1%')
    [ -s "$1"../averages.csv ] && grep -q -e ^$f, "$1"../averages.csv
    if [ $? -eq 1 ] || [ $recompute_average -eq 1 ]
    then
	SE=$(printf "$results\n" | cut -d , -f 3 | sed -e ':a;N;$!ba;s/\n/+/g')
	SDt=$(printf "$results\n" | cut -d , -f 4 | sed -e ':a;N;$!ba;s/\n/+/g')
	n=$(printf "$results\n" | wc -l)
	Epopavg=$(printf "scale=9; ($SE)/$n/1000000000\n" | bc)
	opptavg=$(printf "scale=3; 1000000000/($SDt)*$n\n" | bc)
	[ $recompute_average -eq 1 ] && sed -e "/^$f,/d" "$1"../averages.csv >"$1"../averages.csv
	# CSV format:
	# 1) CPU frequency in MHz
	# 2) average throughput in op/s
	# 3) average energy per operation in J/op
	printf "$f,$opptavg,$Epopavg\n" >>"$1"../averages.csv
    fi
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
		generate_average_results "$frequency"
	    done
	done
    done
}

usage()
{
    printf "ETR plot generator\n"
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
