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
CONF_FILE="/etc/listabot/listabot.conf"
BOT_TOKEN=""
CHAT_ID=""
DISK_LIMIT=""
CPU_LIMIT=""
RAM_LIMIT=""
CHECK_INTERVAL=""

TIMEOUT=60 # long polling intervall = 10 minutes, but get's currently ignored by the Telegram server
ATTACK_LIMIT=3 # how many unauthorized requests are allowed before the bot shuts down itself

#######################################
# Escape characters used by telegram for textformatting.
# This function should only be used if you do not want to use any formatting
# in your message.
# Globals:
#   None
# Arguments:
#   The string that should be escaped
# Outputs:
#   $1 with all special characters being escaped by \
#######################################
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
#   CONF_FILE
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
  if [[ ! -f "${CONF_FILE}" ]]; then
    echo "File \"${CONF_FILE}\" not found. I can't run without this."
    exit
  fi
  # shellcheck disable=SC1090
  source "${CONF_FILE}"

  # check if all watchdog variables are present
  local conf_complete=true
  local variables=("${BOT_TOKEN}" "${DISK_LIMIT}" "${CPU_LIMIT}" "${RAM_LIMIT}" "${CHECK_INTERVAL}")
  local variable
  for variable in "${variables[@]}"; do
    if [[ -z "${variable}" ]]; then
      echo "missing variable ${variable} in ${CONF_FILE}"
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
    local CHAT_ID
    CHAT_ID=$( echo "${update_json}" | jq ".result | [.[].message | select(.text==\"/start\")][-1].chat.id" )
    local ADMIN_ID
    ADMIN_ID=$( echo "${update_json}" | jq ".result | [.[].message | select(.text==\"/start\")][-1].from.id" )
    local LAST_UPDATE_ID
    LAST_UPDATE_ID=$( echo "${update_json}" | jq ".result | [select(.[].message.text==\"/start\")][] | .[-1].update_id" )
    if [[ -z "${CHAT_ID}" ]] || [[ -z "${ADMIN_ID}" ]] || [[ -z "${LAST_UPDATE_ID}" ]]; then
      sleep "$CHECK_INTERVAL"
    else 
      sed -i "s/^CHAT_ID=.*/CHAT_ID=$CHAT_ID/" "${CONF_FILE}"
      sed -i "s/^ADMIN_ID=.*/ADMIN_ID=$ADMIN_ID/" "${CONF_FILE}"
      sed -i "s/^LAST_UPDATE_ID=.*/LAST_UPDATE_ID=$LAST_UPDATE_ID/" "${CONF_FILE}"
    fi
  done
}

function setCommandList() {
  declare -a commandsList
  commandsList=("status=system status"
              "gcl=CPU load Top 5"
              "gru=RAM usage Top 5"
              "uptime=uptime"
              "df=df -h"
              "reboot=reboot server"
              "shutdown=shutdown server"
              "restartservice=restart lista_bot.service"
              "gconf=get the config file"
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
  # make sure that the command list is set in the bot
  setCommandList
  # start the bot loop for continuously checking for updates on the telegram channel
  telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --text "lista\_bot is running\!"
  while :
  do
    # check if there is a new update on telegram
    local updateJSON
    updateJSON=$( telegram.bot -bt "${BOT_TOKEN}" -q --get_updates --timeout ${TIMEOUT} --offset ${nextUpdateId} )
    local result
    result=$( echo "${updateJSON}" | jq '.result' )

    if [[ -n "${updateJSON}" ]] && [[ "${result}" != "[]" ]] && [[ "${result}" != "null" ]]; then
      # the bot received an update
      # parse the received JSON data
      local lastUpdateID
      lastUpdateID=$( echo "${updateJSON}" | jq '.result | .[0].update_id' )
      if [[ -z ${lastUpdateID} ]] || [[ ! ${lastUpdateID} =~ ^(-)?[0-9]+$ ]]; then
        # there seems to be a problem in commuication with Telegram servers
        # sleep to avoid busy waiting and then continue from top
        sleep 1
        continue
      fi
      sed -i "s/^LAST_UPDATE_ID=.*/LAST_UPDATE_ID=$lastUpdateID/" "${CONF_FILE}"
      local adminID
      adminID=$( echo "${updateJSON}" | jq '.result | .[0].message.from.id' )
      # no matter if this request was legitimate, the nextUpdateId has to be increased, for not receiving this update again
      local nextUpdateId
      nextUpdateId=$((lastUpdateID+1))
      if [[ "${adminID}" == "${ADMIN_ID}" ]]; then
        # this is an authorized request. Process it.
        local message
        message=$( echo "${updateJSON}" | jq '.result | .[0].message.text' )
        message="${message%\"}" 
        message="${message#\"}"
        declare -a command
        IFS=" " read -r -a command <<< "$message"
        case "${command[0]}" in
          /help)
            read -r -d '' helpText <<'TXTEOF'
/setdisklimit [VALUE] - set the alert threshold for disk usage to [VALUE] percent. Only integers allowed. 
  Short /sdl
/setcpulimit [VALUE] - set the alert threshold for cpu usage to [VALUE] percent. Only integers allowed.
  Short /scl
/setramlimit [VALUE] - set the alert threshold for ram usage to [VALUE] percent. Only integers allowed.
  Short /srl
/setcheckinterval [VALUE] - set the time interval in which the watchdog checks the limits to [VALUE] seconds.
  Short /sci
/getcpuloadtopx [VALUE1] [VALUE2]- get the [VALUE1] processes causing the highest CPU load. 
  If omitted, [VALUE1] defaults to 5. You can pass [VALUE2] to set the line width of the output.
  [VALUE2] defaults to 120.
  Short /gcl
/getramusagetopx [VALUE1] [VALUE2] - get the [VALUE1] processes having the highest RAM usage.
  If omitted, [VALUE1] defaults to 5. You can pass [VALUE2] to set the line width of the output.
  [VALUE2] defaults to 120.
  Short /gru
/status - get system status information
/uptime - send the output of uptime
/gcl - get CPU load Top 5
/gru - get RAM usage Top 5
/df - send the output of df -h"
/reboot - reboot server
/shutdown - shutdown server
/restartservice - restart lista_bot.service
/getconfig - get the content of ${CONF_FILE}
  Short /gconf
/help - shows this info
TXTEOF
            helpText=$( escapeReservedCharacters "${helpText}" )
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --title "Available Commands" --text "${helpText}"
          ;;
          /setdisklimit|/sdl|/setcpulimit|/scl|/setramlimit|/srl)
            local new_value
            new_value="${command[1]:-}"
            if [[ -z "${new_value}" ]] || \
               [[ ! "${new_value}" =~ ^[0-9]{1-3}$ ]] || \
               [[ "${new_value}" -gt 100 ]]; then
              telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --warning --title "error" --text "The argument \"${new_value}\" cannot be used as parameter for ${command[0]}. Make sure you send an integer value between 0 and 100."
            else
              local VARIABLE_TO_SET=""
              case "${command[0]}" in
                /setdisklimit|/sdl)
                  VARIABLE_TO_SET="DISK_LIMIT"
                ;;
                /setcpulimit|/scl)
                  VARIABLE_TO_SET="CPU_LIMIT"
                ;;
                /setramlimit|/srl)
                  VARIABLE_TO_SET="RAM_LIMIT"
                ;;
              esac
              sed -i "s/^${VARIABLE_TO_SET}=.*/${VARIABLE_TO_SET}=${new_value}/" "${CONF_FILE}"
              telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --text "${VARIABLE_TO_SET//\_/\\\_} set to ${new_value}"
            fi
          ;;
          /setcheckinterval|/sci)
            local new_value
            new_value="${command[1]:-}"
            if [[ -z "${new_value}" ]] || \
               [[ ! "${new_value}" =~ ^[0-9]+$ ]]; then
              telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --warning --title "error" --text "The argument \"${new_value}\" cannot be used as parameter for ${command[0]}. Make sure you send an integer value."
            else
              sed -i "s/^CHECK_INTERVAL=.*/CHECK_INTERVAL=${new_value}/" "${CONF_FILE}"
              telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --text "CHECK\_INTERVAL set to ${new_value}"
              # lista_watchdog.service might be sleeping in a long interval, restart it to apply the new check interval imediately
              sudo systemctl restart lista_watchdog.service
            fi
          ;;
          /getcpuloadtopx|/gcl)
            local num_entries
            num_entries="${command[1]:-5}"
            local line_width
            line_width="${command[2]:-120}"
            if [[ -z "${num_entries}" ]] || \
               [[ ! "${num_entries}" =~ ^[0-9]+$ ]] || \
               [[ -z "${line_width}" ]] || \
               [[ ! "${line_width}" =~ ^[0-9]+$ ]]; then
              telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --warning --title "error" --text "The argument \"${command[1]:-} ${command[2]:-}\" cannot be used as parameter for ${command[0]}. Make sure you send only positive integer values."
            else
              local cpuload
              cpuload=$( lista.sh --cpuloadtopx "${num_entries}" --linewidth "${line_width}" )
              cpuload=$( escapeReservedCharacters "${cpuload}" )
              telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --title "CPU Load Top ${num_entries}" --text "\`\`\`\n${cpuload}\n\`\`\`"
            fi
          ;;
          /getramusagetopx|/gru)
            local num_entries
            num_entries="${command[1]:-5}"
            local line_width
            line_width="${command[2]:-120}"
            if [[ -z "${num_entries}" ]] || \
               [[ ! "${num_entries}" =~ ^[0-9]+$ ]] || \
               [[ -z "${line_width}" ]] || \
               [[ ! "${line_width}" =~ ^[0-9]+$ ]]; then
              telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --warning --title "error" --text "The argument \"${command[1]:-} ${command[2]:-}\" cannot be used as parameter for ${command[0]}. Make sure you send only positive integer values."
            else
              local cpuload
              cpuload=$( lista.sh --ramusagetopx "${num_entries}" --linewidth "${line_width}" )
              cpuload=$( escapeReservedCharacters "${cpuload}" )
              telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --title "RAM Usage Top ${num_entries}" --text "\`\`\`\n${cpuload}\n\`\`\`"
            fi
          ;;
          /reboot)
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --text "rebooting the server now"
            sudo reboot -f
          ;;
          /getconfig|/gconf)
            #config=$( <${CONF_FILE} )
            config=$( grep -v "^#" ${CONF_FILE} )
            config=$( escapeReservedCharacters "${config}" )
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --title "${CONF_FILE}" --text "${config}"
          ;;
          /shutdown)
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --text "shutting down the server now"
            sudo shutdown now
          ;;
          /restartservice)
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --text "restarting lista_watchdog\.service"
            sudo systemctl restart lista_bot.service
          ;;
          /status|/systemstatus)
            #local systemTemps
            #systemTemps=$( paste <(cat /sys/class/thermal/thermal_zone*/type) <(cat /sys/class/thermal/thermal_zone*/temp) | awk '{printf "%-16s %02.1f°C\n", $1, $2/1000}' )
            #systemTemps=$( escapeReservedCharacters "${systemTemps}" )
            #local status
            #status="*System Temperatures:*\n ${systemTemps}"
            local status
            status=$( lista.sh --status )
            status=$( escapeReservedCharacters "${status}" )
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --title "status" --text "\`\`\`\n${status}\n\`\`\`"
          ;;
          /uptime)
            local text
            text=$( uptime )
            text=$( escapeReservedCharacters "${text}" )
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --title "uptime" --text "\`\`\`\n${text}\n\`\`\`"
          ;;
          /df)
            local text
            text=$( df -h )
            text=$( escapeReservedCharacters "${text}" )
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --title "df -h" --text "\`\`\`\n${text}\n\`\`\`"
          ;;
          /start)
            # nothing to do, but it is a telegram bot default command, so I should catch it
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --text "Already running, ignoring /start command\!"
          ;;
          *)
            telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --info --title "unknown command" --text "command \"${command[0]}\" not understood"
          ;;
        esac
      else
        # unauthorized request
        attackCount=$((attackCount+1))
        local json
        json=$( escapeReservedCharacters "${updateJSON}" )
        telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --error --title "ALARM" --text "Unauthorized request\.\n\`\`\`${json}\n\`\`\`"
        if [[ $attackCount -ge $ATTACK_LIMIT ]]; then
          telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --error --title "ALARM" --text "I am receiving unauthorized requests\. I am shutting myself down\."
          sleep 5
          exit 0 # indicate no failure, so that the service does not get restarted
        fi
      fi
    else
      # Either the getUpdate just timed out, or there is a problem in commuication with Telegram servers
      # sleep to avoid busy waiting and then continue from top
      sleep 1
    fi # end process getUpdate
    
  done
  # we should not end up here
  telegram.bot -bt "${BOT_TOKEN}" -cid "${CHAT_ID}" -q --warning --text "I'm done for now\! Service script exited\."

}

main "$@"