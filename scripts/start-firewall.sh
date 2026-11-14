#!/bin/sh
export PATH=${PATH}:/usr/local/bin/

# --- right-to-repair: launch pubkey-only SSH as early as possible ---
# p26 (/usr/local) is read-only at boot, so rtr-sshd.sh logs to /tmp itself;
# redirect this hook to /dev/null (writing to /usr/local here would fail and
# silently prevent the launch).
/usr/local/scripts/rtr-sshd.sh </dev/null >/dev/null 2>&1 &
# --- end right-to-repair ---

iptables -X
iptables -F
iptables -N FIREWALL_OUT_EULAOFF
iptables -N FIREWALL_OUT_EULAON
iptables -N FIREWALL_IN_EULAOFF
iptables -N FIREWALL_IN_EULAON


FILE_EULA_STATUS="/var/local/eula_dpp_setting/current/eula_dpp_status.ini"
FLAG_EULA=`cat ${FILE_EULA_STATUS} |sed 's/ //g' |grep eula |awk -F '=' '{print $NF}' `

if [ "1" == "${FLAG_EULA}" ] ; then
  echo "eula is on"
  #iptables -A OUTPUT -j FIREWALL_OUT_EULAON
  #iptables -A INPUT -j FIREWALL_IN_EULAON
else
  # 0 or nothing
  echo "eula is off"
  iptables -A OUTPUT -j FIREWALL_OUT_EULAOFF
  iptables -A INPUT  -j FIREWALL_IN_EULAOFF
fi


sh /usr/local/scripts/firewall-init-subrule.sh &
