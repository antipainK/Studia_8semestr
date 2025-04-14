#!/bin/sh
# SPDX-FileCopyrightText: 2021 Splunk, Inc. <sales@splunk.com>
# SPDX-License-Identifier: Apache-2.0

# shellcheck disable=SC1091
. "$(dirname "$0")"/common.sh

HEADER='Filesystem\tType\tSize\tUsed\tAvail\tUsePct\tINodes\tIUsed\tIFree\tIUsePct\tOSName\tOS_version\tIP_address\tMountedOn'
HEADERIZE='/^Filesystem/ {print header; next}'
# shellcheck disable=SC2016
PRINTF='{printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, OSName, OS_version, IP_address, $11}'
FILL_DIMENSIONS='{length(IP_address) || IP_address = "?";length(OS_version) || OS_version = "?";length(OSName) || OSName = "?"}'

if [ "$KERNEL" = "Linux" ] ; then
    assertHaveCommand df  
    CMD='df -k --output=source,fstype,size,used,avail,pcent,itotal,iused,iavail,ipcent,target'
    if [ ! -f "/etc/os-release" ] ; then
        DEFINE="-v OSName=$(cat /etc/*release | head -n 1| awk -F" release " '{print $1}'| tr ' ' '_') -v OS_version=$(cat /etc/*release | head -n 1| awk -F" release " '{print $2}' | cut -d\. -f1) -v IP_address=$(hostname -I | cut -d\  -f1)"
    else
        DEFINE="-v OSName=$(cat /etc/*release | grep '\bNAME=' | cut -d '=' -f2 | tr ' ' '_' | cut -d\" -f2) -v OS_version=$(cat /etc/*release | grep '\bVERSION_ID=' | cut -d '=' -f2 | cut -d\" -f2) -v IP_address=$(hostname -I | cut -d\  -f1)"
    fi
    FORMAT='{OSName=OSName;OS_version=OS_version;IP_address=IP_address}'
    # shellcheck disable=SC2016
    FILTER_POST='($2 ~ /^(devtmpfs|tmpfs)$/) {next}'
    BEGIN='function rem_pcent(val) {if(substr(val, length(val), 1)=="%") {val=substr(val, 1, length(val)-1); return val}}'
    # shellcheck disable=SC2016
    PRINTF='{match($0,/^(.*[^ ]) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+%) +(.*)$/,a); printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", a[1], a[2], a[3], a[4], a[5], rem_pcent(a[6]), a[7], a[8], a[9], rem_pcent(a[10]), OSName, OS_version, IP_address, a[11]}'
elif [ "$KERNEL" = "SunOS" ] ; then
    assertHaveCommandGivenPath /usr/bin/df
    CMD_1='eval /usr/bin/df -n; /usr/bin/df -g'
    CMD_2='/usr/bin/df -k'
    # shellcheck disable=SC2016
	INODE_FILTER='/^\// {key=$1} /total blocks/ {inodes=$9} /free files/ {ifree=$1} {if(NR%5==0) sub("\\(.*\\)?", "", key); print "INODE:" key, inodes, ifree}'
	CMD="${CMD_1} | ${AWK} '${INODE_FILTER}'; ${CMD_2}"
    DEFINE="-v OSName=$(uname -s) -v OS_version=$(uname -r) -v IP_address=$(ifconfig -a | grep 'inet ' | grep -v 127.0.0.1 | cut -d\  -f2 | head -n 1)"
    FILTER_PRE='/libc_psr/ {next}'
    # shellcheck disable=SC2016
    MAP_FS_TO_TYPE='/INODE:/ {MoInodes[$1] = $2; MoIFree[$1] = $3;  next} /: / {fsTypes[$1] = $2; next}'
    BEGIN='BEGIN { FS = "[ \t]*:?[ \t]+" }'
    # shellcheck disable=SC2016
    FORMAT='{size=$2; used=$3; avail=$4; usePct=$5; mountedOn=$6; $2=fsTypes[mountedOn]; $3=size; $4=used; $5=avail; if(substr(usePct,length(usePct),1)=="%") $6=substr(usePct, 1, length(usePct)-1); else $6=usePct; $7=MoInodes["INODE:"mountedOn]; $9=MoIFree["INODE:"mountedOn]; $8=$7-$9; if($7>0) $10=int(($8*100)/$7); else $10=0;
    OSName=OSName;OS_version=OS_version;IP_address=IP_address; $11=mountedOn}'
    # shellcheck disable=SC2016
    FILTER_POST='($2 ~ /^(devfs|ctfs|proc|mntfs|objfs|lofs|fd|tmpfs)$/) {next} ($1 == "/proc") {next}'
elif [ "$KERNEL" = "AIX" ] ; then
    assertHaveCommandGivenPath /usr/bin/df
	CMD='eval /usr/sysv/bin/df -n ; /usr/bin/df -kP -F %u %f %z %l %n %p %m'
    DEFINE="-v OSName=$(uname -s) -v OSVersion=$(oslevel -r | cut -d'-' -f1) -v IP_address=$(ifconfig -a | grep 'inet ' | grep -v 127.0.0.1 | cut -d\  -f2 | head -n 1)"
    # shellcheck disable=SC2016
    MAP_FS_TO_TYPE='/: / {fsTypes[$1] = $3; next}'
    # shellcheck disable=SC2016
    FORMAT='{size=$2; used=$3; avail=$4; usePct=$5; mountedOn=$9; IUsed=$6; IFree=$7; IUsePct=$8; INodes=$6+$7; $2=fsTypes[mountedOn]; $3=size; $4=used; $5=avail; if(substr(usePct,length(usePct),1)=="%") $6=substr(usePct, 1, length(usePct)-1); else $6=usePct; $7=INodes; $8=IUsed; $9=IFree; if(substr(IUsePct,length(IUsePct),1)=="%") $10=substr(IUsePct, 1, length(IUsePct)-1); else $10=IUsePct; $11=mountedOn; if ($2=="") {$2="?"}; OSName=OSName;OS_version=OSVersion/1000;IP_address=IP_address;}'
    # shellcheck disable=SC2016
    FILTER_POST='($2 ~ /^(proc)$/) {next} ($1 == "/proc") {next}'
elif [ "$KERNEL" = "HP-UX" ] ; then
    assertHaveCommand df
    assertHaveCommand fstyp
    CMD='df -Pk'
    DEFINE="-v OSName=$(uname -s) -v OS_version=$(uname -r) -v IP_address=$(ifconfig -a | grep 'inet ' | grep -v 127.0.0.1 | cut -d\  -f2 | head -n 1)"
    # shellcheck disable=SC2016
    MAP_FS_TO_TYPE='{c="fstyp " $1; c | getline ft; close(c);}'
    # shellcheck disable=SC2016
    FORMAT='{size=$2; used=$3; avail=$4; usePct=$5; mountedOn=$6; $2=ft; $3=size; $4=used; $5=avail; if(substr(usePct,length(usePct),1)=="%") $6=substr(usePct, 1, length(usePct)-1); else $6=usePct; $7=mountedOn; OSName=OSName;OS_version=OS_version;IP_address=IP_address;}'
    # shellcheck disable=SC2016
    FILTER_POST='($2 ~ /^(tmpfs)$/) {next}'
elif [ "$KERNEL" = "Darwin" ] ; then
    assertHaveCommand mount
    assertHaveCommand df
    CMD='eval mount -t nocddafs,autofs,devfs,fdesc,nfs; df -k -T nocddafs,autofs,devfs,fdesc,nfs'
    DEFINE="-v OSName=$(uname -s) -v OS_version=$(uname -r) -v IP_address=$(ifconfig -a | grep 'inet ' | grep -v 127.0.0.1 | cut -d\  -f2 | head -n 1)"
    # shellcheck disable=SC2016
    MAP_FS_TO_TYPE='/ on / {fs=$1; sub("^.*\134(", "", $0); sub(",.*$", "", $0); fsTypes[fs] = $0; next}'
    # shellcheck disable=SC2016
    FORMAT='{size=$2; used=$3; avail=$4; usePct=$5; mountedOn=$9; IUsed=$6; IFree=$7; IUsePct=$8; INodes=$6+$7; for(i=10; i<=NF; i++) mountedOn = mountedOn " " $i; $2=fsTypes[$1]; $3=size; $4=used; $5=avail; if(substr(usePct,length(usePct),1)=="%") $6=substr(usePct, 1, length(usePct)-1); else $6=usePct; $7=INodes; $8=IUsed; $9=IFree; if(substr(IUsePct,length(IUsePct),1)=="%") $10=substr(IUsePct, 1, length(IUsePct)-1); else $10=IUsePct; $11=mountedOn; OSName=OSName;OS_version=OS_version;IP_address=IP_address;}'
    # shellcheck disable=SC2016
    NORMALIZE='{sub("^/dev/", "", $1); sub("s[0-9]+$", "", $1)}'
elif [ "$KERNEL" = "FreeBSD" ] ; then
    assertHaveCommand mount
    assertHaveCommand df
    CMD='eval mount -t nodevfs,nonfs,noswap,nocd9660; df -ik -t nodevfs,nonfs,noswap,nocd9660'
    DEFINE="-v OSName=$(uname -s) -v OS_version=$(uname -r) -v IP_address=$(ifconfig -a | grep 'inet ' | grep -v 127.0.0.1 | cut -d\  -f2 | head -n 1)"
    # shellcheck disable=SC2016
    MAP_FS_TO_TYPE='/ on / {fs=$1; sub("^.*\134(", "", $0); sub(",.*$", "", $0); fsTypes[fs] = $0; next}'
    # shellcheck disable=SC2016
    FORMAT='{size=$2; used=$3; avail=$4; usePct=$5; mountedOn=$9; IUsed=$6; IFree=$7; IUsePct=$8; INodes=$6+$7; $2=fsTypes[$1]; $3=size; $4=used; $5=avail; if(substr(usePct,length(usePct),1)=="%") $6=substr(usePct, 1, length(usePct)-1); else $6=usePct; $7=INodes; $8=IUsed; $9=IFree; if(substr(IUsePct,length(IUsePct),1)=="%") $10=substr(IUsePct, 1, length(IUsePct)-1); else $10=IUsePct; $11=mountedOn; OSName=OSName;OS_version=OS_version;IP_address=IP_address;}'
fi
# shellcheck disable=SC2086
$CMD | tee "$TEE_DEST" | $AWK $DEFINE "$BEGIN $HEADERIZE $FILTER_PRE $MAP_FS_TO_TYPE $FORMAT $FILTER_POST $NORMALIZE $FILL_DIMENSIONS $PRINTF" header="$HEADER"
echo "Cmd = [$CMD];  | $AWK $DEFINE '$BEGIN $HEADERIZE $FILTER_PRE $MAP_FS_TO_TYPE $FORMAT $FILTER_POST $NORMALIZE $FILL_DIMENSIONS $PRINTF' header=\"$HEADER\"" >>"$TEE_DEST"
