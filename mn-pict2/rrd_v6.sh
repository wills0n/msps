#!/bin/sh

#Add check if process work more then 1.5 hour, then send email 

ROOT=/u01/biller/data/stat
INPUT=$ROOT/input
TMP=$ROOT/temp
LOCK=$ROOT/rrd.lock
RRD=/u01/biller/data/billing/scripts/rrd_v6.pl

export LD_LIBRARY_PATH=/u01/biller/data/billing/rrdtool-1.2.11/lib/:/u01/biller/data/billing/lib/lib/:${LD_LIBRARY_PATH}

make_lock () {
	mkdir $LOCK 2>/dev/null
	return $?
}

clear_lock () {
	rmdir $LOCK 2>/dev/null
	return $?
}


time_ch () {
   time2=$((`date +%s`))
   sec=$(($time2-$time1))

#   if [ $sec -gt 5400 ]
   if [ $sec -gt 1800 ] # 30 min
#   if [ $sec -gt 2400 ] # 40 min
#   if [ $sec -gt 600 ]
   then
        
      HOUR=$((($sec-$sec%3600)/3600))
      MINS=$((($sec%3600-($sec%3600)%60)/60))
      SECS=$((($sec%3600)%60))

      echo -en "Working RRD time: "

      if [ $HOUR -gt 9 ]
      then
        echo -en "$HOUR:"
      else
        echo -en "0$HOUR:"
      fi
      if [ $MINS -gt 9 ]
      then
        echo -en "$MINS:"
      else
        echo -en "0$MINS:"
      fi
      if [ $SECS -gt 9 ]
      then
        echo -en "$SECS"
      else
        echo -en "0$SECS"
      fi

      echo -en " (HH:MI:SS)\n\n\n\n"

   fi


}


# lock process - exit if failed
if ! make_lock
then
        pid1=0
	pid2=`ps -efwww|grep "$RRD"|grep -v grep|awk '{print $2}'`
	
        if [ -z $pid2 ]
        then
           pid=0
        else
           pid=$(($pid1+$pid2))
        fi

        if [ $pid -eq 0 ]
        then
           echo "make_lock failed"
           exit 1
        else
           exit 0
        fi
fi

###
time1=`date +%s`
###

cd $ROOT

file_ext[0]=out
file_ext[1]=cmd

for is_cmd in 0 1
do
	ext=${file_ext[$is_cmd]}
	
	has_files=0
	for fn in `find ${INPUT}/ -name "*.$ext"`;
	do
		#echo file $fn
		if ! mv ${fn} ${TMP}/
		then
			echo "can't move ${fn} to tmp"
		else
			has_files=1
		fi
	done
	
	if [ $has_files -ne 0 ]
	then
		#echo "Parsing.."
		#if $RRD $is_cmd 0 $TMP/ $ext && $RRD $is_cmd 1 $TMP/ $ext
                if $RRD $is_cmd 1 $TMP/ $ext
		then
	
			#echo "Clearing.."
			/usr/bin/find $TMP/ -name "*.$ext" -exec rm -f {} \;
			if [ $? -ne 0 ]
			then
				echo "Can't delete tmp!"
			fi
		else
			echo "Can't process data!"
		fi
	fi
	
done

time_ch

#echo "Remove lock"
if ! clear_lock
then
	echo "Remove lock is failed"
fi

#echo "Finish."

exit 0
