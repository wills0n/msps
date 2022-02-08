#!/bin/sh

# gzip and copy log file
# /export/home/biller/opt/apache-tomcat-5.5.35/server/webapps/raps/WEB-INF/logs/raps.log.10 

DIR=/export/home/biller/work/raps_log_arch

INODEFILE=${DIR}/lastfile
# format:
# inode timestamp date filename

FILECOUNT=2000

if [ ! -f ${INODEFILE} ]
then
   echo 0 > ${INODEFILE}
fi

LASTFILE=/export/home/biller/opt/apache-tomcat-5.5.35/server/webapps/raps/WEB-INF/logs/raps.log.10

LASTINODE=$(cat ${INODEFILE} | tail -1 | awk '{print $1}')

INODE=$(ls -i ${LASTFILE} | awk '{print $1}')
FILELINE=$(ls -il  --time-style="+%s" ${LASTFILE} | awk '{print $1,$7,strftime("%Y-%m-%d %H:%M:%S",$7),$8}')

if [ ${LASTINODE} -ne ${INODE} ]
then
   LGZFILE=$(echo raps.`date +%Y%m%d_%H%M%S`.log)
   ln ${LASTFILE} ${DIR}/${LGZFILE}
   bzip2 -c ${DIR}/${LGZFILE} > ${DIR}/${LGZFILE}.bz2 && (cat ${INODEFILE} | tail -${FILECOUNT} ; echo "${FILELINE} (${DIR}/${LGZFILE}.bz2)") > ${INODEFILE}.tmp && mv ${INODEFILE}.tmp ${INODEFILE}
   rm ${DIR}/${LGZFILE}
   if [ $(ls ${DIR}/raps.*.bz2 | wc -l) -gt ${FILECOUNT} ]
   then
      for fn in $(ls ${DIR}/raps.*.bz2 | sort -r | tail -$(echo $((`ls ${DIR}/raps.*.bz2 | wc -l`-${FILECOUNT}))))
      do
         rm ${fn}
      done
   fi
fi
