#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# Run stress-ng to test the stability of a system in a critical state

# Debug
#set -x

LC_ALL=C
export LC_ALL

STRESSNGEXEC=./stress-ng

# NOTE: af-alg just queries AF_ALG socket in 6s and is thus excluded
# NOTE: affinity needs less than 4 stressors and might fail (--affinity 1 or 2)
# NOTE: cyclic runs best with 1 stressor (--cyclic 1)
# NOTE: mlock needs less than 4 stressors and might fail (--mlock 3)
# NOTE: tree triggers a kernel panic on the baseline of the 3B+ and is therefore excluded
# NOTE: dev tiggers a kernel bug on the 4B
# NOTE: sockpair tiggers a kernel panic on the 4B
sudo $STRESSNGEXEC --abort --aggressive --exclude $($STRESSNGEXEC --class filesystem? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/[[:space:]]\+/,/g'),af-alg,affinity,apparmor,bad-ioctl,bind-mount,cyclic,dccp,ioport,ipsec_mb,memhotplug,mlock,mlockmany,netlink-proc,numa,oom-pipe,pidfd,pkey,rdrand,sctp,sysinfo,tree,tsc,userfaultfd,watchdog --log-file ./stress-ng.log --matrix-size 4096 --matrix-3d-size 256 --maximize --memrate-bytes 128m --metrics-brief --sequential 0 --times --timestamp --tsearch-size 1048576 --verify --vm-rw-bytes 8m
