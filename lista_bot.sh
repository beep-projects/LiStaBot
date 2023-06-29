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
# Configure the lista_watchdog.conf via a telegram bot account
# Depends on telegram.bot from https://github.com/beep-projects/telegram.bot
# ---------------------------------------------------

set -o noclobber  # Avoid overlay files (echo "hi" > foo)
#set -o errexit    # Used to exit upon error, avoiding cascading errors
set -o pipefail   # Unveils hidden failures
set -o nounset    # Exposes unset variables

# Initialize all the option variables.
# This ensures we are not contaminated by variables from the environment.
WATCHDOG_CONF_FILE="/etc/listabot/lista_watchdog.conf"
BOT_CONF_FILE="/etc/listabot/lista_bot.conf"
BOT_TOKEN=""
CHAT_ID=""
DISK_LIMIT=""
CPU_LIMIT=""
RAM_LIMIT=""
CHECK_INTERVAL=""

TIMEOUT=60 # long polling intervall = 10 minutes, but get's currently ignored by the Telegram server
ATTACK_LIMIT=3 # how many unauthorized requests are allowed before the bot shuts down itself

function escapeReservedCharacters() {
  STRING=$1
  STRING="${STRING//\(/\\\(}"
  STRING="${STRING//\)/\\\)}"
  STRING="${STRING//\[/\\\[}"
  STRING="${STRING//\]/\\\]}"
  STRING="${STRING//\_/\\\_}"
  STRING="${STRING//\*/\\\*}"
  STRING="${STRING//\~/\\\~}"
  STRING="${STRING//\`/\\\`}"
  STRING="${STRING//\|/\\\|}"
  echo "${STRING}"
}

#######################################
# Load the configuration file.
# Globals:
#   WATCHDOG_CONF_FILE
#   BOT_CONF_FILE
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
  if [[ ! -f "$WATCHDOG_CONF_FILE" ]]; then
    echo "File '${WATCHDOG_CONF_FILE}' not found. I can't run without this."
    exit
  fi
  # shellcheck disable=SC1090
  source "${WATCHDOG_CONF_FILE}"
  if [[ ! -f "$BOT_CONF_FILE" ]]; then
    echo "ADMIN_ID" >> "$BOT_CONF_FILE"
    echo "LAST_UPDATE_ID" >> "$BOT_CONF_FILE"
  fi
  # shellcheck disable=SC1090
  source "${BOT_CONF_FILE}"

  # check if all watchdog variables are present
  local conf_complete
  conf_complete=true
  local variables
  variables=("${BOT_TOKEN}" "${DISK_LIMIT}" "${CPU_LIMIT}" "${RAM_LIMIT}" "${CHECK_INTERVAL}")
  local variable
  for variable in "${variables[@]}"; do
    if [[ -z "${variable}" ]]; then
      echo "missing variable ${variable} in ${WATCHDOG_CONF_FILE}"
      conf_complete=false
    fi
  done
  if ! $conf_complete; then
    exit 1
  fi
  # without CHAT_ID, the watchdog is useless, so we are trying to fix a missing CHAT_ID by waiting
  # for the first receiption of the /start command. This message is also used to set ADMIN_ID and LAST_UPDATE_ID
  local update_json
  while [[ -z "${CHAT_ID}" ]] || [[ -z "${ADMIN_ID}" ]] || [[ -z "${LAST_UPDATE_ID}" ]]; do
    update_json=$( telegram.bot --get_updates --bottoken "${BOT_TOKEN}" )
    CHAT_ID=$( echo "${update_json}" | jq ".result | [.[].message | select(.text==\"/start\")][-1].chat.id" )
    ADMIN_ID=$( echo "${updateJSON}" | jq ".result | [.[].message | select(.text==\"/start\")][-1].from.id" )
    LAST_UPDATE_ID=$( echo "${updateJSON}" | jq ".result | [select(.[].message.text==\"/start\")][] | .[-1].update_id" )
    if [[ -z "${CHAT_ID}" ]] || [[ -z "${ADMIN_ID}" ]] || [[ -z "${LAST_UPDATE_ID}" ]]; then
      sleep "$CHECK_INTERVAL"
    else 
      sed -i "s/^CHAT_ID=.*/CHAT_ID=$CHAT_ID/" $WATCHDOG_CONF_FILE
      sed -i "s/^ADMIN_ID=.*/ADMIN_ID=$ADMIN_ID/" $BOT_CONF_FILE
      sed -i "s/^LAST_UPDATE_ID=.*/LAST_UPDATE_ID=$LAST_UPDATE_ID/" $BOT_CONF_FILE
    fi
  done
}

function setCommandList() {
  declare -a commandsList
  commandsList=("status=get system status"
              "uptime=call uptime"
              "df=call df -h"
              "reboot=reboot server"
              "shutdown=shutdown server"
              "restartservice=restart lista_bot.service"
              "help=show commands list"
             )
  telegram.bot -bt "${BOT_TOKEN}" --set_commands "${commandsList[@]}"
}

function main() {
  loadConfig
  local nextUpdateId
  nextUpdateId=$((LAST_UPDATE_ID+1))
  local attackCount
  attackCount=0

  # start the bot loop for continuously checking for updates on the telegram channel
  telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --text "Awaiting orders\!"
  while :
  do
    # check if there is a new update on telegram
    local updateJSON
    updateJSON=$( telegram.bot -bt "${BOT_TOKEN}" -q --get_updates --timeout ${TIMEOUT} --offset ${nextUpdateId} )
    local result
    result=$( echo "${updateJSON}" | jq '.result' )

    if [ -n "${updateJSON}" ] && [ "${result}" != "[]" ]; then
      # the bot received an update
      # parse the received JSON data
      local lastUpdateID
      lastUpdateID=$( echo "${updateJSON}" | jq '.result | .[0].update_id' )
      local adminID
      adminID=$( echo "${updateJSON}" | jq '.result | .[0].message.from.id' )
      # no matter if this request was legitimate, the nextUpdateId has to be increased, for not receiving this update again
      local nextUpdateId
      nextUpdateId=$((lastUpdateID+1))
      sed -i "s/^LAST_UPDATE_ID=.*/LAST_UPDATE_ID=$lastUpdateID/" $BOT_CONF_FILE
      if [[ "${adminID}" == "${ADMIN_ID}" ]]; then
        # this is an authorized request. Process it.
        local message
        message=$( echo "${updateJSON}" | jq '.result | .[0].message.text' )
        message="${message%\"}" 
        message="${message#\"}"
        declare -a command
        IFS=" " read -r -a command <<< "$message"
        #local cmdArray=($( ${command[0]}))
        case "${command[0]}" in
          /help)
            read -r -d '' helpText <<-'TXTEOF'
              /setdisklimit [VALUE] - set the alert threshold for disk usage to [VALUE]
              /setcpulimit [VALUE] - set the alert threshold for cpu usage to [VALUE]
              /setramlimit [VALUE] - set the alert threshold for ram usage to [VALUE]
              /setcheckinterval [VALUE] - set the time interval in which the watchdog checks the limits to [VALUE] seconds
              /status - get system status information
              /uptime - send the output of uptime
              /df - send the output of df -h"
              /reboot - reboot server
              /shutdown - shutdown server
              /restartservice - restart lista_bot.service
              /help - shows this info
TXTEOF
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --question --title "help" --text "${helpText}"
          ;;
          /setdisklimit|/setcpulimit|/setramlimit)
            local new_value
            new_value="${command[1]}"
            if [[ -z "${new_value}" ]] || \
               [[ "${new_value}" =~ ^[0-9]{1,3}$ ]] || \
               [[ "${new_value}" -lt 0 ]] || \
               [[ "${new_value}" -gt 100 ]]; then
              telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --warning --title "error" --text "The argument \"${new_value}\" cannot be used as parameter for ${command[0]}. Make sure you send an integer value between 0 and 100."
            else
              local VARIABLE_TO_SET=""
              case "${command[0]}" in
                /setdisklimit)
                  VARIABLE_TO_SET="DISK_LIMIT"
                ;;
                /setcpulimit)
                  VARIABLE_TO_SET="CPU_LIMIT"
                ;;
                /setramlimit)
                  VARIABLE_TO_SET="RAM_LIMIT"
                ;;
              esac
              sed -i "s/^${VARIABLE_TO_SET}=.*/${VARIABLE_TO_SET}=${new_value}/" $WATCHDOG_CONF_FILE
              telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --text "${VARIABLE_TO_SET} set to ${new_value}"
            fi
          ;;
          /setcheckinterval)
            local new_value
            new_value="${command[1]}"
            if [[ -z "${new_value}" ]] || \
               [[ "${new_value}" =~ ^[0-9]{1,3}$ ]] || \
               [[ "${new_value}" -lt 0 ]] || \
               [[ "${new_value}" -gt 100 ]]; then
              telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --warning --title "error" --text "The argument \"${new_value}\" cannot be used as parameter for ${command[0]}. Make sure you send an integer value between 0 and 100."
            else
              sed -i "s/^CHECK_INTERVAL=.*/CHECK_INTERVAL=${new_value}/" $WATCHDOG_CONF_FILE
              telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --text "CHECK_INTERVAL set to ${new_value}"
            fi
          ;;
          /reboot)
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --text "condocam\.ai will reboot now"
            sudo reboot -f
          ;;
          /shutdown)
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --text "condocam\.ai will shutdown now"
            sudo shutdown now
          ;;
          /restart)
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --text "motioneye\.service will be restarted"
            sudo systemctl restart lista_watchdog.service
          ;;
          /status)
            local cpuTemp
            cpuTemp=$( vcgencmd measure_temp | grep -oE '[0-9]*\.[0-9]*')"°C"
            local status
            status="*CPU temp:* ${cpuTemp}"
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --title "status" --text "${status}"
          ;;
          /uptime)
            local text
            text=$( uptime )
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --title "uptime" --text "${text}"
          ;;
          /df)
            local text
            text=$( df -h )
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --title "disk usage" --text "${text}"
          ;;
          /start)
            # nothing to do, but it is a telegram bot default command, so I should catch it
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --text "Awaiting orders\!"
          ;;
          *)
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --title "unknown command" --text "command \"${command[0]}\" not understood"
          ;;
        esac
      else
        # unauthorized request
        attackCount=$((attackCount+1))
        if [[ $attackCount -ge $ATTACK_LIMIT ]]; then
          telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --error --title "ALARM" --text "I am receiving unauthorized requests\. I am shutting myself down\."
          sleep 5
          exit 0 # indicate no failure, so that the service does not get restarted
        fi
      fi
    fi # else the getUpdate just timed out, start waiting again
  done
  # we should not end up here
  telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --warning --text "I'm done for now\! Service script exited\."

}

main "$@"