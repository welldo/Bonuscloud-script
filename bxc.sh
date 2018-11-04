#!/bin/sh
# BxC-Node operation script from AM380 merlin firmware (by sean.ley (ley@bonuscloud.io)) & Betterman's K2 padavan

# load path environment in dbus databse
BXC_MONITOR="/etc/storage/bxc/bxc-monitor"
BXC_NETWORK="/etc/storage/bxc/bxc-network"
BXC_WORKER="/etc/storage/bxc/bxc-worker"
BXC_SSL_DIR="/etc/storage/bcloud"
BXC_SSL_RES="/etc/storage/bcloud/curl.res"
BXC_SSL_KEY="/etc/storage/bcloud/client.key"
BXC_SSL_CRT="/etc/storage/bcloud/client.crt"
BXC_SSL_CA="/etc/storage/bcloud/ca.crt"
BXC_BOUND_URL="https://console.bonuscloud.io/api/web/devices/bind/"
BXC_REPORT_URL="https://bxcvenus.com/idb/dev"
BXC_INFO_LOC="/etc/storage/bcloud/info"
BXC_JSON="/etc/storage/bxc/bxc-json.sh"
BXC_CONF="/etc/storage/bxc/bxc.config"
BXC_MAC=$(cat /sys/class/net/eth2.2/address)
#填入自己的账号替换abc@abc.com
BXC_EMAIL="abc@abc.com"
#填入自己的Bcode替换xxxxxxx
BXC_BCODE="xxxxxxx"

ipv6_enable() {
	ip6tables -I INPUT -p tcp --dport 8901 -j ACCEPT -i tun0
	ip6tables -I OUTPUT -p tcp --sport 8901 -j ACCEPT
	ip6tables -I INPUT -p icmpv6 -j ACCEPT -i tun0
	ip6tables -I OUTPUT -p icmpv6 -j ACCEPT
	ip6tables -I INPUT -p udp -j ACCEPT -i tun0
	ip6tables -I INPUT -p udp -j ACCEPT -i lo
	ip6tables -I OUTPUT -p udp -j ACCEPT
	iptables -I INPUT -p tcp --match multiport --sports 80,443,8080 -j ACCEPT
	iptables -I OUTPUT -p tcp --match multiport --dports 80,443,8080 -j ACCEPT
}

start_bxc(){

	if [ ! -x /etc/storage/bcloud ];then
		bound_bxc
	fi
	echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6
	if [ ! -d /dev/shm ]; then
		mkdir -v /dev/shm
		mount -vt tmpfs none /dev/shm
		chmod -R 777 /dev/shm/
	fi		
	logger -t bxc-network Start bxc-netwrok > /dev/null 2>&1 &
	chmod +x $BXC_NETWORK && $BXC_NETWORK > /dev/null 2>&1 &
	logger -t bxc-worker Start bxc-worker > /dev/null 2>&1 &
	chmod +x $BXC_WORKER && $BXC_WORKER > /dev/null 2>&1 &
	chmod +x $BXC_MONITOR && $BXC_MONITOR > /dev/null 2>&1 &
}

info_report(){
	version="0.2.2"
	cpu_info=$(cat /proc/cpuinfo | grep -e "^processor" | wc -l)
	mem_info=$(cat /proc/meminfo | grep "MemTotal" | awk -F: '{print $2}'| sed 's/ //g')	
	hw_arch=`uname -m`

	info="${version}#${hw_arch}#${cpu_info}#${mem_info}"
	old_info=$(cat $BXC_INFO_LOC)
	if [ "$info"x != "$old_info"x ];then
		/usr/bin/logger -t  "node info changed: \"$old_info\" change to \"$info\", report info..."
		echo $info > $BXC_INFO_LOC
		fcode=`dbus get bxc_bcode`
		status_code=`curl -m 10 -k --cacert $BXC_SSL_CA --cert $BXC_SSL_CRT --key $BXC_SSL_KEY -H "Content-Type: application/json" -d "{\"mac\":\"$MACADDR\", \"info\":\"$info_cur\"}" -X PUT -w "\nstatus_code:"%{http_code}"\n" "$BXC_REPORT_URL/$BCODE_NEW" | grep "status_code" | awk -F: '{print $2}'`

		if [ $status_code -eq 200 ];then
			/usr/bin/logger -t  "node info reported success!"
		else
			/usr/bin/logger -t bxc-node "node info reported failed($status_code)"
		fi
	else
				/usr/bin/logger -t bxc-node  "node info has not changed: $info"

	fi
}

stop_bxc(){
	pid=`ps | grep bxc-monitor | grep -v grep | awk '{print $1}'`
	[  $pid != 0 ] && kill $pid
 	killall -q bxc-worker
	killall -q bxc-worker
	killall -q bxc-network
	logger -t bxc Stop  > /dev/null 2>&1 &

}

bound_bxc(){
	mkdir -p $BXC_SSL_DIR > /dev/null 2>&1
	if [ ! -d $BXC_SSL_DIR ];then
		logger -t "mkdir $BXC_SSLDIR failed, exit"  > /dev/null 2>&1 &
		return 1
	fi
	chmod +x $BXC_JSON

	curl -k -m 10 -H "Content-Type: application/json" -d "{\"email\":\"$BXC_EMAIL\", \"bcode\":\"$BXC_BCODE\", \"mac_address\":\"$BXC_MAC\"}" -w "\nstatus_code:"%{http_code}"\n" $BXC_BOUND_URL > $BXC_SSL_RES
	curl_code=`grep 'status_code' $BXC_SSL_RES | awk -F: '{print $2}'`
	if [ -z $curl_code ];then

		logger -t "Server has no response, exit" > /dev/null 2>&1 &
		return 1
	elif [ "$curl_code"x == "200"x ];then		
		echo "bound success!"		
		echo -e `cat $BXC_SSL_RES | $BXC_JSON | egrep "\"Cert\",\"key\"" | awk -F\" '{print $6}' | sed 's/"//g'` | base64 -d > $BXC_SSL_KEY
		echo -e `cat $BXC_SSL_RES | $BXC_JSON | egrep "\"Cert\",\"cert\"" | awk -F\" '{print $6}' | sed 's/"//g'` | base64 -d > $BXC_SSL_CRT
		echo -e `cat $BXC_SSL_RES | $BXC_JSON | egrep "\"Cert\",\"ca\"" | awk -F\" '{print $6}' | sed 's/"//g'` | base64 -d > $BXC_SSL_CA
		logger -t  "bound success!"  > /dev/null 2>&1 &

	else
		cat $BXC_SSL_RES | $BXC_JSON | egrep '\["details"\]' > /dev/null
		if [ $? -eq 0 ];then	
			fail_detail=`cat $BXC_SSL_RES | $BXC_JSON | egrep '\["details"\]' | awk -F\" '{print $(NF-1)}'`
			logger -t "bound failed with server response: $fail_detail"  > /dev/null 2>&1 &
		
		else
			logger -t "Server response code: $curl_code, please check /etc/storage/bcloud/curl.res" > /dev/null 2>&1 &
		
		fi
		rm -rf  $BXC_SSL_DIR
		return 1
	fi

	# 备份绑定信息（邀请码 + 证书文件）
	echo $BXC_EMAIL > /etc/storage/bcloud/email
	echo $BXC_BCODE > /etc/storage/bcloud/bcode

	# 保存配置文件
	/sbin/mtd_storage.sh save
}




case $1 in
start)
	stop_bxc
	start_bxc
	;;
stop)
	stop_bxc
	;;
init)
	ipv6_enable	
	stop_bxc
	start_bxc
	;;
*)
	echo "Usage: $0 {start|stop|init}"
    ;;
esac


