
[![GitHub license](https://img.shields.io/github/license/beep-projects/LiStaBot)](https://github.com/beep-projects/LiStaBot/blob/main/LICENSE) [![shellcheck](https://github.com/beep-projects/LiStaBot/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/beep-projects/LiStaBot/actions/workflows/shellcheck.yml) [![GitHub issues](https://img.shields.io/github/issues/beep-projects/LiStaBot)](https://github.com/beep-projects/SystaPi/issues) [![GitHub forks](https://img.shields.io/github/forks/beep-projects/LiStaBot)](https://github.com/beep-projects/LiStaBot/network) [![GitHub stars](https://img.shields.io/github/stars/beep-projects/LiStaBot)](https://github.com/beep-projects/LiStaBot/stargazers) ![GitHub repo size](https://img.shields.io/github/repo-size/beep-projects/LiStaBot) ![visitors](https://visitor-badge.glitch.me/badge?page_id=beep-projects.LiStaBot)

# LiStaBot

Telegram Bot for monitoring a Linux system. 

You can set limits for disk usage, RAM usage and CPU load. The bot will notify you if a limit is breached

## Content

- [Project Requirements](#project-requirements)
- [Project Files](#project-files)
- [Installation](#installation)
  - [Setup a Telegram bot](#setup-a-telegram-bot)
  - [Run the script](#run-the-script)
- [Bot Commands](#bot-commands)

## <a name="project-requirements"/>Project Requirements

The used script are developed and tested using a bash shell. Following tools (excluding Linux build ins) are used the script, most should be part any common Linux distributions:

- ```awk``` (POSIX)
- ```cut``` (GNU core utils)
- ```df``` (GNU core utils)
- ```free``` (procps-ng)
- ```grep``` (POSIX)
- ```jq```
- ```paste``` (GNU core utils)
- ```ps``` (POSIX)
- ```tail``` (POSIX)
- ```telegram.bot``` (installed if not available)
- ```users``` (GNU core utils)
- ```wget```


## <a name="project-files"/>Project Files
```
    ├── install_lista.sh        # script ot install lista.sh, lista_watchdog.service and lista_bot.service
    ├── LICENSE                 # license for using and editing this software
    ├── lista.sh                # script to get some system information
    ├── lista_bot.service       # service to configure lista_watchdog.service via Telegram
    ├── lista_bot.sh            # shell script started by lista_bot.service
    ├── lista_watchdog.service  # service for priodically checking some system limits and sending alerts via Telegram 
    ├── lista_watchdog.sh       # script started by lista_watchdog.service
    ├── listabot.conf           # configuration file used by lista_bot.sh and lista_watchdog.sh
    └── README.md               # This file
```

## <a name="installation"/>Installation

The installation is done using the script ```install_lista.sh```. But before you start, you need a Telegram API Token for your bot. If you only want to use ```lista.sh```, you can skip this step.

#### <a name="setup-a-telegram-bot"/>Setup a Telegram bot

In order to use the messaging feature, you need a **Telegram** account and app. See the instructions for [telegram.bot](https://github.com/beep-projects/telegram.bot#usage) on how to set this up. After setting up the **Telegram bot** and obtaining your **API Token**, send any message to your bot. 
**Note:** If you do not continue with the installation within the next 24h you have to send a message to your bot again!  
**condocam.ai** will use the first received message to set the  administrator. So this might fail if you use a bot that was added to a group and other people are messaging there. You can change the configured administrator later by editing ```/etc/condocam/condocambotbot.conf``` on the device, but you have to figure out the needed IDs on your own.

#### <a name="run-the-script"/>Run the script

Installation is done via ```install_lista.sh``` . You can select the following options:

```bash
install.sh: script to install scripts from the LiStaBot project
Main parameters are :
  --lista                install only lista.sh
  --watchdog             install lista.sh and the watchdog
  --bot                  install lista.sh, the watchdog and the bot
  -bt|-token|--bottoken  the telegram API bot token to use, mandatory
                         when installing --bot or --watchdog
Options are :
  -h/-?/--help           display this help and exit
  -cid|--chatid          the chat id to use for sending messages to
```

2. Download and unzip the latest release filed from the project page and open a console in the created directory. 
   
   You can also run the following commands in a console:

   ```
   version=$(curl -sI https://github.com/beep-projects/LiStaBot/releases/latest | awk -F '/' '/^location/ {print  substr($NF, 1, length($NF)-1)}')
   wget "https://github.com/beep-projects/LiStaBot/archive/refs/tags/${version}.zip"
   unzip ""${version}.zip"
   cd "telegram.bot-${version#v}"
   ```
   
2. Run the installation script. Note, during installation of ```--bot``` or ```--watchdog```, the script requires you to send ```/start``` to the created Telegram bot. This message will be used to set up communication with your Telegram account.

   ```bash
   chmod 755 install_lista.sh
   # do one of the following
   ./install_lista.sh --lista
   # or
   ./install_lista.sh --watchdog --bottoken 110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw
   # or
   ./install_lista.sh --bot --bottoken 110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw
   ```

3. DONE

## <a name="bot-commands" />LiStaBot commands

The script `lista_bot.sh` is used for communication between you and your bot. During startup the following commands are registered at @BotFather
<sup>(If you have the chat with your bot open after sending ```/start``` to your bot, you have to exit and enter the chat to update the commands quick menu in the Telegram app)</sup>

```bash
/status - get system status information
/uptime - send the output of uptime
/df - send the output of df -h"
/reboot - reboot server
/shutdown - shutdown server
/restartservice - restart lista_bot.service
/help - shows this info
```

In addition to the commands in the quick menu, there are more commands available. Commands with parameters cannot be added to the quick menu, so you have to enter them manually. To make your life easier, the all have a three letter short code

```bash
/setdisklimit [VALUE] - set the alert threshold for disk usage to [VALUE] percent. Only integers allowed. Short /sdl
/setcpulimit [VALUE] - set the alert threshold for cpu usage to [VALUE] percent. Only integers allowed. Short /scl
/setramlimit [VALUE] - set the alert threshold for ram usage to [VALUE] percent. Only integers allowed. Short /srl
/setcheckinterval [VALUE] - set the time interval in which the watchdog checks the limits to [VALUE] seconds. Only integers allowed. Short /sci
```

