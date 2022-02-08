#!/bin/sh

# Check first cmd parameter, must be "MN" or "DR"
if [ "$1" != "MN" -a "$1" != "DR" ] 
then
    echo "$1 is not \"MN\" or \"DR\" parameter (case sensivite) exiting .. "
    exit 101
fi

THREAD=/export/home/biller/work/snmp/spool/th2.d
INPUT=$THREAD/in
TMP=$THREAD/tmp
#KEY=/export/home/biller/work/snmp2/keys/2nfp2
KEY=/export/home/biller/work/vpnsnmp/keys/2mn-nfp2
#OUT=/u02/yshpak/work/spool/input
#OUT=/u01/biller/work/spool/input

#RUSER="yshpak"
RUSER="biller"
#RHOST=nfp2.sovinte.net
#RHOST="10.101.100.130"
#RHOST="mn-nfp2.vimpelcom.ru"

if [ "$1" = "MN" ]
then
    OUT=/u01/biller/work/spool/input/
    RHOST="mn-nfp2.vimpelcom.ru"
else
    OUT=/u02/biller/work/spool/input/
    RHOST="dr-nfp2.vimpelcom.ru"
fi

#echo -e "${RHOST} : ${OUT}"
#ssh ${RUSER}@${RHOST} ls ${OUT}
#exit 0

do_scp () {

        cd ${INPUT}
        for fn in `ls *.out 2>/dev/null`
        do
                if ! mv ${INPUT}/${fn} ${TMP}/${fn}
                then
                        echo "move ${fn} to tmp: failed!"
                        return 1
                fi
        done

        cd ${TMP}
        for fn in `find . -name '*.out' 2>/dev/null`
        do
                # Now used id_rsa from .ssh
                if ! scp -q ${TMP}/${fn} ${RUSER}@${RHOST}:${OUT}/${fn}.tmp
                #if ! scp -q -i $KEY ${TMP}/${fn} ${RUSER}@${RHOST}:${OUT}/${fn}.tmp
#                if ! scp -i $KEY ${TMP}/${fn} ${RUSER}@${RHOST}:${OUT}/${fn}.tmp
                then
                        echo "scp failed: ${fn} to ${RHOST}"
                        return 1
                fi

                # Now used id_rsa from .ssh
                if ! ssh ${RUSER}@${RHOST} "mv ${OUT}/${fn}.tmp ${OUT}/${fn}"
                #if ! ssh -i $KEY ${RUSER}@${RHOST} "mv ${OUT}/${fn}.tmp ${OUT}/${fn}"
                then
                        echo "ssh move failed: ${fn} on ${RHOST}"
                fi

                rm -f ${TMP}/${fn}
        done

        return 0
}

do_scp

