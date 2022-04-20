#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# usage: print_msg <type> <fct> <msg>...
print_msg()
{
    [ $# -lt 3 ] && printf " [%7s] print_msg: invalid number of arguments $#/3+\n" "ERROR"
    type=$1
    shift
    fct=$1
    shift
    printf " [%7s] $fct: $*\n" $type >&2
}

# usage: fail <function> <msg>...
fail()
{
    [ $# -lt 2 ] && fail "fail" "invalid number of arguments $#/2+"
    print_msg "ERROR" $*
    exit 1
}

# usage: warn <function> <msg>...
warn()
{
    [ $# -lt 2 ] && fail "warn" "invalid number of arguments $#/2+"
    print_msg "WARNING" $*
}
