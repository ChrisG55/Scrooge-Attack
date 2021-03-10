#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# Run stress-ng to test the stability of a system in a critical state

# Debug
#set -x

LC_ALL=C
export LC_ALL

STRESSNGEXEC=./stress-ng

usage()
{
    printf "usage: $0 [-h|--help] [mode]\n"
    printf "  mode   either energy or reliability (default: reliability)\n"
}

mode=$1
if [ -z "$mode" ]
then
    mode=reliability
fi

case $1 in
    reliability)
	# NOTE: af-alg just queries AF_ALG socket in 6s and is thus excluded
	# NOTE: affinity needs less than 4 stressors and might fail (--affinity 1 or 2)
	# NOTE: cyclic runs best with 1 stressor (--cyclic 1)
	# NOTE: mlock needs less than 4 stressors and might fail (--mlock 3)
	# NOTE: tree triggers a kernel panic on the baseline of the 3B+ and is therefore excluded
	# NOTE: dev tiggers a kernel bug on the 4B
	# NOTE: sockpair tiggers a kernel panic on the 4B
	STRESSORS="--exclude $($STRESSNGEXEC --class filesystem? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/[[:space:]]\+/,/g'),af-alg,affinity,apparmor,bad-ioctl,bind-mount,cyclic,dccp,ioport,ipsec_mb,memhotplug,mlock,mlockmany,netlink-proc,numa,oom-pipe,pidfd,pkey,rdrand,sctp,sysinfo,tree,tsc,userfaultfd,watchdog --matrix-size 4096 --matrix-3d-size 256 --memrate-bytes 128m --tsearch-size 1048576 --vm-rw-bytes 8m"
	;;
    energy)
	# crypt: CPU-bound stressor
	# malloc: memory-bound stressor
	STRESSORS="--exclude $($STRESSNGEXEC --class cpu? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/crypt//' -e 's/[[:space:]]\+/,/g'),$($STRESSNGEXEC --class cpu-cache? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/malloc//' -e 's/[[:space:]]\+/,/g'),$($STRESSNGEXEC --class device? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/[[:space:]]\+/,/g'),$($STRESSNGEXEC --class io? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/[[:space:]]\+/,/g'),$($STRESSNGEXEC --class interrupt? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/crypt//' -e 's/[[:space:]]\+/,/g'),$($STRESSNGEXEC --class filesystem? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/[[:space:]]\+/,/g'),$($STRESSNGEXEC --class memory? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/malloc//' -e 's/[[:space:]]\+/,/g'),$($STRESSNGEXEC --class network? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/[[:space:]]\+/,/g'),$($STRESSNGEXEC --class os? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/malloc//' -e 's/[[:space:]]\+/,/g'),$($STRESSNGEXEC --class pipe? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/[[:space:]]\+/,/g'),$($STRESSNGEXEC --class scheduler? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/[[:space:]]\+/,/g'),$($STRESSNGEXEC --class security? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/[[:space:]]\+/,/g'),$($STRESSNGEXEC --class vm? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/malloc//' -e 's/[[:space:]]\+/,/g')"
	;;
    -h|--help)
	usage
	exit 0
	;;
    *)
	printf "  ERROR: invalid mode '$1'\n" >&2
	usage
	exit 1
esac

sudo $STRESSNGEXEC --abort --aggressive $STRESSORS --log-file ./stress-ng.log --maximize --metrics-brief --sequential 0 --times --timestamp --verify
