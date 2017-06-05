#!/bin/bash
# Adds user to list of authorised users.

# get text from environment variable, squeeze delims and shove into array
text=($( echo "${HEADBOY_TEXT}" | tr -s ' ' ))
# user id is the first arg
user_id="${text[1]}"

# no user id supplied
if [ -z $user_id ] ; then
	echo "Usage: /newuser <user_id>"
	exit 1
fi

user_id="$(tr -dc [:digit:] <<< "$user_id" | head -c 64)"
# user id invalid
if [ -z $user_id ] ; then
	echo "Invalid user id: $user_id"
	exit 1
fi

if ! grep -q "$user_id" "auth_users.txt" ; then
	echo "$user_id" >> "auth_users.txt"
	echo "User $user_id added to authorised users"
else
	echo "User $user_id already authorised"
fi

exit 0