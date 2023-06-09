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
# Shell script to get the status of a Linux system, like CPU usage, 
# disk usage, failed services, etc.
# ---------------------------------------------------

set -o noclobber  # Avoid overlay files (echo "hi" > foo)
#set -o errexit    # Used to exit upon error, avoiding cascading errors
set -o pipefail   # Unveils hidden failures
set -o nounset    # Exposes unset variables

# Initialize all the option variables.
# This ensures we are not contaminated by variables from the environment.
BOT_TOKEN=""
CHAT_ID=""
DISK_LIMIT=""
CPU_LIMIT=""
RAM_LIMIT=""
CHECK_INTERVAL=""

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
# Load the configuration file.
# Globals:
#   BOT_TOKEN
#   CHAT_ID
#   DISK_LIMIT
#   CPU_LIMIT
#   RAM_LIMIT
#   CHECK_INTERVAL
# Arguments:
#   None
# Outputs:
#   updates the globals to the values set in ista_watchdog.conf
#######################################
function loadConfig() {
  CONF_FILE=lista_watchdog.conf

  if [ ! -f "$CONF_FILE" ]; then
    echo "File '${CONF_FILE}' not found. I can't run without this."
    exit
  fi
  # shellcheck source=./lista_watchdog.conf
  source "${CONF_FILE}"

  # check if all variables are present
  CONF_IS_COMPLETE=true
  variables=("${BOT_TOKEN}" "${DISK_LIMIT}" "${CPU_LIMIT}" "${RAM_LIMIT}" "${CHECK_INTERVAL}")
  for variable in "${variables[@]}"; do
    if [[ -z "${variable}" ]]; then
      echo "missing variable ${variable} in ${CONF_FILE}"
      CONF_IS_COMPLETE=false
    fi
  done
  if ! $CONF_IS_COMPLETE; then
    exit 1
  fi
  # without CHAT_ID, the watchdog is useless, so we are trying to fix a missing CHAT_ID by waiting
  # for the first one to send /start to the configured BOT_TOKEN
  while [[ -z "${CHAT_ID}" ]]; do
    UPDATEJSON=$( telegram.bot --get_updates --bottoken ${BOT_TOKEN} )
    CHAT_ID=$( echo "${UPDATEJSON}" | jq ".result | [.[].message | select(.text==\"/start\")][0] | .chat.id" )
    if [[ -z "${CHAT_ID}" ]]; then
      sleep $CHECK_INTERVAL
    else 
      sed -i "s/^CHAT_ID=.*/CHAT_ID=$CHAT_ID/" $CONF_FILE
    fi
  done
}

function main() {
  while :; do
    # load config, it might be changed since the lasst loop by lista_bot.sh
    loadConfig
    ###################
    # Check RAM usage #
    ###################
    ram=$( ./lista.sh --ramusage )
    if [[ "${ram%.*}" -ge $RAM_LIMIT ]]; then
      echo "RAM warning!"
      telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --warning --title "RAM Limit exceeded!" --text "RAM usage is currently @ ${ram}%"
    fi
    ###################
    # Check CPU usage #
    ###################
    mapfile -t cpu < <( ./lista.sh --cpuusage 1 )
    send_cpu_alert=false
    cpu_alert_text="\`\`\`\nALL  ${cpu[0]}%"
    len=${#cpu[@]}
    for (( i=1; i<len; i++ )); do
      cpu_alert_text+="\nCPU$((i-1)) ${cpu[$i]}%"
      if [[ "${cpu[$i]%.*}" -ge $CPU_LIMIT ]]; then
        send_cpu_alert=true
      fi
    done
    if $send_cpu_alert; then
      cpu_alert_text+="\n\`\`\`"
      telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --warning --title "High CPU load detected!" --text "${cpu_alert_text}"
    fi 
    ####################
    # Check disk usage #
    ####################
    disk=$( ./lista.sh --diskusage | awk -v disk_limit="${DISK_LIMIT}" '{ if( $3 > disk_limit ) print $1 " mounted as " $2 ": " $3 "%"}' )
    if [[ -n "${disk}" ]]; then
      telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --warning --title "Disk filled over the limit!" --text "${disk}"
    fi
    ###################
    # all checks done #
    ###################
    sleep $CHECK_INTERVAL
  done

}

main "$@"