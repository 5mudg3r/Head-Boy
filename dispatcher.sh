#!/bin/bash
# Admin bot for controlling maspian remotely through telegram commands.
# Dispatcher which checks for and processes updates from Telegram and dispatches
# them to the appropriate handler script.

################# Logging Function #################
function log() {
	# 1 = log level ( "DEBUG", INFO", "MINOR", "MAJOR", "FATAL")
	# 2 = message
	echo $(date "+%d-%b-%Y %H:%M:%S") "[$1] $2" >> $script_dir/headboy.log
}
################# Setup #################
# walk through any symbolic links to get the absolute path to the directory
script="${BASH_SOURCE[0]}"
while [ -h "$script" ]; do
	script="$(readlink -f "$script")"
done
script_dir="$(dirname "$script")"

offset=$(cat "$script_dir/offset.txt")
admin=$(cat "$script_dir/admin.txt")
token=$(cat "$script_dir/token.txt")
api="https://api.telegram.org/bot$token"

handlers="$script_dir/handlers.txt"

################# Functions: Dispatcher --> API #################
function send_message() {
	# 1 = chat id
	# 2 = text
	curl -s -S \
	--data-urlencode "chat_id=$1" \
	--data-urlencode "text=$2" \
	"$api/sendMessage" \
	> /dev/null
}
function send_reply() {
	# 1 = chat id
	# 2 = text
	# 3 = reply id
	curl -s -S \
	--data-urlencode "chat_id=$1" \
	--data-urlencode "text=$2" \
	--data-urlencode "reply_to_message_id=$3" \
	"$api/sendMessage" \
	> /dev/null
}
function send_busy() {
	# 1 = chat id
	curl -s -S \
	--data-urlencode "chat_id=$1" \
	--data-urlencode "action=typing" \
	"$api/sendChatAction" \
	> /dev/null
}
function send_error() {
	# 1 = log level ("DEBUG", "INFO", "MINOR", "MAJOR", "FATAL")
	# 2 = message
	curl -s -S \
	--data-urlencode "chat_id=$admin" \
	--data-urlencode "text=*[$1]* $2" \
	--data-urlencode "parse_mode=Markdown" \
	"$api/sendMessage" \
	> /dev/null
}

################# Functions: API --> Dispatcher #################
function getUpdates() {
	curl -s -S -G \
	-d "offset=$offset" \
	-d "limit=1" \
	-d "timeout=1" \
	-d "allowed_updates=["message"]" \
	"$api/getUpdates"
}

################# Process an update #################
data=$(getUpdates)
json_data=$( jq -r '.result[]'            <<< "$data")
update_id=$( jq -r ".update_id"           <<< "$json_data")
from_id=$(   jq -r ".message.from.id"     <<< "$json_data")
message_id=$(jq -r ".message.message_id"  <<< "$json_data")
text=$(      jq -r ".message.text"        <<< "$json_data")

if [ -z "$from_id" ] || [ -z "$message_id" ] || [ -z "$text" ] || [ -z "$update_id" ]; then
  exit
fi

((update_id++))
echo $update_id > $script_dir/offset.txt
((update_id--))

if [ -z $(grep "$from_id" "$script_dir/auth_users.txt") ] ; then
	# this user is not authorised to send messages to the bot
	log "INFO" "Unauthorised user sent message to bot! User ID: $from_id"
	send_error "INFO" "Unauthorised user sent message to bot! User ID: $from_id"
	exit
fi

if [ "${text:0:1}" != "/" ]; then
  # this is not a command, so ignore it
  log "DEBUG" "Message not a command: $text"
  exit
fi

# the command is everything up to the first space
command="${text%% *}"
# sanitise the command to strip any silly business, and limit to 64 chars
command="$(tr -dc [:alnum:]'_-' <<< "$command" | head -c 64)"
if [ -z "$command" ]; then
  # this isn't a valid command, so bail
  log "DEBUG" "Command not valid: $text"
  exit
fi

# trim comment lines, find lines with command, and get last appearing match (should be redundant)
handler="$(grep -v "^#" "$handlers" | grep "^$command|" | head -1)"

if [ -z "$handler" ]; then
  # no return, so this is not a command we recognise
  log "DEBUG" "Command not recognised: $text"
  exit
fi

# activate the "is typing..." message
send_busy

# trim away up to the first pipe delimiter to get the command to execute
handler="${handler#*|}"

# export environment variables CGI style
env_prefix="HEADBOY_"
export "$env_prefix"FROM_ID="$from_id"
export "$env_prefix"MESSAGE_ID="$message_id"
export "$env_prefix"TEXT="$text"

# yeah, this will run any code specified as a handler - security awareness is required
reply="$($script_dir/$handler 2>&1)"

send_reply "$from_id" "$reply" "$message_id"
log "DEBUG" "Successful Response: $text --> $reply"
