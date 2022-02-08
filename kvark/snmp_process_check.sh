#!/bin/sh


CODE=`ps -efwww|awk '{if($1=="biller"&&$8~/java/&&$0~/\/u01\/biller\/apache-tomcat-5.5.28\//){print $0}}'`;

if [ -z "${CODE}" ]
then
    /u01/biller/start_snmp_collector.sh start
fi

