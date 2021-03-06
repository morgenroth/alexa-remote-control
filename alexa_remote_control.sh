#!/bin/sh
#
# Amazon Alexa Remote Control
#  alex(at)loetzimmer.de
#
# 2017-10-10: v0.1 initial release
# 2017-10-11: v0.2 TuneIn Station Search
# 2017-10-11: v0.2a commands on special device "ALL" are executed on all ECHO+WHA
# 2017-10-16: v0.3 added playback of library tracks
# 2017-10-24: v0.4 added playback information
# 2017-11-21: v0.5 added Prime station and playlist
# 2017-11-22: v0.6 added Prime historical queue and replaced getopts
# 2017-11-25: v0.6a cURL is now configurable
# 2017-11-25: v0.7 added multiroom create/delete, playback of library playlist
# 2017-11-30: v0.7a added US config, fixed device names containing spaces
# 2017-12-07: v0.7b added Bluetooth connect/disconnect
#
###
#
# (no BASHisms were used, should run with any shell)
# - requires cURL for web communication
# - sed and awk for extraction
# - jq as command line JSON parser (optional for the fancy bits)
#
##########################################

EMAIL='amazon_account@email.address'
PASSWORD='Very_Secret_Amazon_Account_Password'

LANGUAGE="de,en"
#LANGUAGE="en-us"

AMAZON='amazon.de'
#AMAZON='amazon.com'

ALEXA='layla.amazon.de'
#ALEXA='pitangui.amazon.com'

# cURL binary
CURL='/usr/bin/curl'

# cURL options
#  -k : if your cURL cannot verify CA certificates, you'll have to trust any
#  --compressed : if your cURL was compiled with libz you may use compression
OPTS='--compressed'
#OPTS='-k --compressed'

###########################################
# nothing to configure below here
#
TMP="/tmp"
COOKIE="${TMP}/.alexa.cookie"
DEVLIST="${TMP}/.alexa.devicelist.json"

GUIVERSION=0

LIST=""
LOGOFF=""
COMMAND=""
STATIONID=""
QUEUE=""
SONG=""
TYPE=""
ASIN=""
SEEDID=""
HIST=""
LEMUR=""
CHILD=""
PLIST=""
BLUETOOTH=""

usage()
{
	echo "$0 [-d <device>|ALL] -e <pause|play|next|prev|fwd|rwd|shuffle|vol:<0-100>> | -b [<\"AA:BB:CC:DD:EE:FF\">] | -q | -r <\"station name\"|stationid> | -s <trackID> | -t <ASIN> |"
	echo "         -u <seedID> | -v <queueID> | -w <playlistId> | -i | -p | -P | -S | -a | -m <multiroom_device> [device_1 .. device_X] | -l | -h"
	echo "   -e : run command"
	echo "   -b : connect/disconnect bluetooth device"
	echo "   -q : query queue"
	echo "   -r : play tunein radio"
	echo "   -s : play library track"
	echo "   -t : play Prime playlist"
	echo "   -u : play Prime station"
	echo "   -v : play Prime historical queue"
	echo "   -w : play library playlist"
	echo "   -i : list imported library tracks"
	echo "   -p : list purchased library tracks"
	echo "   -P : list Prime playlists"
	echo "   -S : list Prime stations"
	echo "   -a : list available devices"
	echo "   -m : delete multiroom and/or create new multiroom containing devices"
	echo "   -l : logoff"
	echo "   -h : help"
}

while [ "$#" -gt 0 ] ; do
	case "$1" in
		-d)
			if [ "${2#-}" != "${2}" -o -z "$2" ] ; then
				echo "ERROR: missing argument for ${1}"
				usage
				exit 1
			fi
			DEVICE=$2
			shift
			;;
		-e)
			if [ "${2#-}" != "${2}" -o -z "$2" ] ; then
				echo "ERROR: missing argument for ${1}"
				usage
				exit 1
			fi
			COMMAND=$2
			shift
			;;
		-b)
			if [ "${2#-}" = "${2}" -a -n "$2" ] ; then
				BLUETOOTH=$2
				shift
			else
				BLUETOOTH="null"
			fi
			;;
		-m)
			if [ "${2#-}" != "${2}" -o -z "$2" ] ; then
				echo "ERROR: missing argument for ${1}"
				usage
				exit 1
			fi
			LEMUR=$2
			shift
			while [ "${2#-}" = "${2}" -a -n "$2" ] ; do
				CHILD="${CHILD} ${2}"
				shift
			done
			;;
		-r)
			if [ "${2#-}" != "${2}" -o -z "$2" ] ; then
				echo "ERROR: missing argument for ${1}"
				usage
				exit 1
			fi
			STATIONID=$2
			shift
			# stationIDs are "s1234" or "s12345"
			if [ -n "${STATIONID##s[0-9][0-9][0-9][0-9]}" -a -n "${STATIONID##s[0-9][0-9][0-9][0-9][0-9]}" ] ; then
				# search for station name
				STATIONID=$(${CURL} ${OPTS} -s --data-urlencode "query=${STATIONID}" -G "https://api.tunein.com/profiles?fullTextSearch=true" | jq -r '.Items[] | select(.ContainerType == "Stations") | .Children[] | select( .Index==1 ) | .GuideId')
				if [ -z "$STATIONID" ] ; then
					echo "ERROR: no Station \"$2\" found on TuneIn"
					exit 1
				fi
			fi
			;;
		-s)
			if [ "${2#-}" != "${2}" -o -z "$2" ] ; then
				echo "ERROR: missing argument for ${1}"
				usage
				exit 1
			fi
			SONG=$2
			shift
			;;
		-t)
			if [ "${2#-}" != "${2}" -o -z "$2" ] ; then
				echo "ERROR: missing argument for ${1}"
				usage
				exit 1
			fi
			ASIN=$2
			shift
			;;
		-u)
			if [ "${2#-}" != "${2}" -o -z "$2" ] ; then
				echo "ERROR: missing argument for ${1}"
				usage
				exit 1
			fi
			SEEDID=$2
			shift
			;;
		-v)
			if [ "${2#-}" != "${2}" -o -z "$2" ] ; then
				echo "ERROR: missing argument for ${1}"
				usage
				exit 1
			fi
			HIST=$2
			shift
			;;
		-w)
			if [ "${2#-}" != "${2}" -o -z "$2" ] ; then
				echo "ERROR: missing argument for ${1}"
				usage
				exit 1
			fi
			PLIST=$2
			shift
			;;
		-l)
			LOGOFF="true"
			;;
		-a)
			LIST="true"
			;;
		-i)
			TYPE="IMPORTED"
			;;
		-p)
			TYPE="PURCHASES"
			;;
		-P)
			PRIME="prime-playlist-browse-nodes"
			;;
		-S)
			PRIME="prime-sections"
			;;
		-q)
			QUEUE="true"
			;;
		-h|-\?|--help)
			usage
			exit 0
			;;
		*)
			echo "ERROR: unknown option ${1}"
			usage
			exit 1
			;;
	esac
	shift
done

case "$COMMAND" in
	pause)
			COMMAND='{"type":"PauseCommand"}'
			;;
	play)
			COMMAND='{"type":"PlayCommand"}'
			;;
	next)
			COMMAND='{"type":"NextCommand"}'
			;;
	prev)
			COMMAND='{"type":"PreviousCommand"}'
			;;
	fwd)
			COMMAND='{"type":"ForwardCommand"}'
			;;
	rwd)
			COMMAND='{"type":"RewindCommand"}'
			;;
	shuffle)
			COMMAND='{"type":"ShuffleCommand","shuffle":"true"}'
			;;
	vol:*)
			VOL=${COMMAND##*:}
			# volume as integer!
			if [ $VOL -le 100 -a $VOL -ge 0 ] ; then
				COMMAND='{"type":"VolumeLevelCommand","volumeLevel":'${VOL}'}'
			else
				echo "ERROR: volume should be an integer between 0 and 100"
				usage
				exit 1
			fi
			;;
	"")
			;;
	*)
			echo "ERROR: unknown command \"${COMMAND}\"!"
			usage
			exit 1
			;;
esac

#
# Amazon Login
#
log_in()
{
################################################################
#
# following headers are required:
#	Accept-Language	(possibly for determining login region)
#	User-Agent	(cURL wouldn't store cookies without)
#
################################################################

rm -f ${DEVLIST}
rm -f ${COOKIE}
rm -f ${TMP}/.alexa.*.list

#
# get first cookie and write redirection target into referer
#
${CURL} ${OPTS} -s -D "${TMP}/.alexa.header" -c ${COOKIE} -b ${COOKIE} -A "Mozilla/5.0" -H "Accept-Language: ${LANGUAGE}" -H "DNT: 1" -H "Connection: keep-alive" -H "Upgrade-Insecure-Requests: 1" -L\
 https://alexa.${AMAZON} | grep "hidden" | sed 's/hidden/\n/g' | grep "value=\"" | sed -r 's/^.*name="([^"]+)".*value="([^"]+)".*/\1=\2\&/g' > "${TMP}/.alexa.postdata"

#
# login empty to generate sessiion
#
${CURL} ${OPTS} -s -c ${COOKIE} -b ${COOKIE} -A "Mozilla/5.0" -H "Accept-Language: ${LANGUAGE}" -H "DNT: 1" -H "Connection: keep-alive" -H "Upgrade-Insecure-Requests: 1" -L\
 -H "$(grep 'Location: ' ${TMP}/.alexa.header | sed 's/Location: /Referer: /')" -d "@${TMP}/.alexa.postdata" https://www.${AMAZON}/ap/signin | grep "hidden" | sed 's/hidden/\n/g' | grep "value=\"" | sed -r 's/^.*name="([^"]+)".*value="([^"]+)".*/\1=\2\&/g' > "${TMP}/.alexa.postdata2"

#
# login with filled out form
#  !!! referer now contains session in URL
#
${CURL} ${OPTS} -s -c ${COOKIE} -b ${COOKIE} -A "Mozilla/5.0" -H "Accept-Language: ${LANGUAGE}" -H "DNT: 1" -H "Connection: keep-alive" -H "Upgrade-Insecure-Requests: 1" -L\
 -H "Referer: https://www.${AMAZON}/ap/signin/$(awk "\$0 ~/.${AMAZON}.*session-id[\\s\\t]/ {print \$7}" ${COOKIE})" --data-urlencode "email=${EMAIL}" --data-urlencode "password=${PASSWORD}" -d "@${TMP}/.alexa.postdata2" https://www.${AMAZON}/ap/signin > /dev/null

#
# get CSRF
#
${CURL} ${OPTS} -s -c ${COOKIE} -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 https://${ALEXA}/api/language > /dev/null

rm -f "${TMP}/.alexa.header"
rm -f "${TMP}/.alexa.postdata"
rm -f "${TMP}/.alexa.postdata2"
}

#
# get JSON device list
#
get_devlist()
{
${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})"\
 "https://${ALEXA}/api/devices-v2/device?cached=false" > ${DEVLIST}
}

check_status()
{
#
# bootstrap with GUI-Version writes GUI version to cookie
#  returns among other the current authentication state
#
	AUTHSTATUS=$(${CURL} ${OPTS} -s -c ${COOKIE} -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L https://${ALEXA}/api/bootstrap?version=${GUIVERSION} | sed -r 's/^.*"authenticated":([^,]+),.*$/\1/g')

	if [ "$AUTHSTATUS" = "true" ] ; then
		return 1
	fi

	return 0
}

#
# set device specific variables from JSON device list
#
set_var()
{
	DEVICE=$(echo ${DEVICE} | sed -r 's/%20/ /g')
	
	if [ -z "${DEVICE}" ] ; then
		# if no device was supplied, use the first Echo(dot) in device list
		echo "setting default device to:"
		DEVICE=$(jq -r '[ .devices[] | select(.deviceFamily == "ECHO" ) | .accountName] | .[0]' ${DEVLIST})
		echo ${DEVICE}
	fi

	DEVICETYPE=$(jq --arg device "${DEVICE}" -r '.devices[] | select(.accountName == $device) | .deviceType' ${DEVLIST})
	DEVICESERIALNUMBER=$(jq --arg device "${DEVICE}" -r '.devices[] | select(.accountName == $device) | .serialNumber' ${DEVLIST})
	MEDIAOWNERCUSTOMERID=$(jq --arg device "${DEVICE}" -r '.devices[] | select(.accountName == $device) | .deviceOwnerCustomerId' ${DEVLIST})

	if [ -z "${DEVICESERIALNUMBER}" ] ; then
		echo "ERROR: unkown device dev:${DEVICE}"
		exit 1
	fi
}

#
# list available devices from JSON device list
#
list_devices()
{
	jq -r '.devices[].accountName' ${DEVLIST}
}

#
# execute command
#
run_cmd()
{
${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X POST -d ${COMMAND}\
 "https://${ALEXA}/api/np/command?deviceSerialNumber=${DEVICESERIALNUMBER}&deviceType=${DEVICETYPE}"
}

#
# play TuneIn radio station
#
play_radio()
{
${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X POST\
 "https://${ALEXA}/api/tunein/queue-and-play?deviceSerialNumber=${DEVICESERIALNUMBER}&deviceType=${DEVICETYPE}&guideId=${STATIONID}&contentType=station&callSign=&mediaOwnerCustomerId=${MEDIAOWNERCUSTOMERID}"
}

#
# play library track
#
play_song()
{
${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X POST -d "{\"trackId\":\"${SONG}\",\"playQueuePrime\":true}"\
 "https://${ALEXA}/api/cloudplayer/queue-and-play?deviceSerialNumber=${DEVICESERIALNUMBER}&deviceType=${DEVICETYPE}&mediaOwnerCustomerId=${MEDIAOWNERCUSTOMERID}&shuffle=false"
}

#
# play library playlist
#
play_playlist()
{
${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X POST -d "{\"playlistId\":\"${PLIST}\",\"playQueuePrime\":true}"\
 "https://${ALEXA}/api/cloudplayer/queue-and-play?deviceSerialNumber=${DEVICESERIALNUMBER}&deviceType=${DEVICETYPE}&mediaOwnerCustomerId=${MEDIAOWNERCUSTOMERID}&shuffle=false"
}

#
# play PRIME playlist
#
play_prime_playlist()
{
${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X POST -d "{\"asin\":\"${ASIN}\"}"\
 "https://${ALEXA}/api/prime/prime-playlist-queue-and-play?deviceSerialNumber=${DEVICESERIALNUMBER}&deviceType=${DEVICETYPE}&mediaOwnerCustomerId=${MEDIAOWNERCUSTOMERID}"
}

#
# play PRIME station
#
play_prime_station()
{
${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X POST -d "{\"seed\":\"{\\\"type\\\":\\\"KEY\\\",\\\"seedId\\\":\\\"${SEEDID}\\\"}\",\"stationName\":\"none\",\"seedType\":\"KEY\"}"\
 "https://${ALEXA}/api/gotham/queue-and-play?deviceSerialNumber=${DEVICESERIALNUMBER}&deviceType=${DEVICETYPE}&mediaOwnerCustomerId=${MEDIAOWNERCUSTOMERID}"
}

#
# play PRIME historical queue
#
play_prime_hist_queue()
{
${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X POST -d "{\"deviceType\":\"${DEVICETYPE}\",\"deviceSerialNumber\":\"${DEVICESERIALNUMBER}\",\"mediaOwnerCustomerId\":\"${MEDIAOWNERCUSTOMERID}\",\"queueId\":\"${HIST}\",\"service\":null,\"trackSource\":\"TRACK\"}"\
 "https://${ALEXA}/api/media/play-historical-queue"
}

#
# show library tracks
#
show_library()
{
	OFFSET="";
	SIZE=50;
	TOTAL=0;
	FILE=${TMP}/.alexa.${TYPE}.list

	if [ ! -f ${FILE} ] ; then
		echo -n '{"playlist":{"entryList":[' > ${FILE}

		while [ 50 -le ${SIZE} ] ; do

${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X GET \
 "https://${ALEXA}/api/cloudplayer/playlists/${TYPE}-V0-OBJECTID?deviceSerialNumber=${DEVICESERIALNUMBER}&deviceType=${DEVICETYPE}&size=${SIZE}&offset=${OFFSET}&mediaOwnerCustomerId=${MEDIAOWNERCUSTOMERID}" > ${FILE}.tmp

			OFFSET=$(jq -r '.nextResultsToken' ${FILE}.tmp)
			SIZE=$(jq -r '.playlist | .trackCount' ${FILE}.tmp)
			jq -r -c '.playlist | .entryList' ${FILE}.tmp >> ${FILE}
			echo "," >> ${FILE}
			TOTAL=$((TOTAL+SIZE))
		done
		echo "[]],\"trackCount\":\"${TOTAL}\"}}" >> ${FILE}
		rm -f ${FILE}.tmp
	fi
	jq -r '.playlist.trackCount' ${FILE}
	jq '.playlist.entryList[] | .[]' ${FILE}
}

#
# show Prime stations and playlists
#
show_prime()
{
	FILE=${TMP}/.alexa.${PRIME}.list

	if [ ! -f ${FILE} ] ; then
${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X GET \
 "https://${ALEXA}/api/prime/{$PRIME}?deviceSerialNumber=${DEVICESERIALNUMBER}&deviceType=${DEVICETYPE}&mediaOwnerCustomerId=${MEDIAOWNERCUSTOMERID}" > ${FILE}

		if [ "$PRIME" = "prime-playlist-browse-nodes" ] ; then
			for I in $(jq -r '.primePlaylistBrowseNodeList[].subNodes[].nodeId' ${FILE} 2>/dev/null) ; do
${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X GET \
 "https://${ALEXA}/api/prime/prime-playlists-by-browse-node?browseNodeId=${I}&deviceSerialNumber=${DEVICESERIALNUMBER}&deviceType=${DEVICETYPE}&mediaOwnerCustomerId=${MEDIAOWNERCUSTOMERID}" >> ${FILE}
			done
		fi
	fi
	jq '.' ${FILE}
}

#
# current queue
#
show_queue()
{
	PARENT=""
	PARENTID=$(jq --arg device "${DEVICE}" -r '.devices[] | select(.accountName == $device) | .parentClusters[0]' ${DEVLIST})
	if [ "$PARENTID" != "null" ] ; then
		PARENTDEVICE=$(jq --arg serial ${PARENTID} -r '.devices[] | select(.serialNumber == $serial) | .deviceType' ${DEVLIST})
		PARENT="&lemurId=${PARENTID}&lemurDeviceType=${PARENTDEVICE}"
	fi

${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X GET \
 "https://${ALEXA}/api/np/player?deviceSerialNumber=${DEVICESERIALNUMBER}&deviceType=${DEVICETYPE}${PARENT}" | jq '.'

${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X GET \
 "https://${ALEXA}/api/media/state?deviceSerialNumber=${DEVICESERIALNUMBER}&deviceType=${DEVICETYPE}" | jq '.'

${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X GET \
 "https://${ALEXA}/api/np/queue?deviceSerialNumber=${DEVICESERIALNUMBER}&deviceType=${DEVICETYPE}" | jq '.'
}

#
# deletes a multiroom device
#
delete_multiroom()
{
${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X DELETE \
 "https://${ALEXA}/api/lemur/tail/${DEVICESERIALNUMBER}"
}

#
# creates a multiroom device
#
create_multiroom()
{
	JSON="{\"id\":null,\"name\":\"${LEMUR}\",\"members\":["
	for DEVICE in $CHILD ; do
		set_var
		JSON="${JSON}{\"dsn\":\"${DEVICESERIALNUMBER}\",\"deviceType\":\"${DEVICETYPE}\"},"
	done
	JSON="${JSON%,}]}"

${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X POST -d "${JSON}" \
 "https://${ALEXA}/api/lemur/tail"
}

#
# connect bluetooth device
#
connect_bluetooth()
{
${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X POST -d "{\"bluetoothDeviceAddress\":\"${BLUETOOTH}\"}"\
 "https://${ALEXA}/api/bluetooth/pair-sink/${DEVICETYPE}/${DEVICESERIALNUMBER}"
}

#
# disconnect bluetooth device
#
disconnect_bluetooth()
{
${CURL} ${OPTS} -s -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 -H "Content-Type: application/json; charset=UTF-8" -H "Referer: https://alexa.${AMAZON}/spa/index.html" -H "Origin: https://alexa.${AMAZON}"\
 -H "csrf: $(awk '$0 ~/.amazon.de.*csrf[\s\t]/ {print $7}' ${COOKIE})" -X POST \
 "https://${ALEXA}/api/bluetooth/disconnect-sink/${DEVICETYPE}/${DEVICESERIALNUMBER}"
}

#
# logout
#
log_off()
{
${CURL} ${OPTS} -s -c ${COOKIE} -b ${COOKIE} -A "Mozilla/5.0" -H "DNT: 1" -H "Connection: keep-alive" -L\
 https://${ALEXA}/logout > /dev/null

rm -f ${DEVLIST}
rm -f ${COOKIE}
rm -f ${TMP}/.alexa.*.list
}

if [ -z "$BLUETOOTH" -a -z "$LEMUR" -a -z "$PLIST" -a -z "$HIST" -a -z "$SEEDID" -a -z "$ASIN" -a -z "$PRIME" -a -z "$TYPE" -a -z "$QUEUE" -a -z "$LIST" -a -z "$COMMAND" -a -z "$STATIONID" -a -z "$SONG" -a -n "$LOGOFF" ] ; then
	echo "only logout option present, logging off ..."
	log_off
	exit 0
fi

if [ ! -f ${COOKIE} ] ; then
	echo "cookie do not exist. logging in ..."
	log_in
fi

if [ ! -f ${DEVLIST} ] ; then
	echo "device list do not exist. downloading ..."
	get_devlist
fi

check_status
if [ $? -eq 0 ] ; then
	echo "cookie expired, logging in again ..."
	log_in
fi

if [ -n "$COMMAND" -o -n "$QUEUE" ] ; then
	if [ "${DEVICE}" = "ALL" ] ; then
		for DEVICE in $(jq -r '.devices[] | select( .deviceFamily == "ECHO" or .deviceFamily == "WHA") | .accountName' ${DEVLIST} | sed -r 's/ /%20/g') ; do
			set_var
			if [ -n "$COMMAND" ] ; then
				echo "sending cmd:${COMMAND} to dev:${DEVICE} type:${DEVICETYPE} serial:${DEVICESERIALNUMBER}"
				run_cmd
			else
				echo "queue info for dev:${DEVICE} type:${DEVICETYPE} serial:${DEVICESERIALNUMBER}"
				show_queue
			fi
		done
	else
		set_var
		if [ -n "$COMMAND" ] ; then
			echo "sending cmd:${COMMAND} to dev:${DEVICE} type:${DEVICETYPE} serial:${DEVICESERIALNUMBER}"
			run_cmd
		else
			echo "queue info for dev:${DEVICE} type:${DEVICETYPE} serial:${DEVICESERIALNUMBER}"
			show_queue
		fi
	fi
elif [ -n "$LEMUR" ] ; then
	DEVICESERIALNUMBER=$(jq --arg device "${LEMUR}" -r '.devices[] | select(.accountName == $device and .deviceFamily == "WHA") | .serialNumber' ${DEVLIST})
	if [ -n "$DEVICESERIALNUMBER" ] ; then
		delete_multiroom
	else
		if [ -z "$CHILD" ] ; then
			echo "ERROR: ${LEMUR} is no multiroom device. Cannot delete ${LEMUR}".
			exit 1
		fi
	fi
	if [ -z "$CHILD" ] ; then
		echo "Deleted multi room dev:${LEMUR} serial:${DEVICESERIALNUMBER}"
	else
		echo "Creating multi room dev:${LEMUR} member_dev(s):${CHILD}"
		create_multiroom
	fi
	rm -f ${DEVLIST}
	get_devlist
elif [ -n "$BLUETOOTH" ] ; then
	set_var
	if [ "$BLUETOOTH" = "null" ] ; then
		echo "disconnecting dev:${DEVICE} type:${DEVICETYPE} serial:${DEVICESERIALNUMBER} from bluetooth"
		disconnect_bluetooth
	else
		echo "connecting dev:${DEVICE} type:${DEVICETYPE} serial:${DEVICESERIALNUMBER} to bluetooth device:${BLUETOOTH}"
		connect_bluetooth
	fi
elif [ -n "$STATIONID" ] ; then
	set_var
	echo "playing stationID:${STATIONID} on dev:${DEVICE} type:${DEVICETYPE} serial:${DEVICESERIALNUMBER} mediaownerid:${MEDIAOWNERCUSTOMERID}"
	play_radio
elif [ -n "$SONG" ] ; then
	set_var
	echo "playing library track:${SONG} on dev:${DEVICE} type:${DEVICETYPE} serial:${DEVICESERIALNUMBER} mediaownerid:${MEDIAOWNERCUSTOMERID}"
	play_song
elif [ -n "$PLIST" ] ; then
	set_var
	echo "playing library playlist:${PLIST} on dev:${DEVICE} type:${DEVICETYPE} serial:${DEVICESERIALNUMBER} mediaownerid:${MEDIAOWNERCUSTOMERID}"
	play_playlist
elif [ -n "$LIST" ] ; then
	echo "the following devices exist in your account:"
	list_devices
elif [ -n "$TYPE" ] ; then
	set_var
	echo -n "the following songs exist in your ${TYPE} library: "
	show_library
elif [ -n "$PRIME" ] ; then
	set_var
	echo "the following songs exist in your PRIME ${PRIME}:"
	show_prime
elif [ -n "$ASIN" ] ; then
	set_var
	echo "playing PRIME playlist ${ASIN}"
	play_prime_playlist
elif [ -n "$SEEDID" ] ; then
	set_var
	echo "playing PRIME station ${SEEDID}"
	play_prime_station
elif [ -n "$HIST" ] ; then
	set_var
	echo "playing PRIME historical queue ${HIST}"
	play_prime_hist_queue
else
	echo "no alexa command received"
fi

if [ -n "$LOGOFF" ] ; then
	echo "logout option present, logging off ..."
	log_off
fi
