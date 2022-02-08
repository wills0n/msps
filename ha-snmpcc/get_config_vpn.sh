#!/bin/sh

. /export/home/biller/oracle_profile


if [ ! -d /export/home/biller/work/vpnsnmp/bin/get_config_vpn.run ]
then
   mkdir /export/home/biller/work/vpnsnmp/bin/get_config_vpn.run &&\
   /export/home/biller/work/vpnsnmp/bin/get_config_vpn_v5.pl &&\
   rmdir /export/home/biller/work/vpnsnmp/bin/get_config_vpn.run
else
   if [ "X`ps -efwww| grep "/export/home/biller/work/vpnsnmp/bin/get_config_vpn_v5.pl" | grep -v grep`" = "X" ]
   then
      rmdir /export/home/biller/work/vpnsnmp/bin/get_config_vpn.run && exit 1
      echo "Can't delete /export/home/biller/work/vpnsnmp/bin/get_config_vpn.run, but process is not running"
      exit 1
      
   fi
fi

/export/home/biller/work/vpnsnmp/bin/scp_vpn_config_privat_ekaterinburg.sh