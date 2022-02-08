#!/bin/sh

PATH=/sbin:/usr/sbin:/bin:/usr/bin
export PATH

ROOT='/export/home/biller/work/snmp'
BIN="${ROOT}/bin"
SPOOL="${ROOT}/spool"
INPUT="${SPOOL}/th1.d/in"
TEMP="${SPOOL}/th1.d/tmp"
LOGS="${SPOOL}/logs"
TRASH="${SPOOL}/trash"
ARCH="${LOGS}/arch"

PARSER="${BIN}/debug-parse.pl"

# BIN="${ROOT}/mpls-test"
# INPUT="${SPOOL}/input"
# TEMP="${SPOOL}/temp"
#RRD_SPOOL="${SPOOL}/2rrd"
#ARCH="/opt/data/anry/spool/arch"
#PARSER2="/home/anry/work/snmp2/debug-parse.pl"
#PARSER3="/home/anry/work/snmp2/tmp/parse2.pl"

#MPLS_PARSER="/home/anry/work/snmp2/cnt/parse-cnt.pl"
#SNMP_PARSER="/home/anry/work/snmp2/debug-parse.pl"

#UPDT="${BIN}/upd2snmp.pl"
#RRD="${BIN}/rrd.pl"
#RRD="/home/anry/work/snmp2/rrd.pl"

DELAY=3600
RETRY=3

# make perl happy
#PERL5OPT="-I${ROOT}"
#export PERL5OPT

# =======================================================================
# functions
# =======================================================================
create_lock () {
	lock=$1

	# lock the spool file
	mkdir ${lock}
	if [ $? -ne 0 ]
	then
		echo "	create_lock: failed - ${lock}"
		return 1
	fi

	return 0
}

delete_lock () {
	lock=$1

	if [ -d "${lock}" ]
	then
		rmdir "${lock}"
		if [ $? -ne 0 ]
		then
			echo "	delete_lock: failed - ${lock}"
			return 1
		fi
	else
		echo "	delete_lock: no lock-file - ${lock}"
	fi

	return 0
}

lock_spool () {
	prefix=$1
	lock="${SPOOL}/${prefix}.lock"

	create_lock "${lock}"
	return $?
}

unlock_spool () {
	prefix=$1
	lock="${SPOOL}/${prefix}.lock"

	delete_lock "${lock}"
	return $?
}

lock_acct () {
	prefix=$1

	if lock_spool "${prefix}"
	then
		lock="${SPOOL}/${prefix}.acct"
		if create_lock "${lock}"
		then
			return 0
		else
			echo "	lock_acct: failed - ${lock}"
			unlock_spool "${prefix}"
		fi
	else
		echo "	lock_acct: failed"
	fi

	return 1
}

unlock_acct () {
	prefix=$1
	lock="${SPOOL}/${prefix}.acct"

	if delete_lock "${lock}"
	then
		return 0
	else
		echo "	unlock_acct: failed - ${lock}"
		return 1
	fi
}

concatent_data () {
	prefix=$1
	file="${SPOOL}/${prefix}_spool"

	# lock the spool file
	if ! lock_spool "${prefix}"
	then
		echo "${prefix} - lock file exists or some error"
		return 1
	fi

	if [ ! -f ${file} ] && ! touch ${file} 2>/dev/null
	then
		echo "${prefix} - file doesn't exist and its creation failed"
		unlock_spool "${prefix}"
		return 1
	fi

	# move input files to the temp dir
	mv ${INPUT}/${prefix}_*.out ${TEMP}/
	if [ $? -eq 1 ]
	then
		echo "${prefix} - input files movement failed"
	# it's not a failure - just no files in input/ but they may be in temp/
	#	rmdir ${file}.lock
	#	return 1
	fi

	# rename spool file to .tmp
	mv ${file} ${file}.tmp 2>/dev/null
	if [ $? -eq 1 ]
	then
		echo "${prefix} - mv failed"
		unlock_spool "${prefix}"
		return 1
	fi

	cat ${file}.tmp ${TEMP}/${prefix}_*.out 2>/dev/null | sort -nk 1 > ${file}

	s_old=`ls -l ${file}.tmp 2>/dev/null | awk '{print $5}'`
	s_new=`ls -l ${file}.tmp 2>/dev/null | awk '{print $5}'`

	if [ "X${s_new}" == "X" ]
	then
		echo "${prefix} - concatention failed - no file"
		mv ${file}.tmp ${file}
		unlock_spool "${prefix}"
		return 1
	fi

	if [ $s_old -gt $s_new ]
	then
		echo "${prefix} - new file is less than the old one"
		rm -f ${file}
		mv ${file}.tmp ${file}
		unlock_spool "${prefix}"
		return 1
	fi

	# save inputs
	# commented after THREADS
	 mv ${TEMP}/${prefix}_*.out ${LOGS}/
#	rm ${TEMP}/${prefix}_*.out

	# delete the .tmp file
	rm -f ${file}.tmp

	# unlock the prefix
	unlock_spool "${prefix}"
}

process_data () {

	prefix=$1
	file="${SPOOL}/${prefix}_spool"

	if [ ! -f ${file} ]
	then
		echo "prefix - file does not exist"
		return 1
	fi

	# lock the spool file
	if ! lock_spool "${prefix}"
	then
		echo "${prefix} - lock file exists or some error"
		return 1
	fi

	# rename the spool file to .tmp
	mv ${file} ${file}.tmp 2>/dev/null
	if [ $? -eq 1 ]
	then
		echo "${prefix} - mv failed"
		unlock_spool "${prefix}"
		return 1
	fi

	regexp=`cat ${file}.tmp | awk '{print $1}' | sort -nu | awk '
		BEGIN { i=-1 }
		      { time[++i] = $1 }
		END   { max=time[i]
			out = ""
			for(j=0; j<=i; j++) {
				if( (max - time[j]) < '${DELAY}' ) {
					out = out time[j] "|"
				}
			}

			len=length(out);
			if( len > 0 ) {
			    tt=substr(out, 1, len-1);
			    regexp = "^(" tt ")\t"
			    print regexp
			}
		} '`

#	echo "${prefix}: REGEXP - '$regexp'"
	if [ "X$regexp" != "X" ]
	then
		# 1st grep - to .out file
		err=`eval "egrep -v '$regexp' ${file}.tmp >> ${file}.out" 2>&1`
		st=$?
		case $st in 
		    # first grep OK
		    0)
			# run second grep
			err=`eval "egrep '$regexp' ${file}.tmp > ${file}" 2>&1`
			st=$?
			case $st in
			    # second grep is also OK
			    0)
				rm -f ${file}.tmp
				unlock_spool "${prefix}"
			    ;;
			    # some errors were found
			    *)
				echo "${prefix}: 2nd grep status $st"
				echo "${prefix}: 2nd grep regexp '$regexp'"

				prg=`echo $err | sed 's/^\(.....\).*$/\1/'`

				# check the error source
				if [ $st -eq 1 -a "X$err" == "X" ]
				then
					# error was returned by grep
					# and error code is 1 - nothing found
					echo "${prefix}: 2nd grep NOTHING found"
					echo "${prefix}: returning"
					rm -f ${file}.tmp
					unlock_spool "${prefix}"
					return
				fi

				# error was set by shell
				# or it was set to 2 by grep
				# anyway - something has failed

				echo "${prefix}: errstr '$err'"

				# make several retries
				i=0
				while [ $i -lt $RETRY  -a  $st -ne 0 ]
				do
					err=`eval "egrep '$regexp' ${file}.tmp > ${file}" 2>&1`
					st=$?
					i=$(($i+1))
				done

				prg=`echo $err | sed 's/^\(.....\).*$/\1/'`

				case $status in
				    0)
					echo "${prefix}: fixed"
					rm -f ${file}.tmp
					unlock_spool "${prefix}"
					;;
				    *)
					echo "${prefix}: 2nd grep status $st"
					if [ $st -eq 1 -a "X$prg" == "X" ]
					then
						echo "${prefix}: 2nd grep NOTHING found"
						echo "${prefix}: returning"
						rm -f ${file}.tmp
						unlock_spool "${prefix}"
					else
						echo "${prefix}: errstr '$err'"
						echo "${prefix}: FAILED"
					fi
					;;
				esac
			    ;;
			esac
		    ;;
		    *)
			echo "${prefix}: 1st grep status $st"
			echo "${prefix}: 1st grep errstr '$err'"
			echo "${prefix}: 1st grep regexp '$regexp'"
			echo "${prefix}: returning ..."
			mv ${file}.tmp ${file}
			unlock_spool "${prefix}"
		    ;;
		esac
	else
		mv ${file}.tmp ${file}
		unlock_spool "${prefix}"
	fi
}

account_data () {

	prefix=$1
	func='account'

	file="${SPOOL}/${prefix}_spool.out"
	DATE=`date '+%m%d_%H%M'`
	acct_tmp="${TEMP}/${prefix}_spool_${DATE}"
	acct_log="${LOGS}/${prefix}_spool_${DATE}"
	rrd_log="${RRD_SPOOL}/${prefix}_spool_${DATE}"

	if [ ! -f ${file} ]
	then
		echo "${prefix} - file does not exist"
		return 1
	fi

	# create the accounting lock
	if ! lock_acct "${prefix}"
	then
		echo "${func}: ${prefix} - account lock failed"
		return 1
	fi
		
	# move the spool file to the temp dir
	mv $file ${acct_tmp}
	if [ $? -ne 0 ]
	then
		echo "${func}: ${prefix} - move to temp failed - $!"
		unlock_acct "${prefix}"
		unlock_spool "${prefix}"
		return 1
	fi

	# unlock the spool file
	if ! unlock_spool "${prefix}"
	then
		echo "${func}: ${prefix} - spool unlock failed - $!"
		echo "${func}: ${prefix} - continuing"
	fi

	# calculations
	# ${PARSER} < ${acct_tmp}

	# off - Mon Sep  1 15:35:57 MSD 2003
	# on - Thu Sep  4 19:06:55 MSD 2003
	# ${PARSER2} ${acct_tmp}

	# mix by sly - Thu May 25 10:40:45 MSD 2006
#	if [ "${prefix}" == "mpls" ]
#	then
#		echo
#		echo "[$prefix] MPLS parser"
#		echo
#		${MPLS_PARSER} ${acct_tmp}
#	else
#		echo
#		echo "[$prefix] SNMP parser"
#		echo
#		${SNMP_PARSER} ${acct_tmp}
#	fi

        time1=`date +%s`

	${PARSER} ${acct_tmp}

        time2=`date +%s`
        sec=$(($time2-$time1))
        min=$(($sec/60))
        sec1=$(($sec%60))
        echo -e "\nNeeded time for processor: $sec sec; $min:$sec1 min:sec\n"

	# tmp update trash1_3
	# off -  Thu Sep  4 18:00:00 MSD 2003
	# ${PARSER3} ${acct_tmp}

	# Update traffic_snmp
	# ${UPDT}	

	# save acct_file for history
	mv ${acct_tmp} ${acct_log}
	if [ $? -ne 0 ]
	then
		echo "${func}: ${prefix} - moving acct to logs failed - $!"
		echo "${func}: ${prefix} - leaving file in temp - ${acct_tmp}"
	fi

	# make a link for rrd processing
	# removed by anry - 2004.04.04
	# ln -s ${acct_log} ${rrd_log}

	# unlock acct
	if ! unlock_acct "${prefix}"
	then
		echo "${func}: ${prefix} - accounting unlock failed"
		return 1
	fi

	return 0
}

account_data_nolog () {

	# one different from account_data()
	# we don't store file for history

        prefix=$1
        func='account'

        file="${SPOOL}/${prefix}_spool.out"
        DATE=`date '+%m%d_%H%M'`
        acct_tmp="${TEMP}/${prefix}_spool_${DATE}"
        acct_log="${LOGS}/${prefix}_spool_${DATE}"
        rrd_log="${RRD_SPOOL}/${prefix}_spool_${DATE}"

        if [ ! -f ${file} ]
        then
                echo "${prefix} - file does not exist"
                return 1
        fi

        # create the accounting lock
        if ! lock_acct "${prefix}"
        then
                echo "${func}: ${prefix} - account lock failed"
                return 1
        fi
                
        # move the spool file to the temp dir
        mv $file ${acct_tmp}
        if [ $? -ne 0 ]
        then
                echo "${func}: ${prefix} - move to temp failed - $!"
                unlock_acct "${prefix}"
                unlock_spool "${prefix}"
                return 1
        fi

        # unlock the spool file
        if ! unlock_spool "${prefix}"
        then
                echo "${func}: ${prefix} - spool unlock failed - $!"
                echo "${func}: ${prefix} - continuing"
        fi

        # calculations
        # ${PARSER} < ${acct_tmp}

        # off - Mon Sep  1 15:35:57 MSD 2003
        # on - Thu Sep  4 19:06:55 MSD 2003
        ${PARSER2} ${acct_tmp}

        # tmp update trash1_3
        # off -  Thu Sep  4 18:00:00 MSD 2003
        # ${PARSER3} ${acct_tmp}

        # Update traffic_snmp
        # ${UPDT}       

        # save acct_file for history
	# off by sly - Wed Feb  1 11:50:24 MSK 2006
#        mv ${acct_tmp} ${acct_log}
#        if [ $? -ne 0 ]
#        then
#                echo "${func}: ${prefix} - moving acct to logs failed - $!"
#                echo "${func}: ${prefix} - leaving file in temp - ${acct_tmp}"
#        fi

	# delete file, because backup stopped
	rm -f ${acct_tmp}

        # make a link for rrd processing
        # removed by anry - 2004.04.04
        # ln -s ${acct_log} ${rrd_log}

        # unlock acct
        if ! unlock_acct "${prefix}"
        then
                echo "${func}: ${prefix} - accounting unlock failed"
                return 1
        fi

        return 0
}

rrd_data () {
	prefix=$1
	func="rrd_data"

	# update rrd files
	${RRD} ${RRD_SPOOL}/${prefix}_spool_*

	# delete files
	rm -f ${RRD_SPOOL}/${prefix}_spool_*
}

backup_data () {

	prefix=$1
	func='backup'
	
	TZ=GMT+12
	export TZ
	YMD=`date '+%Y%m%d'`
	MD=`date '+%m%d'`
	unset TZ

	echo "spool archive ..."
	# tricky move
	cd ${LOGS}
	mv ${prefix}_spool_${MD}_???? ${TRASH}/
	cd ${TRASH}
	tar cvzf ${ARCH}/${prefix}-${YMD}.tgz ${prefix}_spool_${MD}_????
	echo "done"
	echo 

	echo "raw archive"
	# tricky move
	cd ${LOGS}
	mv ${prefix}_*.out ${TRASH}/
	cd ${TRASH}
	tar cvzf ${ARCH}/${prefix}.raw-${YMD}.tgz ${prefix}_*.out
	echo "done"

}

backup_data2 () {

	prefix=$1
	func='backup'

	Y=`date +%Y`
	YMD=`date +%Y%m%d -d 'yesterday'`
	MD=`date +%m%d -d 'yesterday'`

	WINDOW="$LOGS/window"

	# ATS - (00:00 - 30 min)
	# STS - 00:00
	# CATS - (59:59 - 30 min)
	# ETS - 59:59
	# BTS - (59:59 + 30 min)

	STS=`date +%s -d "$YMD"`
	let "ETS = STS + ( 60 * 60 * 24 ) - 1"
	let "ATS = STS - ( 60 * 30 )"
	let "BTS = ETS + ( 60 * 30 )"
	let "CATS = ETS - ( 60 * 30 )"

        TMP="$ARCH/import"

	echo
	echo "spool archive for ${prefix} ..."

	cd ${LOGS}
	for file in ${prefix}_spool_${MD}_*
	do
		if ! mv ${file} ${TRASH}/${file}
		then
			echo "Can't move to TRASH: ${file}"
		fi
	done

	cnt=`find ${TRASH}/ -name "${prefix}_spool_${MD}_????" 2>/dev/null | wc -l`
	if [ $cnt -gt 0 ]
	then
		cd ${TRASH}
		if ! find . -name "${prefix}_spool_${MD}_????" -print | tar -czvf ${ARCH}/${prefix}-${YMD}.tgz --files-from -
		then
			echo "Backup.spool ${prefix} failed!"
		else
			echo "Successful."

			#Create md5 file for check it in future CR#22236
			if ! /usr/bin/md5sum ${ARCH}/${prefix}-${YMD}.tgz > ${ARCH}/${prefix}-${YMD}.tgz.md5
			then
			   echo "Can't create MD5 file for ${ARCH}/${prefix}-${YMD}.tgz"
			fi
			####

			if ! cp ${ARCH}/${prefix}-${YMD}.tgz ${TMP}/
			then
				echo "Can't copy to ${TMP}: ${prefix}-${YMD}.tgz"
			else                                                   #CR#22236
			        cp ${ARCH}/${prefix}-${YMD}.tgz.md5 ${TMP}/    #CR#22236
			fi
		fi
	else
		echo "No files for backup."
	fi


	echo
	echo "raw archive for ${prefix} ..."

	cd ${WINDOW}
	for file in ${prefix}_*.out
	do
		if ! mv ${file} ${TRASH}/${file}
		then
			echo "Can't move to TRASH: ${file}"
		fi
	done

	cd ${LOGS}
	for file in ${prefix}_*.out
	do
		#ts=`echo ${file} | sed "s/^${prefix}_\?\w\+\?_\([0-9]\+\)_[0-9]\+\.out$/\1/"`
                ts=`echo ${file} | sed "s/^${prefix}_\?\w\+\?_\([0-9]\+\).out$/\1/"|awk -F "" '{print substr($0,0,10)}'`

		if [ $ts -ge $STS -a $ts -le $ETS ]
		then

			if [ $ts -ge $CATS -a $ts -le $ETS ]
			then
				if ! cp ${file} ${WINDOW}/${file}
				then
					echo "Can't copy file to WINDOW: ${file}"
				fi
			fi
			
			if ! mv ${file} ${TRASH}/${file}
			then
				echo "Can't move to TRASH: ${file}"
			fi

		elif [ $ts -ge $ETS -a $ts -le $BTS ]
		then
			if ! cp ${file} ${TRASH}/${file}
			then
				echo "Can't copy to TRASH: ${file}"
			fi
		fi
	done

	cnt=`find ${TRASH}/ -name "${prefix}_*.out" 2>/dev/null | wc -l`
	if [ $cnt -gt 0 ]
	then

		# copy first file after midnight
		#
#		if [ $prefix == "sovintel" ]
#		then
#			nodelist="kvark lepton letron atom"
#
#			for node in ${nodelist}
#			do
#				prefix_node="${prefix}_${node}"
#				firstfile_raw $prefix_node
#
#				if [ ! -z $FFname ]
#				then
#					if ! cp $FFname ${TRASH}/
#					then
#						echo "Copy to TRASH failed: $FFname"
#					fi
#				fi
#			done
#		else
#			firstfile_raw $prefix
#
#			if ! cp $FFname ${TRASH}/
#			then
#				echo "Copy to TRASH failed: $FFname"
#			fi
#		fi

		#
		# end of copy

		cd ${TRASH}
		if ! find . -name "${prefix}_*.out" -print | tar -czvf ${ARCH}/${prefix}.raw-${YMD}.tgz --files-from -
		then
			echo "Backup.raw ${prefix} failed!"
		else
			echo "Successful."

			#Create md5 file for check it in future CR#22236
			if ! /usr/bin/md5sum ${ARCH}/${prefix}.raw-${YMD}.tgz > ${ARCH}/${prefix}.raw-${YMD}.tgz.md5
			then
                              echo "Can't create MD5 file for ${ARCH}/${prefix}.raw-${YMD}.tgz"
                        fi
			####

			if ! cp ${ARCH}/${prefix}.raw-${YMD}.tgz ${TMP}/
			then
				echo "Can't copy to ${TMP}: ${prefix}.raw-${YMD}.tgz"
			else                                                     #CR#22236
			        cp ${ARCH}/${prefix}.raw-${YMD}.tgz.md5 ${TMP}/  #CR#22236
			fi
		fi
	else
		echo "No files for backup."
	fi

}

import_nfp () {

	prefix=$1

        OUTDIR="/u03/archive/snmp"
        TMP="$ARCH/import"
	ILOCK="$TMP/import.lock"
        SSHKEY="/export/home/biller/work/snmp2/keys/atom-nfp-key"
	Y=`date +%Y -d "yesterday"`

        # var for mn-nfp1.vimpelcom.ru
        User="biller"
        Host="192.168.191.211"  # mn-nfp1.vimpelcom.ru 192.168.191.211 (second ip 192.168.191.200)
        NFP1_OUT="/u02/data/snmp"
        NFP1_TMP="${NFP1_OUT}/tmp"


#	echo
#	echo "Transfer to nfp.sovintel.net ..."

	if ! create_lock ${ILOCK}
	then
		exit 1
	fi

	cd ${TMP}
	for file in `ls ${prefix}*.tgz 2>/dev/null`
	do
	        #Edit md5 file: change path to file CR#22236
	        if [ ! -f ${file}.md5 ]
		then
		   echo "No MD5 file for ${file}" | mail -s 'NO MD5' YuShpak@beeline.ru   #send message about no md5 file
		   continue
		else
                   # for nfp.sovintel.net
		   #sed -e "s|${ARCH}|${OUTDIR}/${Y}|g" ${file}.md5 > ${file}.md5.tmp && mv ${file}.md5.tmp ${file}.md5.nfp
		   # for mn-nfp1.vimpelcom.ru
		   sed -e "s|${ARCH}|${NFP1_OUT}/${Y}|g" ${file}.md5 > ${file}.md5.tmp && mv ${file}.md5.tmp ${file}.md5.mn-nfp1

		   rm -f ${file}.md5
		fi
	        #### 
		
	#	echo -n "${file} to nfp .. "

	#	if ! scp -q -i $SSHKEY ${file} nfp@nfp.sovintel.net:${OUTDIR}/${file}.tmp
	#	then
	#		echo "Can't ssh copy to nfp: ${file}"
	#		continue
	#	fi

	#	if ! ssh -i $SSHKEY nfp@nfp.sovintel.net "mkdir -p ${OUTDIR}/${Y}"
	#	then
	#		echo "Can't ssh make dir: ${OUTDIR}/${Y}"
	#		continue
	#	fi

	#	if ! ssh -i $SSHKEY nfp@nfp.sovintel.net "mv ${OUTDIR}/${file}.tmp ${OUTDIR}/${Y}/${file}"
	#	then
	#		echo "Can't ssh move: ${OUTDIR}/${file}.tmp"
	#		continue
	#	fi

		#Send md5 file to nfp CR#22236
	#	if ! scp -q -i $SSHKEY ${file}.md5.nfp nfp@nfp.sovintel.net:${OUTDIR}/${file}.md5.tmp
	#	then
	#		echo "Can't ssh copy to nfp: ${file}.md5"
	#		continue
	#	fi

	#	if ! ssh -i $SSHKEY nfp@nfp.sovintel.net "mv ${OUTDIR}/${file}.md5.tmp ${OUTDIR}/${Y}/${file}.md5"
	#	then
	#		echo "Can't ssh move: ${OUTDIR}/${file}.md5"
	#		continue
	#	fi
	#	echo "transfered"
		####

                ##
                #   mn-nfp1.vimpelcom.ru 192.168.191.211 (second ip 192.168.191.200)
                ##
                
#                User="biller"
#                Host="192.168.191.211"
#                NFP1_OUT="/u02/data/snmp"
#                NFP1_TMP="${NFP1_OUT}/tmp"

                echo -n "${file} to mn-nfp1 .. "

                if ! ssh ${User}@${Host} "mkdir -p ${NFP1_OUT}/${Y} ; mkdir -p ${NFP1_OUT}/${Y}/tmp"
                then
                        echo "Can't ssh make dir: ${OUTDIR}/${Y}"
                        continue
                fi

                if ! scp -q ${file} ${User}@${Host}:${NFP1_OUT}/${Y}/tmp/${file}.tmp
                then
                        echo "Can't ssh copy to nfp: ${file}"
                        continue
                fi

                if ! ssh ${User}@${Host} "mv ${NFP1_OUT}/${Y}/tmp/${file}.tmp ${NFP1_OUT}/${Y}/${file}"
                then
                        echo "Can't ssh move: ${NFP1_OUT}/${Y}/tmp/${file}.tmp"
                        continue
                fi

                if ! scp -q ${file}.md5.mn-nfp1 ${User}@${Host}:${NFP1_OUT}/${Y}/tmp/${file}.md5.tmp
                then
                        echo "Can't ssh copy to nfp: ${file}.md5"
                        continue
                fi

                if ! ssh ${User}@${Host} "mv ${NFP1_OUT}/${Y}/tmp/${file}.md5.tmp ${NFP1_OUT}/${Y}/${file}.md5"
                then
                        echo "Can't ssh move: ${NFP1_OUT}/${Y}/tmp/${file}.md5"
                        continue
                fi

                ##
                #  mn-nfp1.vimpelcom.ru 192.168.191.211 (second ip 192.168.191.200) 
                ##
                
		echo "transfered"

		rm -f ${file}
		rm -f ${file}.md5   #CR#22236
		rm -f ${file}.md5.*
	done

	if ! delete_lock ${ILOCK}
	then
		exit 1
	fi

}

trash_data () {
	prefix=$1
	func="spool_trash"

	echo "Clearning trash of ${prefix} ..."
	cd ${TRASH}
	find . -name "${prefix}_*" -exec rm -f {} \;
	echo
}

firstfile_raw () {

	# find first file after midnight

        pref=$1

        fc=0
        fn=""
        FFname=""

        cd ${LOGS}

        for file in `ls ${pref}_*.out 2>/dev/null`
        do
                ts=`echo ${file} | sed "s/^${pref}_\?\w\+\?_\([0-9]\+\)_[0-9]\+\.out$/\1/"`

                if [ $fc -gt $ts -o $fc -eq 0 ]
                then
                        fc=$ts
                        fn=$file
                fi
        done

        FFname=$fn

        return

}

# =======================================================================
#
# main script
#
if [ $# -eq 0 ]
then
	echo "Usage: $0 prefix"
	exit 1
fi

# remove all leading path before the script name
prg1=${0##*/}

# remove .sh extension
prg=${prg1%.sh}

while [ "$1" ]
do

#        echo $1
#	echo $0

	case $prg in
		spool_proc)
			# echo "spool_proc"
			concatent_data $1
			process_data $1
		;;
		spool_acct)
			# echo "spool_acct"
			account_data $1
		;;
		spool_acct_v2)
			# echo "spool_acct_v2"
			account_data_nolog $1
		;;
		spool_rrd)
			# echo "spool_rrd"
			rrd_data $1
		;;
		spool_backup)
			# echo "spool_backup"
			# backup_data $1
			backup_data2 $1
			#import_nfp $1
		;;
		spool_trash)
			# echo "spool_trash"
			trash_data $1
		;;
		spool_import_nfp)
			# echo "import_nfp"
			import_nfp $1
		;;
		*)
			echo "Unknown script: $0 - $prg"
		;;
	esac

        shift
done
