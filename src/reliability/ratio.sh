#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# Debug
#set -x

LC_ALL=C
export LC_ALL

usage()
{
    printf "ETR ratio computation\n"
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

stressor_list=""

for stressor in bigheap bsearch clock fork futex get hdd heapsort hsearch judy kcmp kill lsearch mergesort mq msg pipe poll qsort seek sigsegv sysfs tmpfs tsearch urandom vm-rw wcs
do
    base_stressor=$(grep -q -e ^$stressor, "$1"averages.csv)
    [ $? -eq 1 ] && warn "main" "stressor $stressor not available in ${1}averages.csv" && continue
    under_stressor=$(grep -q -e ^$stressor, "$2"averages.csv)
    [ $? -eq 1 ] && warn "main" "stressor $stressor not available in ${2}averages.csv" && continue
    line=$(grep -e ^$stressor, "$1"averages.csv | cut -d , -f 4-5 | sed -e '/,$/d' -e 's%^\([^,]\+\),\([^,]\+\)$%\2/\1%')
    base_ETR=$(printf "scale=16; $line\n" | bc)
    line=$(grep -e ^$stressor, "$2"averages.csv | cut -d , -f 4-5 | sed -e '/,$/d' -e 's%^\([^,]\+\),\([^,]\+\)$%\2/\1%')
    under_ETR=$(printf "scale=16; $line\n" | bc)
    ratio=$(printf "scale=2; $under_ETR/$base_ETR\n" | bc)
    stressor_list="$stressor_list $stressor"
    printf " $ratio &"
done
printf "\n"
printf "$stressor_list\n"
