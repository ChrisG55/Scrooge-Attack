#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Christian Göttel

# Debug
#set -x

LC_ALL=C
export LC_ALL

readonly LOG="./param.log"

while [ 1 ]
do
    date +%s >>"$LOG"
    vcgencmd measure_temp >>"$LOG"
    sleep 1
done
