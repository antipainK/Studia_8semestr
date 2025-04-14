#!/bin/sh
# SPDX-FileCopyrightText: 2021 Splunk, Inc. <sales@splunk.com>
# SPDX-License-Identifier: Apache-2.0

# shellcheck disable=SC1091
. "$(dirname "$0")"/common.sh

if [ "$KERNEL" = "Linux" ] ; then
	assertHaveCommand date
	assertHaveCommand yum
	
	CMD='eval date ; yum check-update'
	# shellcheck disable=SC2016
	PARSE_0='NR==1 {
		DATE=$0
		PROCESS=0
		UPDATES["addons"]=0
		UPDATES["base"]=0
		UPDATES["extras"]=0
		UPDATES["updates"]=0
	}'

	# Skip extraneous text up to first blank line.
	# shellcheck disable=SC2016
	PARSE_1='NR>1 && PROCESS==0 && $0 ~ /^[[:blank:]]*$|^$/ {
		PROCESS=1
	}'
	# shellcheck disable=SC2016
	PARSE_2='NR>1 && PROCESS==1 {
		num = split($0, update_array)
		if (num == 3) {
			# Record the update count
			UPDATES[update_array[3]] = UPDATES[update_array[3]]+1
			printf "%s package=\"%s\" package_type=\"%s\"\n", DATE, update_array[1], update_array[3]		
		} else if (num==2 && update_array[1] != "") {
			printf "%s package=\"%s\"\n", DATE, update_array[1]
		}
	}'
		
	PARSE_3='END {
		TOTALS=""
		for (key in UPDATES) {
			TOTALS=TOTALS key "=" UPDATES[key] " "
		}
		printf "%s %s\n", DATE, TOTALS
	}'
	
	MASSAGE="$PARSE_0 $PARSE_1 $PARSE_2 $PARSE_3"

elif [ "$KERNEL" = "Darwin" ] ; then
	assertHaveCommand date	
	assertHaveCommand softwareupdate
	
	CMD='eval date ; softwareupdate -l'
	# shellcheck disable=SC2016
	PARSE_0='NR==1 {
		DATE=$0
		PROCESS=0
		TOTAL=0
	}'
	
	# If the first non-space character is an asterisk, assume this is the name
	# of the update. Otherwise, print the update.
	# shellcheck disable=SC2016
	PARSE_1='NR>1 && PROCESS==1 && $0 !~ /^[[:blank:]]*$/ {
		if ( $0 ~ /^[[:blank:]]*\*/ ) {
			PACKAGE="package=\"" $2 "\""
			RECOMMENDED=""
			RESTART=""
			TOTAL=TOTAL+1
		} else {
			if ( $0 ~ /recommended/ ) { RECOMMENDED="is_recommended=\"true\"" }
			if ( $0 ~ /restart/ ) { RESTART="restart_required=\"true\"" }
			printf "%s %s %s %s\n", DATE, PACKAGE, RECOMMENDED, RESTART
		}
	}'

	# Use sentinel value to skip all text prior to update list.
	# shellcheck disable=SC2016
	PARSE_2='NR>1 && PROCESS==0 && $0 ~ /found[[:blank:]]the[[:blank:]]following/ { 
		PROCESS=1
	}'
	
	PARSE_3='END {
		printf "%s total_updates=%s\n", DATE, TOTAL
	}'
	
	MASSAGE="$PARSE_0 $PARSE_1 $PARSE_2 $PARSE_3"
	
else
	# Exits
	failUnsupportedScript
fi

$CMD | tee "$TEE_DEST" | $AWK "$MASSAGE"
echo "Cmd = [$CMD];  | $AWK '$MASSAGE'" >> "$TEE_DEST"
