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

# Initialize all the option variables.
# This ensures we are not contaminated by variables from the environment.
RAM="false"
CPU="false"
CPU_MEASUREMENT_DURATION=5
DISK="false"

# save the arguments in case they are required later
ARGS=$*

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
    Main parameters are :
    -h/-?/--help           display this help and exit
  Options are :
    --title <title>        Title of the message

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
#   CPU_MEASUREMENT_DURATION in seconds
# Arguments:
#   None
# Outputs:
#   Prints average load over all CPU cores. The first value is the overall load,
#   each following entry is for another CPU core, CPU0, CPU1, CPU2, ...
#######################################
function getCpuUsage() {
  cpu_cores=$( lscpu | grep '^CPU(s):' | awk '{print int($2)}' )

  if [ "${CPU_MEASUREMENT_DURATION}" -le 0 ]; then
    mpstats_output=$( mpstat -P ALL 0 | tail -n $((cpu_cores + 1)) )
  else
    mpstats_output=$( mpstat -P ALL 1 "${CPU_MEASUREMENT_DURATION}" | tail -n $((cpu_cores + 1)) )
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
# Get the current disk usage of all mounted disks.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Prints percentage of used space for each mounted disk
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
  while :; do
    case ${1:-} in
      -h|-\?|--help)
      help # show help for this script
      exit 0
      ;;
      --ramusage|-ram|-mem)
      RAM="true"
      ;;
      --cpuusage|-cpu)
      CPU="true"
      if [[ ${2:-} == ?(-)+([0-9]) ]]; then
        CPU_MEASUREMENT_DURATION=$2
        shift
      #else
      #  CPU_MEASUREMENT_DURATION=5
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

  if [ "${CPU}" = "true" ]; then
    getCpuUsage
  fi

  if [ "${DISK}" = "true" ]; then
    getDiskUsage
  fi

}

main "$@"