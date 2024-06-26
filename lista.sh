#!/bin/bash
# ---------------------------------------------------
# Copyright (c) 2023, The beep-projects contributors
# this file originated from https://github.com/beep-projects
# Do not remove the lines above.
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see https://www.gnu.org/licenses/
#
#
# Shell script to get the status of a Linux system, like CPU usage, 
# disk usage, failed services, etc.
# ---------------------------------------------------


set -o noclobber  # Avoid overlay files (echo "hi" > foo)
#set -o errexit    # Used to exit upon error, avoiding cascading errors
set -o pipefail   # Unveils hidden failures
set -o nounset    # Exposes unset variables

#######################################
# Show help.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Prints usage information to stdout
#######################################
function help() {
cat <<END
  lista.sh: script to get status information about a Linux system
  Options are :
    --help|-h|-?                        display this help and exit
    --status                            displays a collection of various system status information
    --ramusage|-ram|-mem                get the current RAM usage
    --ramusagetopx|-ramtopx|-memtopx    get the top X processes for CPU usage. Accepts parameter X, which defaults to 5
    --cpuload|-cpu                      get the CPU load. Accepts parameter measurement duration in seconds, which defaults to 5s if unset
                                        Prints average load over all CPU cores. The first value is the overall load,
                                        each following entry is for another CPU core, CPU0, CPU1, CPU2, ...
    --cpuloadtopx|-cputopx              get the top X processes for CPU usage. Accepts parameter X, which defaults to 5
    --diskusage|-disk                   get the current disk usage as percentage of device size for each non tempfs device
    --linewidth|-lw                     sets the linewidth for output from --ramusagetopx and --cpuloadtopx
END
}

#######################################
# Print error message.
# Globals:
#   None
# Arguments:
#   $1 = Error message
#   $2 = return code (optional, default 1)
# Outputs:
#   Prints an error message to stderr
#######################################
function error() {
    printf "%s\n" "${1}" >&2 ## Send message to stderr.
    exit "${2:-1}" ## Return a code specified by $2, or 1 by default.
}

#######################################
# Writes user specific config files for the top command.
# This is needed, because top does not support a usable configuration via command line parameters and lista.sh
# does not want to interfere with any other existing configuration for top
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Writes lista_mem_toprc and lista_cpu_toprc into the user specific configuration folder ~/.config/procps
#######################################
function write_toprcs() {
  if ! [[ -f ~/.config/procps/lista_mem_toprc ]]; then
    mkdir -p ~/.config/procps
    cat << EOF > ~/.config/procps/lista_mem_toprc
top's Config File (Linux processes with windows)
Id:k, Mode_altscr=0, Mode_irixps=1, Delay_time=3.0, Curwin=0
Def	fieldscur= 117   75   81  102  104  118  122  128  136  110  114  139   76   78   82   84   86   88   90   92 
		    94   96   98  100  106  108  112  120  124  126  130  132  134  140  142  144  146  148  150  152 
		   154  156  158  160  162  164  166  168  170  172  174  176  178  180  182  184  186  188  190  192 
		   194  196  198  200  202  204  206  208  210  212  214  216  218  220  222  224  226  228  230  232 
		   234  236  238  240  242  244  246  248  250  252  254  256  258  260  262  264  266  268  270  272 
	winflags=193972, sortindx=18, maxtasks=0, graph_cpus=0, graph_mems=0, double_up=0, combine_cpus=0, core_types=0
	summclr=1, msgsclr=1, headclr=3, taskclr=1
Job	fieldscur=  75   77  115  111  117   80  103  105  137  119  123  128  120   79  139   82   84   86   88   90 
		    92   94   96   98  100  106  108  112  124  126  130  132  134  140  142  144  146  148  150  152 
		   154  156  158  160  162  164  166  168  170  172  174  176  178  180  182  184  186  188  190  192 
		   194  196  198  200  202  204  206  208  210  212  214  216  218  220  222  224  226  228  230  232 
		   234  236  238  240  242  244  246  248  250  252  254  256  258  260  262  264  266  268  270  272 
	winflags=193844, sortindx=0, maxtasks=0, graph_cpus=0, graph_mems=0, double_up=0, combine_cpus=0, core_types=0
	summclr=6, msgsclr=6, headclr=7, taskclr=6
Mem	fieldscur=  75  117  119  120  123  125  127  129  131  154  132  156  135  136  102  104  111  139   76   78 
		    80   82   84   86   88   90   92   94   96   98  100  106  108  112  114  140  142  144  146  148 
		   150  152  158  160  162  164  166  168  170  172  174  176  178  180  182  184  186  188  190  192 
		   194  196  198  200  202  204  206  208  210  212  214  216  218  220  222  224  226  228  230  232 
		   234  236  238  240  242  244  246  248  250  252  254  256  258  260  262  264  266  268  270  272 
	winflags=193844, sortindx=21, maxtasks=0, graph_cpus=0, graph_mems=0, double_up=0, combine_cpus=0, core_types=0
	summclr=5, msgsclr=5, headclr=4, taskclr=5
Usr	fieldscur=  75   77   79   81   85   97  115  111  117  137  139   82   86   88   90   92   94   98  100  102 
		   104  106  108  112  118  120  122  124  126  128  130  132  134  140  142  144  146  148  150  152 
		   154  156  158  160  162  164  166  168  170  172  174  176  178  180  182  184  186  188  190  192 
		   194  196  198  200  202  204  206  208  210  212  214  216  218  220  222  224  226  228  230  232 
		   234  236  238  240  242  244  246  248  250  252  254  256  258  260  262  264  266  268  270  272 
	winflags=193844, sortindx=3, maxtasks=0, graph_cpus=0, graph_mems=0, double_up=0, combine_cpus=0, core_types=0
	summclr=3, msgsclr=3, headclr=2, taskclr=3
Fixed_widest=0, Summ_mscale=1, Task_mscale=0, Zero_suppress=0, Tics_scaled=0
EOF
  fi
  if ! [[ -f ~/.config/procps/lista_cpu_toprc ]]; then
    mkdir -p ~/.config/procps
    cat << EOF > ~/.config/procps/lista_cpu_toprc
top's Config File (Linux processes with windows)
Id:k, Mode_altscr=0, Mode_irixps=1, Delay_time=3.0, Curwin=0
Def	fieldscur= 111   75   81  102  104  118  122  128  136  116  114  139   76   78   82   84   86   88   90   92 
		    94   96   98  100  106  108  112  120  124  126  130  132  134  140  142  144  146  148  150  152 
		   154  156  158  160  162  164  166  168  170  172  174  176  178  180  182  184  186  188  190  192 
		   194  196  198  200  202  204  206  208  210  212  214  216  218  220  222  224  226  228  230  232 
		   234  236  238  240  242  244  246  248  250  252  254  256  258  260  262  264  266  268  270  272 
	winflags=193972, sortindx=18, maxtasks=0, graph_cpus=0, graph_mems=0, double_up=0, combine_cpus=0, core_types=0
	summclr=1, msgsclr=1, headclr=3, taskclr=1
Job	fieldscur=  75   77  115  111  117   80  103  105  137  119  123  128  120   79  139   82   84   86   88   90 
		    92   94   96   98  100  106  108  112  124  126  130  132  134  140  142  144  146  148  150  152 
		   154  156  158  160  162  164  166  168  170  172  174  176  178  180  182  184  186  188  190  192 
		   194  196  198  200  202  204  206  208  210  212  214  216  218  220  222  224  226  228  230  232 
		   234  236  238  240  242  244  246  248  250  252  254  256  258  260  262  264  266  268  270  272 
	winflags=193844, sortindx=0, maxtasks=0, graph_cpus=0, graph_mems=0, double_up=0, combine_cpus=0, core_types=0
	summclr=6, msgsclr=6, headclr=7, taskclr=6
Mem	fieldscur=  75  117  119  120  123  125  127  129  131  154  132  156  135  136  102  104  111  139   76   78 
		    80   82   84   86   88   90   92   94   96   98  100  106  108  112  114  140  142  144  146  148 
		   150  152  158  160  162  164  166  168  170  172  174  176  178  180  182  184  186  188  190  192 
		   194  196  198  200  202  204  206  208  210  212  214  216  218  220  222  224  226  228  230  232 
		   234  236  238  240  242  244  246  248  250  252  254  256  258  260  262  264  266  268  270  272 
	winflags=193844, sortindx=21, maxtasks=0, graph_cpus=0, graph_mems=0, double_up=0, combine_cpus=0, core_types=0
	summclr=5, msgsclr=5, headclr=4, taskclr=5
Usr	fieldscur=  75   77   79   81   85   97  115  111  117  137  139   82   86   88   90   92   94   98  100  102 
		   104  106  108  112  118  120  122  124  126  128  130  132  134  140  142  144  146  148  150  152 
		   154  156  158  160  162  164  166  168  170  172  174  176  178  180  182  184  186  188  190  192 
		   194  196  198  200  202  204  206  208  210  212  214  216  218  220  222  224  226  228  230  232 
		   234  236  238  240  242  244  246  248  250  252  254  256  258  260  262  264  266  268  270  272 
	winflags=193844, sortindx=3, maxtasks=0, graph_cpus=0, graph_mems=0, double_up=0, combine_cpus=0, core_types=0
	summclr=3, msgsclr=3, headclr=2, taskclr=3
Fixed_widest=0, Summ_mscale=1, Task_mscale=0, Zero_suppress=0, Tics_scaled=0
EOF
  fi
}

#######################################
# Get some information about the system.
# Inspired by Ubuntu's landscape-sysinfo
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Prints information about the system
#######################################
function getSystemStatus() {
  local systemload
  systemload="$( cut -d " " -f 1 < /proc/loadavg )"
  local loggedin_users
  loggedin_users="$( users )"
  local usage_of_root
  usage_of_root=$( df -h / | awk 'NR==2{ print $5 }' )
  local size_of_root
  size_of_root=$( df -h / | awk 'NR==2{ print $2 }' )
  size_of_root="${size_of_root//M/ MB}"
  size_of_root="${size_of_root//G/ GB}"
  size_of_root="${size_of_root//T/ TB}"
  local memory_usage
  memory_usage=$( free -m | awk 'NR==2{printf "%d", $3*100/($2?$2:1) }' )"%"
  local swap_usage
  swap_usage=$( free -m | awk 'NR==3{printf "%d", $3*100/($2?$2:1) }' )"%"
  local temperature #maximum temperature in the thermal zones, most likely the CPU
  temperature=$( paste <(cat /sys/class/thermal/thermal_zone*/temp) | awk 'BEGIN{max=0}{if(($1)>max) max=($1)}END{printf "%02.1f°C\n", max/1000}' )
  local num_of_processes
  num_of_processes=$( ps aux | awk '{print $8}' | wc -l )
  local num_of_zombies
  # cat finishes to slow, sometimes it shows up as zombie, skip it with next
  num_of_zombies=$( ps aux | awk '/\[cat\] <defunct>$/ {next}{print $8}' | grep -c Z )
  local system_info
  printf -v system_info "%-25s %s\n" "System load:"             "${systemload}" \
                                     "Usage of /:"              "${usage_of_root} of ${size_of_root}" \
                                     "Memory usage:"            "${memory_usage}" \
                                     "Swap usage:"              "${swap_usage}" \
                                     "Temperature:"             "${temperature}" \
                                     "Processes:"               "${num_of_processes} (${num_of_zombies} Zombies)" \
                                     "Users logged in:"         "${loggedin_users}"
  local external_ip
  external_ip=$( curl --silent ifconfig.me )
  printf -v external_ip "%-25s %s" "External IP address:" "${external_ip}"
  local ipv4_info
  ipv4_info=$( ip -o addr show scope global | awk '$3 == "inet" {split($4, addr, "/"); printf "%-25s %s\n", "IPv4 address for "$2":", addr[1]}' )
  local ipv6_info
  ipv6_info=$( ip -o addr show scope global | awk '$3 == "inet6" {split($4, addr, "/"); printf "%-25s %s\n", "IPv6 address for "$2":", addr[1]}' )
  printf "%s%s\n%s\n%s" "${system_info}" \
                      "${external_ip}" \
                      "${ipv4_info}" \
                      "${ipv6_info}"

}

#######################################
# Get the current memory usage of the system.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Prints percentage of memory currently used
#######################################
function getMemoryUsage() {
  free -m | awk 'NR==2{print $3*100/$2 }'
}

#######################################
# Get the current load on all CPU cores of the system.
# Globals:
#   None
# Arguments:
#   X size of the top X list
# Outputs:
#   Prints the top X processes in terms of RAM usage. The values are %MEM, PID, COMMAND
#######################################
function getMemoryUsageTopX() {
  num_entries=$(( ${1:-5}+1 ))
  line_width=${2:-120}
  # shellcheck disable=SC2009 #disabled, because I see no benefit in using pgrep for this task
  # ps has only statistics for full process lifetime
  #ps -eo pmem,pid,user,command --sort=-%mem | grep -v "ps -eo pmem,pid,user,command --sort=-c" | head -n${num_entries} | cut -c -"${line_width}"
  write_toprcs
  exec -a lista_mem_top top -b -n 2 -d 1 -o +%MEM -w 512 | awk -v RS='(\n\n)' 'END{printf "%s\n",$0}' | head -n ${num_entries} | cut -c -"${line_width}"
  #ps ahux --sort=-%mem | awk -v x="${1:-5}" '/ps ahux --sort=-%mem/ {x=x+1;next} NR<=x{printf"%s %6d %s\n",$4,$2,$11}'
}

#######################################
# Get the current load on all CPU cores of the system.
# Globals:
#   None
# Arguments:
#   duration measurement duration for CPU load in second. Defaults to 5s.
# Outputs:
#   Prints average load over all CPU cores. The first value is the overall load,
#   each following entry is for another CPU core, CPU0, CPU1, CPU2, ...
#######################################
function getCpuUsage() {
  local cpu_cores
  cpu_cores=$( lscpu | grep '^CPU(s):' | awk '{print int($2)}' )
  duration=${1:-5}
  local mpstats_output=""
  if [ "${duration}" -le 0 ]; then
    mpstats_output=$( mpstat -P ALL 0 | tail -n $((cpu_cores + 1)) )
  else
    mpstats_output=$( mpstat -P ALL "${duration}" 1 | tail -n $((cpu_cores + 1)) )
  fi
  local mpstat_array=()
  read -r -a mpstat_array -d '' <<< "$mpstats_output"
  local len
  len=${#mpstat_array[@]}
  # mpstats values have the following structure
  # time   CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest  %gnice   %idle
  # in the following we want to access the %idle value at index 11, 23, 35, ...
  for (( i=0; i<len; i=i+12 )); do #calculate the load from the idle and iowait column
    awk -v iowait="${mpstat_array[(($i+5))]//,/\.}}" -v idle="${mpstat_array[(($i+11))]//,/\.}}" 'BEGIN{print 100.0 - iowait - idle }'
  done
}

#######################################
# Get the current load on all CPU cores of the system.
# Globals:
#   None
# Arguments:
#   X size of the top X list
# Outputs:
#   Prints the top X processes in terms of caused CPU load. The values are %CPU, PID, COMMAND
#######################################
function getCpuLoadTopX() {
  num_entries=$(( ${1:-5}+1 ))
  line_width=${2:-120}
  # shellcheck disable=SC2009 #disabled, because I see no benefit in using pgrep for this task
  # ps has only statistics for full process lifetime
  # ps -eo pcpu,pid,user,command --sort=-c | grep -v "ps -eo pcpu,pid,user,command --sort=-c" | head -n${num_entries} | cut -c -"${line_width}"
  #top -b -n 2 -d 10 -o +%CPU -w 512 | awk -v RS='(\r*\n){2,}' 'END{printf "%s\n",$0}' | head -n 6 | tail -n 5
  write_toprcs
  exec -a lista_cpu_top top -b -n 2 -d 1 -o +%CPU -w 512 | awk -v RS='(\n\n)' 'END{printf "%s\n",$0}' | head -n ${num_entries} | cut -c -"${line_width}"
  #ps ahux --sort=-c | awk -v x="${1:-5}" '/ps ahux --sort=-c/ {x=x+1;next} NR<=x{printf"%s %6d %s\n",$3,$2,$11}'
}

#######################################
# Get the current disk usage of all mounted disks.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Prints percentage of used space for each mounted disk
#   %Device %Mount Point %Used
#######################################
function getDiskUsage() {
  df -H | awk '(NR>1 && !/^tmpfs|cdrom/){sub(".$","",$5);  print $1 " " $6 " " $5 }'
}

function main() {
  # -------------------------------------------------------
  #   Loop to load arguments
  # -------------------------------------------------------

  # if no argument, display help
  if [ $# -eq 0 ]; then
    help
  fi

  # loop to retrieve arguments
  local STATUS="false"
  local RAM="false"
  local RAM_TOP_X="false"
  local CPU="false"
  local CPU_TOP_X="false"
  local DISK="false"
  local measurement_duration=3
  local cpu_top_x=5
  local ram_top_x=5
  local line_width=120
  while :; do
    case ${1:-} in
      -h|-\?|--help)
        help # show help for this script
        exit 0
      ;;
      --status)
        STATUS="true"
      ;;
        --ramusage|-ram|-mem)
        RAM="true"
      ;;
        --ramusagetopx|-ramtopx|-memtopx)
        RAM_TOP_X="true"
        if [[ ${2:-} =~ ^[0-9]+$ ]]; then
          ram_top_x=$2
          shift
        fi
      ;;
      --cpuload|-cpu)
        CPU="true"
        if [[ ${2:-} =~ ^[0-9]+$ ]]; then
          measurement_duration=$2
          shift
        fi
      ;;
      --cpuloadtopx|-cputopx)
        CPU_TOP_X="true"
        if [[ ${2:-} =~ ^[0-9]+$ ]]; then
          cpu_top_x=$2
          shift
        fi
      ;;
      --diskusage|-disk)
        DISK="true"
      ;;
      --linewidth|-lw)
        if [[ ${2:-} =~ ^[0-9]+$ ]]; then
          line_width=$2
          shift
        fi
      ;;
      --) # End of all options.
        shift
        break
      ;;
      -?*)
        printf '[lista.sh] WARN: Unknown option (ignored): %s\n' "$1" >&2
      ;;
      *) # Default case: No more options, so break out of the loop.
        break
    esac
    shift
  done

  if [ "${STATUS}" = "true" ]; then
    getSystemStatus
  fi

  if [ "${RAM}" = "true" ]; then
    getMemoryUsage
  fi

  if [ "${RAM_TOP_X}" = "true" ]; then
    getMemoryUsageTopX "$ram_top_x" "$line_width"
  fi

  if [ "${CPU}" = "true" ]; then
    getCpuUsage "$measurement_duration"
  fi

  if [ "${CPU_TOP_X}" = "true" ]; then
    getCpuLoadTopX "$cpu_top_x" "$line_width"
  fi

  if [ "${DISK}" = "true" ]; then
    getDiskUsage
  fi

}

main "$@"