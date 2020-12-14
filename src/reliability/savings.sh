#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# Debug
#set -x

LC_ALL=C
export LC_ALL

usage()
{
    printf "Energy savings computation\n"
    printf "usage: $0 base_dir under_dir\n"
}

. ../error.sh

if [ $# -ne 2 ]
then
    usage
    fail "main" "invalid number of arguments"
    exit 1
fi

[ ! -s "$1"averages.csv ] && fail "main" "file ${1}averages.csv does not exist"
[ ! -s "$2"averages.csv ] && fail "main" "file ${2}averages.csv does not exist"

while read base_line
do
    stressor=${base_line%%,*}
    under_line=$(grep -e ^$stressor, "$2"averages.csv)
    [ $? -eq 1 ] && warn "main" "stressor $stressor not available in ${2}averages.csv" && continue
    average=$(printf "$base_line\n" | cut -d , -f 4-5 | sed -e '/,$/d' -e 's%^\([^,]\+\),\([^,]\+\)$%\2/\1%')
    base_ETR=$(printf "scale=16; $average\n" | bc)
    base_E=$(printf "$base_line\n" | cut -d , -f 2)
    average=$(printf "$under_line\n" | cut -d , -f 4-5 | sed -e '/,$/d' -e 's%^\([^,]\+\),\([^,]\+\)$%\2/\1%')
    under_ETR=$(printf "scale=16; $average\n" | bc)
    under_E=$(printf "$under_line\n" | cut -d , -f 2)
    if [ "x$base_E" = "x0" ] || [ "x$base_E" = "x0.00" ]
    then
	E_ratio="n/a"
    else
	E_ratio=$(printf "scale=2; $under_E/$base_E\n" | bc)
    fi
    if [ "x$base_ETR" = "x0" ] || [ "x$base_ETR" = "x0.00" ]
    then
	ETR_ratio="n/a"
    else
	ETR_ratio=$(printf "scale=2; $under_ETR/$base_ETR\n" | bc)
    fi
    printf "$stressor,$E_ratio,$ETR_ratio\n"
done <"$1"averages.csv
