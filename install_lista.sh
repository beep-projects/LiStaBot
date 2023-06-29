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
# Install files from the LiStaBot project
# ---------------------------------------------------

set -o noclobber  # Avoid overlay files (echo "hi" > foo)
set -o errexit    # Used to exit upon error, avoiding cascading errors
set -o pipefail   # Unveils hidden failures
set -o nounset    # Exposes unset variables

# Initialize all the option variables.
# This ensures we are not contaminated by variables from the environment.
WATCHDOG_CONF_FILE="lista_watchdog.conf"
BOT_CONF_FILE="lista_bot.conf"


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
  install.sh: script to install scripts from the LiStaBot project
    Main parameters are :
  Options are :
    -h/-?/--help           display this help and exit
    -bt|-token|--bottoken  the telegram API bot token to use, mandatory
                           when installing --bot or --watchdog
    -cid|--chatid          the chat id to use for sending messages to
    --bot                  install lista.sh, the bot and the watchdog
    --watchdog             install the lista.sh and the watchdog
    --lista                install only lista.sh
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
# Checks if internet can be accessed
# and waits until they become available. 
# Warning, you might get stuck forever in here
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
#######################################
function waitForInternet() {
  until nc -zw1 google.com 443 >/dev/null 2>&1;  do
    #wget should be available on most Linux distributions
    if wget -q --spider http://google.com; then
      break # we are online
    else
      #we are still offline
      echo ["$(date +%T)"] waiting for internet access ...
      sleep 1
    fi
  done
}


#######################################
# Try to obtain the chat_id from messages with command /start.
# If such a message is not received, this function will loop indefenitely.
# Globals:
#   None
# Arguments:
#   bot_token the bot token used to check for update holding the check id 
# Outputs:
#   the chat id of the last update for bot_id containing the /start command
#######################################
function getChatID() {
  local bot_token="${1}"
  local chat_id
  local admin_id
  local last_update_id
  local update_json
  if [[ ! ${bot_token} =~ ^[0-9]{8,10}:[0-9a-zA-Z_-]{35}$ ]]; then
    error "\"${bot_token}\" does not seem to be a valid bot token, getChatID() cannot work with this. Please check why this error happened."
  fi
  while [[ -z "${chat_id}" ]]; do
    update_json=$( telegram.bot --get_updates --bottoken "${bot_token}" )
    chat_id=$( echo "${update_json}" | jq ".result | [.[].message | select(.text==\"/start\")][-1].chat.id" )
    admin_id=$( echo "${update_json}" | jq ".result | [.[].message | select(.text==\"/start\")][-1].from.id" )
    last_update_id=$( echo "${update_json}" | jq ".result | [select(.[].message.text==\"/start\")][] | .[-1].update_id" )
    if [[ -z "${chat_id}" ]] || [[ -z "${admin_id}" ]] || [[ -z "${LAST_UPDATE_ID}" ]]; then
      echo "please send /start to bot #${bot_token}, I am still waiting ..."
      sleep 10
    else #TODO check the globals for these files
      sed -i "s/^CHAT_ID=.*/CHAT_ID=$chat_id/" $WATCHDOG_CONF_FILE
      sed -i "s/^ADMIN_ID=.*/ADMIN_ID=$admin_id/" $BOT_CONF_FILE
      sed -i "s/^LAST_UPDATE_ID=.*/LAST_UPDATE_ID=$last_update_id/" $BOT_CONF_FILE
    fi
  done
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
  local bot=false
  local watchdog=false
  local lista=false
  local bot_token=""
  local client_id=""
  
  while :; do
    case ${1:-} in
      -h|-\?|--help)
        help # show help for this script
        exit 0
      ;;
      -bt|-token|--bottoken)
        # test if bot token is valid
        if [[ ${2:-} =~ ^[0-9]{8,10}:[0-9a-zA-Z_-]{35}$ ]]; then
          bot_token=${2}
          shift
        else
          error "\"${2:-}\" does not seem to be a valid bot token, please correct your input"
        fi
      ;;
      -cid|--chatid)
        # test if chat id is valid
        if [[ ${2:-} =~ ^(-)?[0-9]+$ ]]; then
          chat_id=${2}
          shift
        else
          error "\"${2:-}\" does not seem to be a valid chat_id, please correct your input"
        fi
      ;;
      --bot)
        bot=true
        watchdog=true
        lista=true
      ;;
      --watchdog)
        watchdog=true
        lista=true
      ;;
      --lista)
        lista=true
      ;;
      --) # End of all options.
        shift
        break
      ;;
      -?*)
        printf '[install_lista.sh] WARN: Unknown option (ignored): %s\n' "$1" >&2
      ;;
      *) # Default case: No more options, so break out of the loop.
      break
    esac
    shift
  done

  if [[ -n "${bot_token}" ]]; then
    sed -i "s/^BOT_TOKEN=.*/BOT_TOKEN=${bot_token}/" "${WATCHDOG_CONF_FILE}"
  fi

  if [[ -n "${client_id}" ]]; then
    sed -i "s/^CHAT_ID=.*/CHAT_ID=${client_id}/" "${WATCHDOG_CONF_FILE}"
  fi

  if [[ "${watchdog}" = true ]]; then
    if ! command -v telegram.bot &> /dev/null; then
        # install dependency telegram.bot
        waitForInternet
        wget https://github.com/beep-projects/telegram.bot/releases/latest/download/telegram.bot
        chmod 755 telegram.bot
        sudo ./telegram.bot --install
    fi
    # validate BOT_TOKEN
    bot_token=$( grep -w "BOT_TOKEN" "${WATCHDOG_CONF_FILE}" | cut -d"=" -f2 )
    if [[ ! ${bot_token} =~ ^[0-9]{8,10}:[0-9a-zA-Z_-]{35}$ ]]; then
      # without a valid BOT_TOKEN, the lista_watchdog.sh cannot send messages and is useless
      # print this information and exit the install script
      error "\"${bot_token}\" does not seem to be a valid bot token, please correct your entry in ${WATCHDOG_CONF_FILE} and try again"
    fi
    # validate CHAT_ID
    chatid_id=$( grep -w "CHAT_ID" "${WATCHDOG_CONF_FILE}" | cut -d"=" -f2 )
    if [[ ! ${chatid_id} =~ ^(-)?[0-9]+$ ]]; then
      echo "\"${chatid_id}\" does not seem to be a valid chat id, please send /start to your bot now. The install script will then get the chat id from your message"
      getChatId "${bot_token}"
    fi
    sed -i "s/^CHAT_ID=.*/CHAT_ID=${chatid_id}/" "${WATCHDOG_CONF_FILE}"
    # copy the files to their apropriate locations and enable the lista_watchdog.service
    sudo cp "${WATCHDOG_CONF_FILE}" /etc/listabot/
    sudo cp lista_watchdog.sh /usr/local/bin/
    sudo cp lista_watchdog.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable lista_watchdog.service
  fi

  if [[ "${bot}" = true ]]; then
    admin_id=$( grep -w "ADMIN_ID" "${BOT_CONF_FILE}" | cut -d"=" -f2 )
    if [[ -z "${admin_id}" ]]; then
      echo "The ADMIN_ID is not set, please send /start to your bot now. The install script will then get the ADMIN_ID from your message"
      getChatId "${bot_token}"
    fi
    sudo cp lista_bot.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable lista_bot.service
  fi

  if [[ "${lista}" = true ]]; then
    sudo cp lista.sh /usr/local/bin
  fi
}

main "$@"


