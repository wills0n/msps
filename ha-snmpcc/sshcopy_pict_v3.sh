#!/bin/sh

#SRCINPUT=/u01/data/biller/work/snmp/spool/input
#THREAD=/u01/data/biller/work/snmp/spool/th3.d
#INPUT=$THREAD/in
#TMP=$THREAD/tmp
#KEY=/export/home/biller/work/snmp2/keys/2pict

#########
LTMP="/export/home/biller/work/vpnsnmp/spool/th3.d/tmp"
LOCK="${LTMP}/picts.lock"

INPUT=/export/home/msnmp/vpnsnmp/spool/th3.d/in
TMP=/export/home/msnmp/vpnsnmp/spool/th3.d/tmp

OUT=/u01/biller/data/stat/input
#OUT=/home/yshpak/test_vpn

KEY=/export/home/biller/work/snmp2/keys/2pict
RUSER=biller
RHOST="mn-pict.vimpelcom.ru"
RHOST1="mn-pict2.vimpelcom.ru"

KEY2=/export/home/biller/work/vpnsnmp/keys/vpnsnmp-key
RUSER2=msnmp
RHOST2="172.27.191.25" #Ekaterinburg
###########


do_scp () {


#        for fn in `ssh -q -i ${KEY2} ${RUSER2}@${RHOST2} ". .bash_profile; cd ${INPUT}; find . -name '*.out' 2>/dev/null"`
#        do
#              ssh -q -i ${KEY2} ${RUSER2}@${RHOST2} "mv ${INPUT}/${fn} ${TMP}/${fn} || echo \"move ${fn}to tmp: failed!\""
#        done

        #`ssh -q -i ${KEY2} ${RUSER2}@${RHOST2} ". .bash_profile; cd ${INPUT}; find . -name '*.out' 2>/dev/null"`
#        ssh -v -i ${KEY2} ${RUSER2}@${RHOST2} ". .bash_profile; cd ${INPUT}; \
#           for fn in `find . -name '*.out' 2>/dev/null` ; \
#           do \
#              mv ${INPUT}/${fn} ${TMP}/${fn} ; \
#              if [ $? -ne 0 ] ; then \
#                 echo \"move ${fn} to tmp: failed!\" ; return 1 ; \
#              fi; \
#           done "
        ssh -q -i ${KEY2} ${RUSER2}@${RHOST2} "mv ${INPUT}/*.out ${TMP}/ || echo \"move from in to tmp: failed!\""

        for fn in `ssh -q -i ${KEY2} ${RUSER2}@${RHOST2} ". .bash_profile; cd ${TMP}; find . -name '*.out' 2>/dev/null | sort"`
        do
            if ! scp -q -i ${KEY2} ${RUSER2}@${RHOST2}:${TMP}/${fn} ${LTMP}/
            then
                echo "scp failed: ${fn} to mn-snmp.vimpelcom.ru:${LTMP}/${fn}"
                continue 1
            fi

            # PICT
            if ! scp -q -i ${KEY} ${LTMP}/${fn} ${RUSER}@${RHOST}:${OUT}/${fn}.tmp
            then
                echo "scp failed: ${fn} to mn-pict.vimpelcom.ru:${OUT}/${fn}.tmp"
                continue 1
            fi

            if ! ssh -q -i ${KEY} ${RUSER}@${RHOST} "mv ${OUT}/${fn}.tmp ${OUT}/${fn}"
            then
                echo "ssh move failed: ${fn} on mn-pict.vimpelcom.ru"
                continue 1
            fi
            #PICT

            #PICT2
            if ! scp -q -i ${KEY} ${LTMP}/${fn} ${RUSER}@${RHOST1}:${OUT}/${fn}.tmp
            then
                echo "scp failed: ${fn} to mn-pict2.vimpelcom.ru:${OUT}/${fn}.tmp"
                continue 1
            fi

            if ! ssh -q -i ${KEY} ${RUSER}@${RHOST1} "mv ${OUT}/${fn}.tmp ${OUT}/${fn}"
            then
                echo "ssh move failed: ${fn} on mn-pict2.vimpelcom.ru"
                continue 1
            fi
            #PICT2

            ssh -q -i ${KEY2} ${RUSER2}@${RHOST2} "rm ${TMP}/${fn}"
            rm ${LTMP}/${fn}
        done
}


if [ ! -d ${LOCK} ]
then
   mkdir ${LOCK}
   do_scp
   rmdir ${LOCK}
else
   echo "Lock dir is in ${LOCK}, check it"
fi
