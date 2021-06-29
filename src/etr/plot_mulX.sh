#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Christian Göttel

# Debug
#set -x

LC_ALL=C
export LC_ALL

readonly TALPHA5="12.7062,4.3027,3.1824,2.7764,2.5706,2.4469,2.3646,2.3060,2.2622,2.2231,2.2010,2.1788,2.1604,2.1448,2.1314,2.1199,2.1098,2.1009,2.0930,2.0860,2.0796,2.0736,2.0687,2.0639,2.0595,2.0555,2.0518,2.0484,2.0452,2.0423,2.0395"
readonly DATADIR="../../data/etr"
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
	Eout=$(printf "$results\n" | cut -d , -f 5 | ../stats.m cln)
	Opsout=$(printf "$results\n" | cut -d , -f 7 | ../stats.m cln)
	outliers=$(printf "$Eout\n$Opsout\n" | sed -e '/^$/d' | sort -bdu | sed -e 's/^\([[:digit:]]\+\)$/\1d/g' | sed -e ':a;N;$!ba;s/\n/;/g' | sed -e 's/^/-e /')
	E=$(printf "$results\n" | cut -d , -f 5 | sed -e '/^$/d' $outliers)
	Op=$(printf "$results\n" | head -n 1 | cut -d , -f 6)
	Ops=$(printf "$results\n" | cut -d , -f 7 | sed -e '/^$/d' $outliers)
	n=$(printf "$E\n" | wc -l)
	rv=$(printf "$E\n" | ../stats.m sta 2)
	Eavg=${rv%%,*}
	Estd=${rv##*,}
	rv=$(printf "$Ops\n" | ../stats.m sta 2)
	Opsavg=${rv%%,*}
	Opsstd=${rv##*,}
	Epopavg=$(awk -v E=$Eavg -v O=$Op 'BEGIN { printf("%.11f\n", E/O) }')
	#Epopstd=$(awk -v sE=$Estd -v O=$Op 'BEGIN { printf("%.13f\n", sE/O) }')
	#Epopci=$(awk -v a="$TALPHA5" -v n=$n -v sEpop=$Epopstd 'BEGIN { split(a, z, ","); printf("%.11f\n", z[n-1]*sEpop/sqrt(n)) }')
	ETRavg=$(awk -v Epop=$Epopavg -v Ops=$Opsavg 'BEGIN { printf("%.18f\n", Epop/Ops) }')
	cov=$(printf "$results\n" | sed -e '/^$/d' $outliers | awk 'BEGIN { FS="," }; { printf("%.11f,%.2f\n", $5/$6, $7) }' | ../stats.m cov)
	ETRstd=$(awk -v Epop=$Epopavg -v sEpop=$Epopstd -v O=$Opsavg -v sO=$Opsstd -v sEpO=$cov 'BEGIN { ci = Epop / O * sqrt((sEpop/Epop)^2 + (sO/O)^2 - 2 * sEpO/(Epop*O)); printf("%.22f\n", ci) }')
	ETRci=$(awk -v a="$TALPHA5" -v n=$n -v sETR=$ETRstd 'BEGIN { split(a, z, ","); printf("%.22f\n", z[n-1]*sETR/sqrt(n)) }')
	Opsci=$(awk -v a="$TALPHA5" -v n=$n -v sOps=$Opsstd 'BEGIN { split(a, z, ","); print z[n-1]*sOps/sqrt(n) }')
	[ -s "$DIR"../averages.csv ] && [ $recompute_average -eq 1 ] && sed -e "/^$f,/d" "$DIR"../averages.csv >/tmp/averages.csv && mv /tmp/averages.csv "$DIR"../averages.csv
	# CSV format:
	# 1) CPU frequency in MHz
	# 2) average throughput in op/s
	# 3) average energy per operation in J/op
	printf "$f,$Opsavg,$Opsci,$ETRavg,$ETRci\n" >>"$DIR"../averages.csv
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
# How to obtain final values, e.g. for 3B:
# join -t , -o 1.1,1.2,1.3,1.4,1.5,2.2,2.3,2.4,2.5 -1 1 -2 1 ../../data/etr2/3B/dU0/averages.csv ../../data/etr2/3B/dU-75/averages.csv | awk -v opscov=113433095302465.765625 'BEGIN { FS="," }; { ops = ($2 + $6) / 2; rETR = $8 / $4; sops = sqrt($3^2+$4^2+2*opscov); sops = sops/2; opsci = 2.4469 * sops / sqrt(7); ETRci = 2.4469 * (rETR * sqrt(($5/$4)^2+($9/$8)^2))/sqrt(7); printf("%d,%.2f,%.2f,%.4f,%f\n", $1, ops, opsci, rETR, ETRci) }'
