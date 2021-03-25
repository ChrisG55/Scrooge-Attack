#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# Debug
#set -x

LC_ALL=C
export LC_ALL

readonly DATADIR="../../data/guardband"

# usage: retrieve_cpuno lino
#   lino  Line number offset into log file
# ENVIRONMENT:
#   CPUNO   assigns the CPU number
#   LOG     reads from Linux kernel log file
# RETURN VALUE:
#   0    successful completion
#   >0   an error occurred
# STDERR:
#   The standard error shall be used only for diagnostic messages.
retrieve_cpuno()
{
    lino=1
    if [ $# -eq 1 ]
    then
	lino=$1
    elif [$# -gt 1 ]
    then
	warn "retrieve_cpuno" "Invalid number of arguments $#/1" && return 1
    fi
    [ ! -s "$LOG" ] && { CPUNO="n/a"; warn "retrieve_cpuno" "'$LOG' is not a file"; return 2; }
    CPUNO=$(tail -n +$lino "$LOG" | sed -n -e '/^\[[[:space:]]*[[:digit:]]\+\.[[:digit:]]\+\] \(WARNING: \)\{0,1\}CPU: [[:digit:]]\+ .*$/ s/^\[[[:space:]]*[[:digit:]]\+\.[[:digit:]]\+\] \(WARNING: \)\{0,1\}CPU: \([[:digit:]]\+\) PID: .*$/\2/p' | head -n 1)
    [ -z "$CPUNO" ] && CPUNO="n/a"
    return 0
}

# usage: retrieve_exception_class lino
#   lino  Line number offset into log file
# ENVIRONMENT:
#   EC      assigns the CPU number
#   LOG     reads from Linux kernel log file
# RETURN VALUE:
#   0    successful completion
#   >0   an error occurred
# STDERR:
#   The standard error shall be used only for diagnostic messages.
retrieve_exception_class()
{
    lino=1
    if [ $# -ne 1 ]
    then
	lino=$1
    elif [ $# -gt 1 ]
    then
	warn "retrieve_exception_class" "Invalid number of arguments $#/1" && return 1
    fi
    [ ! -s "$LOG" ] && { EC="n/a"; warn "retrieve_exception_class" "'$LOG' is not a file"; return 2; }
    EC=$(tail -n +$lino "$LOG" | sed -n -e '/^\[[[:space:]]*[[:digit:]]\+\.[[:digit:]]\+\]   Exception class = .*$/ s/^\[[[:space:]]*[[:digit:]]\+\.[[:digit:]]\+\]   Exception class = \([^,]\+\),.*$/\1/p' | head -n 1)
    [ -z "$EC" ] && EC="n/a"
    return 0
}

# usage: retrieve_pid lino
#   lino  Line number offset into log file
# ENVIRONMENT:
#   PID     assigns the process identifier
#   LOG     reads from Linux kernel log file
# RETURN VALUE:
#   0    successful completion
#   >0   an error occurred
# STDERR:
#   The standard error shall be used only for diagnostic messages.
retrieve_pid()
{
    lino=1
    if [ $# -eq 1 ]
    then
	lino=$1
    elif [ $# -gt 1 ]
    then
	warn "retrieve_pid" "Invalid number of arguments $#" && return 1
    fi
    [ ! -s "$LOG" ] && { PID="n/a"; warn "retrieve_pid" "'$LOG' is not a file"; return 2; }
    PID=$(tail -n +$lino "$LOG" | sed -n -e '/^\[[[:space:]]*[[:digit:]]\+\.[[:digit:]]\+\] \(WARNING: \)\{0,1\}CPU: [[:digit:]]\+ PID: [[:digit:]]\+ .*$/ s/^\[[[:space:]]*[[:digit:]]\+\.[[:digit:]]\+\] \(WARNING: \)\{0,1\}CPU: [[:digit:]]\+ PID: \([[:digit:]]\+\) .*$/\2/p' | head -n 1)
    [ -z "$PID" ] && PID="n/a"
    return 0
}

# usage: retrieve_process lino
#   lino  Line number offset into log file
# ENVIRONMENT:
#   PROC    assigns the process name
#   LOG     reads from Linux kernel log file
# RETURN VALUE:
#   0    successful completion
#   >0   an error occurred
# STDERR:
#   The standard error shall be used only for diagnostic messages.
retrieve_process()
{
    lino=1
    if [ $# -ne 1 ]
    then
	lino=$1
    elif [ $# -gt 1 ]
    then
	warn "retrieve_process" "Invalid number of arguments $#/1" && return 1
    fi
    [ ! -s "$LOG" ] && { PROC="n/a"; warn "retrieve_process" "'$LOG' is not a file"; return 2; }
    PROC=$(tail -n +$lino "$LOG" | sed -n -e '/^\[[[:space:]]*[[:digit:]]\+\.[[:digit:]]\+\] Process .*$/ s/^\[[[:space:]]*[[:digit:]]\+\.[[:digit:]]\+\] Process \([^[:space:]]\+\) (.*$/\1/p' | head -n 1)
    [ -z "$PROC" ] && PROC="n/a"
    return 0
}

# usage: retrieve_refcount lino
#   lino  Line number offset into log file
# ENVIRONMENT:
#   EC      assigns the refcount exception
#   LOG     reads from Linux kernel log file
# RETURN VALUE:
#   0    successful completion
#   >0   an error occurred
# STDERR:
#   The standard error shall be used only for diagnostic messages.
retrieve_refcount()
{
    lino=1
    if [ $# -ne 1 ]
    then
	lino=$1
    elif [ $# -gt 1 ]
    then
	warn "retrieve_refcount" "Invalid number of arguments $#/1" && return 1
    fi
    [ ! -s "$LOG" ] && { EC="n/a"; warn "retrieve_refcount" "'$LOG' is not a file"; return 2; }
    EC=$(tail -n +$lino "$LOG" | sed -n -e '/^\[[[:space:]]*[[:digit:]]\+\.[[:digit:]]\+\] refcount_t: .*$/ s/^\[[[:space:]]*[[:digit:]]\+\.[[:digit:]]\+\] refcount_t: \([^\.]\+\)\.$/\1/p' | head -n 1)
    [ -z "$EC" ] && EC="n/a"
    return 0
}

# usage: parse_failed_measurements dir
# STDERR:
#   The standard error shall be used only for diagnostic messages.
parse_failed_measurements()
{
    ov=$(printf "$DU\n" | sed -e 's/dU//' -e 'y/n/-/')
    for LOG in "$1"/kernel_*.log
    do
	printf "LOG='$LOG'\n" >&2

	measurement_id=$(printf "$LOG" | sed -e 's/^[^_]\+_\([[:digit:]]\+\)\.log$/\1/')
	type=0 # "unknown" (default)

	# Search for Linux kernel Oops
	str=$(grep -n -e '] Unable to handle kernel ' "$LOG")
	if [ $? -eq 0 ]
	then
	    # Did the Oops lead to a Linux kernel panic?
	    panic="n/a"
	    matches=$(grep -n -e '] Kernel panic - ' "$LOG")
	    [ $? -eq 0 ] && panic=$(printf "$matches\n" | sed -e 's/^[^-]\+- \(.\+\)$/\1/' | sed -e ':a;N;$!ba;s/\n/;/g')

	    lineno=${str%%:*}
	    pipeout=$(printf "$str\n" | while read line
		      do
			  word=$(printf "$line\n" | sed -e 's/^.\+\[[[:space:]]*[[:digit:]]\+\.[[:digit:]]\+\] Unable to handle kernel \([[:alpha:]]\+\)[^[:alpha:]]*.*$/\1/')
			  case $word in
			      NULL)
				  type=1 # "NULL pointer dereference"
				  printf " $type"
				  retrieve_refcount $lineno
				  retrieve_cpuno $lineno
				  retrieve_pid $lineno
				  PROC="n/a"
				  ;;
			      pagin|paging)
				  type=2 # "paging request at virtual address"
				  printf " $type"
				  retrieve_exception_class $lineno
				  retrieve_cpuno $lineno
				  retrieve_pid $lineno
				  retrieve_process $lineno
				  # cpu=$(tail -n +$lineno "$log" | sed -n -e '/^\[[[:space:]]*[[:digit:]]\+\.[[:digit:]]\+\] CPU: .*$/ s/^\[[[:space:]]*[[:digit:]]\+\.[[:digit:]]\+\] CPU: \([[:digit:]]\+\) PID.*$/\1/p' | head -n 1)
				  # if [ -z "$cpu" ]
				  # then
				  #     cpu="n/a"
				  # fi
				  ;;
			      read)
				  type=3 # "read from unreadable memory at virtual address"
				  printf " $type"
				  retrieve_exception_class $lineno
				  retrieve_cpuno $lineno
				  retrieve_pid $lineno
				  retrieve_process $lineno
				  ;;
			      write)
				  type=4 # "write to read-only memory at virtual address"
				  printf " $type"
				  # Probably no data can be retrieved for this type
				  retrieve_exception_class $lineno
				  retrieve_cpuno $lineno
				  retrieve_pid
				  retrieve_process $lineno
				  ;;
			      *)
				  printf " 0" # "unknown"
				  break;
			  esac
			  printf "$m,$f,$ov,$T,$measurement_id,$type,$EC,$CPUNO,$PID,$PROC,$panic\n" >>failure.csv
		      done)
	    type=${pipeout##* }
	    [ $type -eq 0 ] && fail "parse_failed_measurements" "Unknown 'Unable to handle kernel ...' failure in '$LOG'"
	fi

        # Search for system freeze
	str=$(sed -n -e '$ s/^\(pi@raspberrypi:~\$ \)\{0,1\}\[[[:space:]]*[[:digit:]]\+\.[[:digit:]]\+\] \(.*\)$/\2/p' "$LOG")
	if [ "x$str" = "xreboot: Restarting system" ]
	then
	    type=5 # "reboot freeze"
	    printf "$m,$f,$ov,$T,$measurement_id,$type,n/a,n/a,n/a,n/a,n/a\n" >>failure.csv
	fi

	str=$(tail -n 1 "$LOG" | sed -e 's/^\(\[[[:space:]]*[[:digit:]]\+\.[[:digit:]]\+\]\).*$/\1/')
	if [ $type -eq 0 ] && [ -n "$str" ]
	then
	    type=6 # "bootup freeze"
	    printf "$m,$f,$ov,$T,$measurement_id,$type,n/a,n/a,n/a,n/a,n/a\n" >>failure.csv
	fi
	
	[ $type -eq 0 ] && fail "parse_failed_measurements" "Unknown kernel failure in '$LOG'"
    done
}

# usage: generate_csv dir temperature
generate_csv()
{
    [ -d "${1}failures" ] && parse_failed_measurements "${1}failures"
}

# usage: traverse_soft_limit dir temperature
# ENVIRONMENT: changes the value of the global variable DU
traverse_soft_limit()
{
    for soft_limit in $(ls -d "$1"*/ 2>/dev/null)
    do
	sl=$(printf "$soft_limit\n" | sed -e 's/^.\+\(SL[[:digit:]]\+\).*/\1/')
	DU="${DU%SL*}$sl"
	generate_csv "$soft_limit" $2
	#eval "printf \"$DU=\$$DU\n\""
    done
}

# usage: traverse_measurements dir
# ENVIRONMENT: changes the value of the global variable DU
traverse_measurements()
{
    for model in $(ls -d "$1"/*/ 2>/dev/null)
    do
	printf "$model\n"
	m="${model%/}"
	m="${m##*/}"
	for frequency in $(ls -d "$model"*/ 2>/dev/null)
	do
	    printf "$frequency\n"
	    f=$(printf "$frequency\n" | sed -e 's/^.\+f\([[:digit:]]\+\).*$/\1/')
	    # The overvoltage has to be traversed in descending order
	    for overvoltage in $(ls -d "$frequency"*/ 2>/dev/null)
	    do
		DU="${overvoltage%/}"
		DU="$(printf "${DU##*/}" | tr '-' 'n')"
		for temperature in $(ls -d "$overvoltage"*/ 2>/dev/null)
		do
		    T=$(printf "$temperature\n" | sed -e 's/^.\+T\([[:digit:]]\+\).*$/\1/')
		    # The Raspberry Pi 3B+ has a soft limit starting at 60°C and
		    # needs an additional directory level. The first temperature
		    # to include this addtional directory level is 59°C.
		    if [ "x$m" = "x3B+" ] && [ $T -ge 59 ]
		    then
			traverse_soft_limit "$temperature" $T
		    else
			generate_csv "$temperature" $T
		    fi
		done
	    done
	done
    done
}

# Print program usage.
# usage: usage
# STDOUT:
#   The standard output shall be a description of the program's usage.
usage()
{
    printf "Failure plot generator\n"
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
