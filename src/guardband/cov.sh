#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Christian Göttel

# Debug
#set -x

LC_ALL=C
export LC_ALL

readonly DATADIR="../../data/guardband"

# usage: parse_regular_measurements dir temperature
# STDOUT: a tripple with the average temerature and voltage as well as the
#         number of regular measurements
# STDERR: debug output
parse_regular_measurements()
{
    # First test if there is a regular measurement
    ls "$1"benchmark_*.csv >/dev/null 2>&1
    [ $? -ne 0 ] && fail "parse_regular_measurements" "no regular measurements found" && exit 1

    printf "$1\n" >&2
    for csv in "$1"benchmark_*.csv
    do
	data="${data}
$(cut -d , -f 21,22 "$csv")"
    done
    Tout=$(printf "$data\n" | sed -e '/^$/d' | cut -d , -f 2 | ../stats.m cln)
    Vout=$(printf "$data\n" | sed -e '/^$/d' | cut -d , -f 1 | ../stats.m cln)
    outliers=$(printf "$Tout\n$Vout\n" | sed -e '/^$/d' | sort -bdu | sed -e 's/^\([[:digit:]]\+\)$/\1d/g' | sed -e ':a;N;$!ba;s/\n/;/g' | sed -e 's/^/-e /')
    printf "$data\n" | sed -e '/^$/d' $outliers
}

# usage: compute_covariance dir1 dir2
# ENVIRONMENT: changes the value of the global variable DU
compute_covariance()
{
    printf "data1: "
    data1=$(parse_regular_measurements "$DATADIR/$1" $(printf "$1\n" | sed -e 's/^.*T\([[:digit:]]\+\).*$/\1/'))
    printf "$data1\n"
    printf "data2: "
    data2=$(parse_regular_measurements "$DATADIR/$2" $(printf "$2\n" | sed -e 's/^.*T\([[:digit:]]\+\).*$/\1/'))
    printf "$data2\n"
    mkfifo /tmp/cov_data1 /tmp/cov_data2
    printf "$data1\n" | nl -s , | sed -e 's/^[[:space:]]\+//' >/tmp/cov_data1 &
    printf "$data2\n" | nl -s , | sed -e 's/^[[:space:]]\+//' >/tmp/cov_data2 &
    printf "covT="
    join -t , -a 1 -a 2 -e 'nan' -o 1.3,2.3 /tmp/cov_data1 /tmp/cov_data2 | ../stats.m cov
    printf "$data1\n" | nl -s , | sed -e 's/^[[:space:]]\+//' >/tmp/cov_data1 &
    printf "$data2\n" | nl -s , | sed -e 's/^[[:space:]]\+//' >/tmp/cov_data2 &
    printf "covV="
    join -t , -a 1 -a 2 -e 'nan' -o 1.2,2.2 /tmp/cov_data1 /tmp/cov_data2 | ../stats.m cov
    rm -f /tmp/cov_data1 /tmp/cov_data2
}

usage()
{
    printf "Guardband sample covariance\n"
    printf "Computes the covariance for the temperature and voltage of two datasets\n"
    printf "usage: $0 dir1 dir2\n"
}

. ../error.sh

if [ $# -ne 2 ]
then
    usage
    fail "main" "invalid number of arguments"
    exit 1
fi

[ ! -d "$DATADIR" ] && fail "main" "'$DATADIR' is not a directory"
compute_covariance "$1" "$2"
