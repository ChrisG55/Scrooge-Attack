#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Christian Göttel

# Debug
#set -x

LC_ALL=C
export LC_ALL

readonly DATADIR="../../data/etr2"
readonly PSTMP="/tmp/PowerSpy.csv"

# Compute the results for one measurement.
# usage: compute_measurement_results mulX_bench_*.csv
# STDERR:
#   The standard error shall be used only for diagnostic messages.
# STDOUT:
#   The standard output shall be a comma separated list of energy and duration.
#   The energy field will contain n/a, if the PowerSpy log file is not available.
# EXIT STATUS:
#   0 if successful
#   1 if PowerSpy log file is not available
compute_measurement_results()
{
    pscsv="${1%/*}/powerspy_${1##*_}"
    pslog="${pscsv%csv}log"

    measurement=$(awk 'BEGIN {
    	CONVFMT = "%.10g"
    	FS = ","
	OFMT = "%.10g"
	cpuusage = 0
	op = 0
	ops = 0
	tsstart = 0
	tsstop = 9999999999
    }
    {
	if ($1 > tsstart)
	    tsstart = $1
	if ($2 < tsstop)
	    tsstop = $2
	op += $8
	ops += $8 / $9
	cpuusage += $10
    }
    END {
    	print tsstart "," tsstop ",n/a," op "," ops "," cpuusage
    }' "$1")

    if [ ! -s "$pslog" ]
    then
	printf "$measurement\n"
	warn "compute_measurement_results" "$pslog does not exist"
	return 1
    fi
    [ ! -s "$pscsv" ] && ../powerspy_log2csv.sh "$pslog"
    timestamps=$(printf "$measurement\n" | cut -d , -f 1-2)
    ../powerspy_extractor.m "$pscsv" "$PSTMP" ${timestamps%%,*} ${timestamps##*,}
    E=$(../powerspy_p2E.m "$PSTMP" | sed -e 's/^.\+ \([[:digit:]]\+\.[[:digit:]]\+\)$/\1/')
    rm -f "$PSTMP"
    printf "$measurement\n" | sed -e "s%n/a%$E%"
}

# usage: parse_regular_measurements
# ENVIRONMENT:
#   DIR  reads the current measurement directory
# FILES:
#   Results are written into dir/results.csv. The file is created if it does not
#   exist.
# EXIT STATUS:
#   0 if successful
#   1 if a new result was successfully added
parse_regular_measurements()
{
    new_result=0
    n=0
    ls "$DIR"mulX_bench_*.csv >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
	for csv in "$DIR"mulX_bench_*.csv
	do
	    measurement_id=$(printf "$csv" | sed -e 's/^.\+_\([[:digit:]]\+\)\.csv$/\1/')
	    [ -s "$DIR"results.csv ] && grep -q -e ^$measurement_id, "$DIR"results.csv
	    if [ $? -eq 1 ]
	    then
		# CSV format:
		# 1) measurement ID
		# 2) measurement exit status (0 = success)
		# 3) timestamp start [s]
		# 4) timestamp stop [s]
		# 5) energy in joule [J]
		# 6) operations
		# 7) throughput [op/s]
		# 8) CPU usage
		printf "$measurement_id,0,$(compute_measurement_results "$csv")\n" >>"$DIR"results.csv
		new_result=1
	    fi
	done
    fi
    return $new_result
}

# usage: generate_average_results
# STDERR:
#   The standard error shall be used only for diagnostic messages.
# ENVIRONMENT:
#   DIR  reads the current measurement directory
# EXIT STATUS:
#   0 if successful
#   1 if dir/results.csv is not available
#   2 if no average can be computed from dir/results.csv because of incomplete
#     data
generate_average_results()
{
    #ret=$(parse_regular_measurements "$DIR")
    parse_regular_measurements
    recompute_average=$?
    if [ ! -s "$DIR"results.csv ]
    then
	info "generate_average_results" "${DIR}results.csv is not available"
	return 1
    fi
    results=$(grep -v -e ',n/a' "$DIR"results.csv)
    if [ $? -eq 1 ]
    then
	info "generate_average_results" "no average because of incomplete data in ${DIR}results.csv"
	return 2
    fi
    # The frequency is used as identifier in the averaged results
    f=$(printf "$DIR\n" | sed -e 's%^.\+/f\([[:digit:]]\+\)/$%\1%')
    [ -s "$DIR"../averages.csv ] && grep -q -e ^$f, "$DIR"../averages.csv
    if [ $? -eq 1 ] || [ $recompute_average -eq 1 ]
    then
	SE=$(printf "$results\n" | cut -d , -f 3 | sed -e ':a;N;$!ba;s/\n/+/g')
	SDt=$(printf "$results\n" | cut -d , -f 4 | sed -e ':a;N;$!ba;s/\n/+/g')
	n=$(printf "$results\n" | wc -l)
	Epopavg=$(printf "scale=9; ($SE)/$n/1000000000\n" | bc)
	opptavg=$(printf "scale=3; 1000000000/($SDt)*$n\n" | bc)
	[ -s "$DIR"../averages.csv ] && [ $recompute_average -eq 1 ] && sed -e "/^$f,/d" "$DIR"../averages.csv >/tmp/averages.csv && mv /tmp/averages.csv "$DIR"../averages.csv
	# CSV format:
	# 1) CPU frequency in MHz
	# 2) average throughput in op/s
	# 3) average energy per operation in J/op
	printf "$f,$opptavg,$Epopavg\n" >>"$DIR"../averages.csv
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
	for overvoltage_dir in $(ls -d "$model_dir"*/ 2>/dev/null)
	do
	    #printf "$overvoltage_dir\n"
	    for DIR in $(ls -d "$overvoltage_dir"*/ 2>/dev/null)
	    do
		printf "$DIR\n"
		generate_average_results
	    done
	done
    done
}

usage()
{
    printf "ETR2 plot generator\n"
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
