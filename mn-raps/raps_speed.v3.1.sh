#!/bin/sh

plSTART="/export/home/biller/raps_speed.v3.1.pl"
FLAG=0

if [ ! -z "`ps -efwww | grep ${plSTART} | grep -v grep`" ]
then
   FLAG=1
fi

if [ ${FLAG} == 0 ]
then
    ${plSTART} &
#else
#    echo OK
fi
