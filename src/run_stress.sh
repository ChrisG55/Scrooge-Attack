#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# Run stress-ng to test the stability of a system in a critical state

# Debug
#set -x

LC_ALL=C
export LC_ALL

STRESSNGEXEC=./stress-ng

sudo $STRESSNGEXEC --aggressive --exclude $($STRESSNGEXEC --class filesystem? | sed -e 's/^.\+: \(.\+\)$/\1/' -e 's/[[:space:]]\+/,/g'),apparmor,bad-ioctl,bind-mount,dccp,ioport,ipsec_mb,memhotplug,mlockmany,netlink-proc,numa,oom-pipe,pidfd,pkey,rdrand,sctp,sysinfo,tsc,watchdog --log-file ./stress-ng.log --matrix-size 4096 --matrix-3d-size 256 --maximize --metrics-brief --sequential 0 --times --timestamp --verify
