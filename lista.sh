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
    -h/-?/--help                         display this help and exit
    --ramusage|-ram|-mem                 get the current RAM usage
    --ramusagetopx|-ramtopx|-memtopx)    get the top X processes for CPU usage. Accepts parameter X, which defaults to 5
    --cpuusage|-cpu                      get the CPU usage. Accepts parameter measurement duration in seconds, which defaults to 5s if unset
                                         Prints average load over all CPU cores. The first value is the overall load,
                                         each following entry is for another CPU core, CPU0, CPU1, CPU2, ...
    --cpuloadtopx|-cputopx)              get the top X processes for CPU usage. Accepts parameter X, which defaults to 5
    --diskusage|-disk)                   get the current disk usage as percentage of installed RAM
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
    exit "${2-1}" ## Return a code specified by $2, or 1 by default.
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
  ps ahux --sort=-%mem | awk -v x="${1:-5}" '/ps ahux --sort=-%mem/ {x=x+1;next} NR<=x{printf"%s %6d %s\n",$4,$2,$11}'
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
  cpu_cores=$( lscpu | grep '^CPU(s):' | awk '{print int($2)}' )
  duration=${1:-5}
  if [ "${duration}" -le 0 ]; then
    mpstats_output=$( mpstat -P ALL 0 | tail -n $((cpu_cores + 1)) )
  else
    mpstats_output=$( mpstat -P ALL 1 "${duration}" | tail -n $((cpu_cores + 1)) )
  fi
  mpstat_array=()
  read -r -a mpstat_array -d '' <<< "$mpstats_output"

  len=${#mpstat_array[@]}
  # mpstats values have the following structure
  # time   CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest  %gnice   %idle
  # in the following we want to access the %idle value at index 11, 23, 35, ...
  for (( i=11; i<len; i=i+12 )); do #calculate the load from the idle column
    awk -v idle="${mpstat_array[$i]//,/\.}}" 'BEGIN{print 100.0 - idle }'
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
  ps ahux --sort=-c | awk -v x="${1:-5}" '/ps ahux --sort=-c/ {x=x+1;next} NR<=x{printf"%s %6d %s\n",$3,$2,$11}'
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
  df -H | grep -vE '^Filesystem|tmpfs|cdrom' | awk '{sub(".$","",$5); print $1 " " $6 " " $5 }'
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
  local RAM="false"
  local RAM_TOP_X="false"
  local CPU="false"
  local CPU_TOP_X="false"
  local DISK="false"
  local measurement_duration=3
  local cpu_top_x=5
  local ram_top_x=5
  while :; do
    case ${1:-} in
      -h|-\?|--help)
      help # show help for this script
      exit 0
      ;;
      --ramusage|-ram|-mem)
      RAM="true"
      ;;
      --ramusagetopx|-ramtopx|-memtopx)
      RAM_TOP_X="true"
      if [[ ${2:-} == ?(-)+([0-9]) ]]; then
        ram_top_x=$2
        shift
      fi
      ;;
      --cpuusage|-cpu)
      CPU="true"
      if [[ ${2:-} == ?(-)+([0-9]) ]]; then
        measurement_duration=$2
        shift
      fi
      ;;
      --cpuloadtopx|-cputopx)
      CPU_TOP_X="true"
      if [[ ${2:-} == ?(-)+([0-9]) ]]; then
        cpu_top_x=$2
        shift
      fi
      ;;
      --diskusage|-disk)
      DISK="true"
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

  if [ "${RAM}" = "true" ]; then
    getMemoryUsage
  fi

  if [ "${RAM_TOP_X}" = "true" ]; then
    getMemoryUsageTopX "$ram_top_x"
  fi

  if [ "${CPU}" = "true" ]; then
    getCpuUsage "$measurement_duration"
  fi

  if [ "${CPU_TOP_X}" = "true" ]; then
    getCpuLoadTopX "$cpu_top_x"
  fi

  if [ "${DISK}" = "true" ]; then
    getDiskUsage
  fi

}

main "$@"