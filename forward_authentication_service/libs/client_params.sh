#!/bin/sh
#Copyright (C) BlueWave Projects and Services 2015-2022
#This software is released under the GNU GPL license.
#
status=$1
clientip=$2

do_ndsctl () {
	local timeout=4

	for tic in $(seq $timeout); do
		ndsstatus="ready"
		ndsctlout=$(eval ndsctl "$ndsctlcmd")

		for keyword in $ndsctlout; do

			if [ $keyword = "locked" ]; then
				ndsstatus="busy"
				sleep 1
				break
			fi
		done

		if [ "$ndsstatus" = "ready" ]; then
			break
		fi
	done
}

get_client_zone () {
	# Gets the client zone, (if we don't already have it) ie the connection the client is using, such as:
	# local interface (br-lan, wlan0, wlan0-1 etc.,
	# or remote mesh node mac address

	failcheck=$(echo "$clientif" | grep "get_client_interface")

	if [ -z $failcheck ]; then
		client_if=$(echo "$clientif" | awk '{printf $1}')
		client_meshnode=$(echo "$clientif" | awk '{printf $2}' | awk -F ':' '{print $1$2$3$4$5$6}')
		local_mesh_if=$(echo "$clientif" | awk '{printf $3}')

		if [ ! -z "$client_meshnode" ]; then
			client_zone="MeshZone: $client_meshnode"
		else
			client_zone="LocalZone: $client_if"
		fi
	else
		client_zone=""
	fi
}

htmlentityencode() {
	entitylist="s/\"/\&quot;/ s/>/\&gt;/ s/</\&lt;/"
	local buffer="$1"
	for entity in $entitylist; do
		entityencoded=$(echo "$buffer" | sed "$entity")
		buffer=$entityencoded
	done
}

parse_parameters() {
	ndsctlcmd="json $clientip"

	do_ndsctl

	if [ "$ndsstatus" = "ready" ]; then
		param_str=$ndsctlout

		for param in gatewayname gatewayaddress gatewayfqdn mac version ip client_type clientif session_start session_end \
			last_active token state upload_rate_limit_threshold download_rate_limit_threshold \
			upload_packet_rate upload_bucket_size download_packet_rate download_bucket_size \
			upload_quota download_quota upload_this_session download_this_session upload_session_avg  download_session_avg
		do
			val=$(echo "$param_str" | grep "$param\"" | awk -F'"' '{printf "%s", $4}')

			if [ "$val" = "null" ]; then
				val="Unlimited"
			fi

			if [ -z "$val" ]; then
				eval $param=$(echo "Unavailable")
			else
				eval $param=$(echo "\"$val\"")
			fi
		done

		# url decode and html entity encode gatewayname
		gatewayname_dec=$(printf "${gatewayname//%/\\x}")
		htmlentityencode "$gatewayname_dec"
		gatewaynamehtml=$entityencoded

		# Get client_zone from clientif
		get_client_zone

		# Get human readable times:
		sessionstart=$(date -d @$session_start)

		if [ "$session_end" = "Unlimited" ]; then
			sessionend=$session_end
		else
			sessionend=$(date -d @$session_end)
		fi

		lastactive=$(date -d @$last_active)
	fi
}

header() {
# Define a common header html for every page served
	header="<!DOCTYPE html>
		<html>
		<head>
		<meta http-equiv=\"Cache-Control\" content=\"no-cache, no-store, must-revalidate\">
		<meta http-equiv=\"Pragma\" content=\"no-cache\">
		<meta http-equiv=\"Expires\" content=\"0\">
		<meta charset=\"utf-8\">
		<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
		<link rel=\"shortcut icon\" href=\"$url/images/splash.jpg\" type=\"image/x-icon\">
		<link rel=\"stylesheet\" type=\"text/css\" href=\"$url/splash.css\">
		<title>$gatewaynamehtml Client Session Status</title>
		</head>
		<body>
		<div class=\"offset\">
		<big-red>
			Client Session Status<br>
		</big-red>
		<med-blue>
			$gatewaynamehtml <br>
			$client_zone
		</med-blue><br>
		<div class=\"insert\" style=\"max-width:100%;\">
	"
	echo "$header"
}

footer() {
	# Define a common footer html for every page served
	year=$(date +'%Y')
	echo "
		<hr>
		<div style=\"font-size:0.5em;\">
			<img style=\"height:30px; width:60px; float:left;\" src=\"$url/images/splash.jpg\" alt=\"Splash Page: For access to the Internet.\">
			&copy; The openNDS Project 2015 - $year<br>
			openNDS $version
			<br><br>
		</div>
		</div>
		</div>
		</body>
		</html>
	"
}

body() {
	if [ "$ndsstatus" = "busy" ]; then
		pagebody="
			<hr>
			<b>The Portal is busy, please click or tap \"Refresh\"<br><br></b>
			<form>
				<input type=\"button\" VALUE=\"Refresh\" onClick=\"history.go(0);return true;\">
			</form>
		"
	elif [ "$status" = "status" ]; then

		if [ "$upload_rate_limit_threshold" = "Unlimited" ] || [ "$upload_packet_rate" = "Unlimited" ]; then
			upload_packet_rate="(Not Checked)"
			upload_bucket_size="(Not Set)"
		fi

		if [ "$download_rate_limit_threshold" = "Unlimited" ] || [ "$download_packet_rate" = "Unlimited" ]; then
			download_packet_rate="(Not Checked)"
			download_bucket_size="(Not Set)"
		fi

		pagebody="
			<form action=\"$url/opennds_deny/\" method=\"get\">
				<input type=\"submit\" value=\"Logout\" >
			</form>
			<hr>
			<form>
				<input type=\"button\" VALUE=\"Refresh\" onClick=\"history.go(0);return true;\">
			</form>

		<div style=\"font-size:0.8em;\">
			<br>
			<b>IP address:</b> $ip<br>
			<b>MAC address:</b> $mac<br>
			<b>Client Type:</b> $client_type<br>
			<b>Interfaces being used by this client:</b> $clientif<br>
			<b>Session Start:</b> $sessionstart<br>
			<b>Session End:</b> $sessionend<br>
			<b>Last Active:</b> $lastactive<br>
			<b>Download Rate Limit Threshold:</b> $download_rate_limit_threshold Kb/s<br>
			<b>Download Packet Rate:</b> $download_packet_rate packets/min<br>
			<b>Download Bucket Size:</b> $download_bucket_size packets<br>
			<b>Upload Rate Limit Threshold:</b> $upload_rate_limit_threshold Kb/s<br>
			<b>Upload Packet Rate:</b> $upload_packet_rate packets/min<br>
			<b>Upload Bucket Size:</b> $upload_bucket_size packets<br>
			<b>Download Quota:</b> $download_quota KBytes<br>
			<b>Upload Quota:</b> $upload_quota KBytes<br>
			<b>Downloaded This Session:</b> $download_this_session KBytes<br>
			<b>Uploaded This Session:</b> $upload_this_session KBytes<br>
			<b>Average Download Rate This Session:</b> $download_session_avg Kb/s<br>
			<b>Average Upload Rate This Session:</b> $upload_session_avg Kb/s<br>
		</div>
		"
	elif [ "$status" = "err511" ]; then

		pagebody="
			<h1>Network Authentication Required</h1>
			<form action=\"$url\" method=\"get\">
			<input type=\"submit\" value=\"Refresh\">
			</form>
			<br>
			<form action=\"$url/login\" method=\"get\" target=\"_blank\">
			<input type=\"submit\" value=\"Portal Login\" >
			</form>
		"

	else
		exit 1
	fi

	echo "$pagebody"
}

# Start generating the html:
if [ -z "$clientip" ]; then
	exit 1
fi

if [ "$status" = "status" ] || [ "$status" = "err511" ]; then
	parse_parameters

	if [ -z "$gatewayfqdn" ] || [ "$gatewayfqdn" = "disable" ] || [ "$gatewayfqdn" = "disabled" ]; then
		url="http://$gatewayaddress"
	else
		url="http://$gatewayfqdn"
	fi

	header
	body
	footer
else
	exit 1
fi
