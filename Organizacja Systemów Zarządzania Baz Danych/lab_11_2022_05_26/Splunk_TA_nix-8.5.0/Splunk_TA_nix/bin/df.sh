#!/bin/sh
# SPDX-FileCopyrightText: 2021 Splunk, Inc. <sales@splunk.com>
# SPDX-License-Identifier: Apache-2.0

# shellcheck disable=SC1091
. "$(dirname "$0")"/common.sh

HEADER='Filesystem\tType\tSize\tUsed\tAvail\tUsePct\tINodes\tIUsed\tIFree\tIUsePct\tMountedOn'
# shellcheck disable=SC2016
HEADERIZE='{if (NR==1) {$0 = header}}'
# shellcheck disable=SC2016
PRINTF='{printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11}'

if [ "$KERNEL" = "Linux" ] ; then
	assertHaveCommand df
	CMD='df -h --output=source,fstype,size,used,avail,pcent,itotal,iused,iavail,ipcent,target'
	# shellcheck disable=SC2016
	HEADERIZE='{if (NR==1) {$0 = header; printf header"\n"; {next}}}'
	# shellcheck disable=SC2016
	FILTER_POST='($2 ~ /^(devtmpfs|tmpfs)$/) {next}'
	# shellcheck disable=SC2016
	PRINTF='{match($0,/^(.*[^ ]) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+%) +(.*)$/,a); printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", a[1],a[2],a[3],a[4],a[5],a[6],a[7],a[8],a[9],a[10],a[11];}'

elif [ "$KERNEL" = "SunOS" ] ; then
	assertHaveCommandGivenPath /usr/bin/df
	if [ "$SOLARIS_8" = "true" ] ; then
		CMD_1='eval /usr/bin/df -n ; /usr/bin/df -g'
		CMD_2='/usr/bin/df -k'
		# shellcheck disable=SC2016
		NORMALIZE='function fromKB(KB) {MB = KB/1024; if (MB<1024) return MB "M"; GB = MB/1024; if (GB<1024) return GB "G"; TB = GB/1024; return TB "T"} {$3=fromKB($3); $4=fromKB($4); $5=fromKB($5)}'
	else
		CMD_1='eval /usr/bin/df -n ; /usr/bin/df -g'
		CMD_2='/usr/bin/df -h'
	fi
	# shellcheck disable=SC2016
	INODE_FILTER='/^\// {key=$1} /total blocks/ {inodes=$9} /free files/ {ifree=$1} {if(NR%5==0) sub("\\(.*\\)?", "", key); print "INODE:" key, inodes, ifree}'
	CMD="${CMD_1} | ${AWK} '${INODE_FILTER}'; ${CMD_2}"
	FILTER_PRE='/libc_psr/ {next}'
	# shellcheck disable=SC2016
	MAP_FS_TO_TYPE='/INODE:/ {MoInodes[$1] = $2; MoIFree[$1] = $3;  next} /: / {fsTypes[$1] = $2; next}'
	HEADERIZE='/^Filesystem/ {print header; next}'
    BEGIN='BEGIN { FS = "[ \t]*:?[ \t]+" }'
	# shellcheck disable=SC2016
	FORMAT='{size=$2; used=$3; avail=$4; usePct=$5; mountedOn=$6; $2=fsTypes[mountedOn]; $3=size; $4=used; $5=avail; $6=usePct; $11=mountedOn; $7=MoInodes["INODE:"mountedOn]; $9=MoIFree["INODE:"mountedOn]; $8=$7-$9; if($7>0) $10=int(($8*100)/$7)"%"; else $10=0}'
	# shellcheck disable=SC2016
	FILTER_POST='($2 ~ /^(devfs|ctfs|proc|mntfs|objfs|lofs|fd|tmpfs)$/) {next} ($1 == "/proc") {next}'
elif [ "$KERNEL" = "AIX" ] ; then
	assertHaveCommandGivenPath /usr/bin/df
	CMD='eval /usr/sysv/bin/df -n ; /usr/bin/df -kP -F %u %f %z %l %n %p %m'
	# shellcheck disable=SC2016
	NORMALIZE='function fromKB(KB) {MB = KB/1024; if (MB<1024) return MB "M"; GB = MB/1024; if (GB<1024) return GB "G"; TB = GB/1024; return TB "T"} {$3=fromKB($3); $4=fromKB($4); $5=fromKB($5)}'
	# shellcheck disable=SC2016
	MAP_FS_TO_TYPE='/: / {fsTypes[$1] = $3; next}'
	HEADERIZE='/^Filesystem/ {print header; next}'
	# shellcheck disable=SC2016
    FORMAT='{size=$2; used=$3; avail=$4; usePct=$5; mountedOn=$9; IUsed=$6; IFree=$7; IUsePct=$8; INodes=$6+$7; $2=fsTypes[mountedOn]; $3=size; $4=used; $5=avail; $6=usePct; $7=INodes; $8=IUsed; $9=IFree; $10=IUsePct; $11=mountedOn; if ($2=="") {$2="?"}}'
	# shellcheck disable=SC2016
	FILTER_POST='($2 ~ /^(proc)$/) {next} ($1 == "/proc") {next}'
elif [ "$KERNEL" = "HP-UX" ] ; then
    assertHaveCommand df
    assertHaveCommand fstyp
    CMD='df -Pk'
	# shellcheck disable=SC2016
    MAP_FS_TO_TYPE='{c="fstyp " $1; c | getline ft; close(c);}'
    HEADERIZE='/^Filesystem/ {print header; next}'
	# shellcheck disable=SC2016
    FORMAT='{size=$2; used=$3; avail=$4; usePct=$5; mountedOn=$6; $2=ft; $3=size; $4=used; $5=avail; $6=usePct; $7=mountedOn}'
	# shellcheck disable=SC2016
    FILTER_POST='($2 ~ /^(tmpfs)$/) {next}'
elif [ "$KERNEL" = "Darwin" ] ; then
	assertHaveCommand mount
	assertHaveCommand df
	CMD='eval mount -t nocddafs,autofs,devfs,fdesc,nfs; df -h -T nocddafs,autofs,devfs,fdesc,nfs'
	# shellcheck disable=SC2016
	MAP_FS_TO_TYPE='/ on / {fs=$1; sub("^.*\134(", "", $0); sub(",.*$", "", $0); fsTypes[fs] = $0; next}'
	HEADERIZE='/^Filesystem/ {print header; next}'
	# shellcheck disable=SC2016
	FORMAT='{size=$2; used=$3; avail=$4; usePct=$5; mountedOn=$9; IUsed=$6; IFree=$7; IUsePct=$8; INodes=$6+$7; for(i=10; i<=NF; i++) mountedOn = mountedOn " " $i; $2=fsTypes[$1]; $3=size; $4=used; $5=avail; $6=usePct; $7=INodes; $8=IUsed; $9=IFree; $10=IUsePct; $11=mountedOn}'
	# shellcheck disable=SC2016
	NORMALIZE='{sub("^/dev/", "", $1); sub("s[0-9]+$", "", $1)}'
elif [ "$KERNEL" = "FreeBSD" ] ; then
	assertHaveCommand mount
	assertHaveCommand df
	CMD='eval mount -t nodevfs,nonfs,noswap,nocd9660; df -ih -t nodevfs,nonfs,noswap,nocd9660'
	# shellcheck disable=SC2016
	MAP_FS_TO_TYPE='/ on / {fs=$1; sub("^.*\134(", "", $0); sub(",.*$", "", $0); fsTypes[fs] = $0; next}'
	HEADERIZE='/^Filesystem/ {print header; next}'
	# shellcheck disable=SC2016
	FORMAT='{size=$2; used=$3; avail=$4; usePct=$5; mountedOn=$9; IUsed=$6; IFree=$7; IUsePct=$8; INodes=$6+$7; $2=fsTypes[$1]; $3=size; $4=used; $5=avail; $6=usePct; $7=INodes; $8=IUsed; $9=IFree; $10=IUsePct; $11=mountedOn}'
fi

$CMD | tee "$TEE_DEST" | $AWK "$BEGIN $HEADERIZE $FILTER_PRE $MAP_FS_TO_TYPE $FORMAT $FILTER_POST $NORMALIZE $PRINTF"  header="$HEADER"
echo "Cmd = [$CMD];  | $AWK '$BEGIN $HEADERIZE $FILTER_PRE $MAP_FS_TO_TYPE $FORMAT $FILTER_POST $NORMALIZE $PRINTF' header=\"$HEADER\"" >> "$TEE_DEST"
