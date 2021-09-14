#!/bin/bash
#By Keepwalking86
##Scripting for changing auto CDN when high traffic

#CloudFlare API Token key
auth_email="changeme"
auth_key="changeme"

#DNS config
zone_id="changeme"
#identifier record ID
record_id="changeme"
#data_content="'{"type":"CNAME","name":"cdn","content":"static.example.com","ttl":120,"proxied":false}'"
#data_alertcontent="'{"type":"CNAME","name":"cdn","content":"cdn1.example.com","ttl":120,"proxied":false}'"
name="cdn"
content="static.example.com"
alertcontent="cdn1.example.com"

######### Trigger Conditions for alert #########
## Alert when result is greater than or equal to
alert=8000
## Recover automatically when result is less than
recover=6000

############ Notifications Telegram ############
## https://api.telegram.org/bot[TOKEN]/sendMessage?chat_id=[CHAT_ID]&text=[MY_MESSAGE_TEXT]
chat_id="changeme"
bot_token="changeme"
telegram_notify(){
curl -s --data "text=$1" --data "chat_id=$chat_id" 'https://api.telegram.org/bot'$bot_token'/sendMessage' > /dev/null
}

#Get traffic via Prometheus API
#query_monitor="'query=rate(ifHCOutOctets{ifIndex="11111"}[2m])*8/1024/1024' http://192.168.1.111:9090/api/v1/query | jq -r '.data.result[] | [.value[1] ] | @csv'"
monitor_url="http://192.168.1.111:9090/api/v1/query"
monitor_query()
{
  cat <<EOF
query=rate(ifHCOutOctets{ifIndex="11111"}[2m])*8/1024/1024
EOF
}

#Functions for put cname data to Cloudflare
recover_cname_data()
{
  cat <<EOF
{
    "type":"CNAME","name":"$name","content":"$content","ttl":120,"proxied":false
}
EOF
}

alert_cname_data()
{
  cat <<EOF
{
    "type":"CNAME","name":"$name","content":"$alertcontent","ttl":120,"proxied":false
}
EOF
}

##Create a file that contains status
[ ! -f status_file.txt ] && echo "recover">status_file.txt

##alert status
status_alert=alert
status_recover=recover

##Create a file that contains logs
OUTPUT="log.txt"
# Assign the fd 3 to $OUTPUT file
exec 3> $OUTPUT

i=0
while true; do
	query_bandwidth=$(curl -fs --data-urlencode "$(monitor_query)" $monitor_url | jq -r '.data.result[] | [.value[1] ] | @csv' |grep -o "[0-9.]\+")
	#convert float to int
	bandwidth=${query_bandwidth%.*}
	echo "Current bandwidth: $bandwidth" >&3
	if [[ $bandwidth -ge $alert ]]; then
		status=$(cat status_file.txt)
		if [[ $status != 'alert' ]]; then
			((i+=1))
			echo "Number times of alert bandwidth: $i" >&3
			if [[ $i == 3 ]]; then
				echo "Change cname to big CDN .." >&3
				#Change cname via Cloudflare API
			curl -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
     -H "X-Auth-Email: $auth_email" \
     -H "X-Auth-Key: $auth_key" \
     -H "Content-Type: application/json" \
     --data "$(alert_cname_data)" >notify.txt
				cat notify.txt |grep -i '"success":true'
				if [ $? -eq 0 ]; then
					cat notify.txt  >&3
					#Send notify to telegram
					telegram_notify "🔥Change cname from $content to $alertcontent successfully!🔥"
					#change status to alert
					echo "alert">status_file.txt
				else
					cat notify.txt >&3
					#Send notify to telegram
					telegram_notify "🔥Change cname from $content to $alertcontent Failed!🔥"
				fi
				i=0
			fi
		fi
	else
		i=0
		status=$(cat status_file.txt)
		echo "Current status: $status" >&3
		echo "Bandwidth less than alert" >&3
		if [[ $bandwidth -lt $recover ]] && [[ $status != 'recover' ]]; then
			echo "Status change from alert to recover" >&3
			#Recover cname to my CDN
			curl -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
     			-H "X-Auth-Email: $auth_email" \
     			-H "X-Auth-Key: $auth_key" \
     			-H "Content-Type: application/json" \
     			--data "$(recover_cname_data)" >notify.txt
			cat notify.txt |grep -i '"success":true'
			if [ $? -eq 0 ]; then
				cat notify.txt  >&3
                #Send notify to telegram
				telegram_notify "🔥Recover cname from $alertcontent to $content successfully!🔥"
				#change status to recover
				echo "recover">status_file.txt
            else
                cat notify.txt >&3
                #Send notify to telegram
				telegram_notify "🔥Recover cname from $alertcontent to $content failed!🔥"
            fi
		fi
	fi
	sleep 10
done