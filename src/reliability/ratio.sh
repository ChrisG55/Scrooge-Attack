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

for stressor in atomic bigheap bsearch clock fork futex get hdd hrtimers hsearch judy kcmp kill lsearch mergesort mq msg pipe poll seek sigsegv sysfs tmpfs tsearch urandom vm-rw wcs
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
    printf " & $ratio"
done
printf "\n"
printf "$stressor_list\n"

n=0
ratio_max=0
ratio_min=100000
#for stressor in aio aiol atomic bad-altstack bigheap branch brk bsearch cache cap chroot clock clone close context cpu crypt daemon dev dev-shm dynlib enosys env epoll fault fifo fork fp-error full funccall funcret futex get getrandom hdd heapsort hrtimers hsearch icache icmp-flood itimer judy kcmp key kill klog lockbus longjmp loop lsearch madvise malloc matrix matrix-3d mcontend membarrier memcpy memfd memrate memthrash mergesort mincore mmap mmapaddr mmapfixed mmapfork mmapmany mq mremap msg msync nanosleep netdev netlink-task nice nop null opcode personality physpage pipe pipeherd poll prctl pthread ptrace pty qsort quota radixsort ramfs rawdev rawpkt rawsock rawudp readahead reboot remap resources revio rlimit rmap rtc schedpolicy seal seccomp seek sem sem-sysv sendfile session set shellsort shm shm-sysv sigabrt sigchld sigfd sigfpe sigio sigpending sigpipe sigq sigrt sigsegv sigsuspend sigtrap skiplist sleep sock sockabuse sockdiag sockfd sockmany sockpair softlockup splice stack stackmmap str stream swap switch sysbadaddr sysfs sysinval tee timer timerfd tlb-shootdown tmpfs tsearch udp udp-flood unshare urandom vdso vecmath vfork vforkmany vm vm-addr vm-rw vm-segv vm-splice wait wcs yield zero zlib zombie
for stressor in aio aiol atomic bad-altstack bigheap branch brk bsearch cache cap chroot clock clone close context cpu crypt daemon dev dev-shm dynlib enosys env epoll fault fifo fork fp-error full funccall funcret futex get getrandom hdd heapsort hrtimers hsearch icache icmp-flood itimer judy kcmp key kill klog lockbus longjmp loop lsearch madvise malloc matrix matrix-3d mcontend membarrier memcpy memrate mergesort mincore mmapaddr mmapfixed mmapfork mmapmany mq msg msync nanosleep netdev netlink-task nice nop null opcode personality physpage pipe pipeherd poll prctl pthread ptrace pty qsort quota radixsort ramfs rawdev rawpkt rawsock rawudp reboot remap resources revio rlimit rmap schedpolicy seal seccomp seek sem sem-sysv sendfile session set shm-sysv sigabrt sigchld sigfd sigfpe sigio sigpending sigpipe sigq sigrt sigsegv sigsuspend sigtrap skiplist sleep sock sockabuse sockfd sockmany sockpair softlockup splice stack stackmmap str stream swap switch sysbadaddr sysfs sysinval tee timer timerfd tlb-shootdown tmpfs tsearch udp udp-flood unshare urandom vdso vecmath vfork vforkmany vm-rw vm-segv vm-splice wait wcs
do
    base_stressor=$(grep -q -e ^$stressor, "$1"averages.csv)
    [ $? -eq 1 ] && warn "main" "stressor $stressor not available in ${1}averages.csv" && continue
    under_stressor=$(grep -q -e ^$stressor, "$2"averages.csv)
    [ $? -eq 1 ] && warn "main" "stressor $stressor not available in ${2}averages.csv" && continue
    line=$(grep -e ^$stressor, "$1"averages.csv | cut -d , -f 4-5 | sed -e '/,$/d' -e 's%^\([^,]\+\),\([^,]\+\)$%\2/\1%')
    base_ETR=$(printf "scale=16; $line\n" | bc 2>/dev/null)
    [ -z "$base_ETR" ] && warn "main" "$stressor has zero ETR at base" && continue
    line=$(grep -e ^$stressor, "$2"averages.csv | cut -d , -f 4-5 | sed -e '/,$/d' -e 's%^\([^,]\+\),\([^,]\+\)$%\2/\1%')
    under_ETR=$(printf "scale=16; $line\n" | bc 2>/dev/null)
    [ -z "$under_ETR" ] && warn "main" "$stressor has zero ETR when undervolted" && continue
    ratio=$(printf "scale=2; $under_ETR/$base_ETR\n" | bc)
    [ -n "${ratio%%.*}" ] && [ ${ratio%%.*} -gt 16 ] && warn "main" "$stressor has ratio >16" && continue
    ratio_min=$(awk -v rmin=$ratio_min -v r=$ratio 'BEGIN { if (r < rmin) printf("%.2f\n", r); else printf("%.2f\n", rmin); }')
    ratio_max=$(awk -v rmax=$ratio_max -v r=$ratio 'BEGIN { if (r > rmax) printf("%.2f\n", r); else printf("%.2f\n", rmax); }')
    ratio_sum="${ratio_sum}+$ratio"
    n=$((n+1))
done
# printf "ratio_sum=${ratio_sum#+}\n"
# printf "n=$n\n"
# printf "sum=$(printf "scale=2; ${ratio_sum#+}\n" | bc)\n"
printf "scale=2; (${ratio_sum#+})/$n\n" | bc
printf "min=$ratio_min\tmax=$ratio_max\n"
