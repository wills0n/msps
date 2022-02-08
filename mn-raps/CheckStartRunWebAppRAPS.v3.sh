#!/bin/sh
# ToDo:
#    check itself started proccess, if started exit, else continue execution. For check in cron.
#    check "/export/home/biller/opt/apache//bin/httpd" process and restart if need
#    think about start check without terminal !!!

v_restart_flag=0

v_log_file="/export/home/biller/scripts/CheckStartRunWebAppRAPS.v3.log"
v_log_size=10000000
#v_log_size=100  # for test
v_log_rotate=10
v_OutMin_count=10;  # need for write % free mem every 10 min, not every 1 min

lock="/export/home/biller/scripts/CheckStartRunWebAppRAPS.v3.lock"

if [ -f ${lock} ]
then
    s_pid=$(cat ${lock})
    
    #if [ $(ps -p ${s_pid} h | grep $(basename $0) | wc -l) -eq 0 ]
    if [ $(ps -p ${s_pid} h | grep -E "CheckStartRunWebAppRAPS.*sh" | wc -l) -eq 0 ]
    then
        #echo "rm not data"
        rm ${lock}
    else
        #echo "$(ps -p ${s_pid} h)" 
        exit 0
    fi
fi

echo $$  > ${lock}

#CommName=$(basename $0)
#echo ${CommName}

#sleep 60
#if [ $(ps -ef | grep ${CommName} | grep -v grep | wc -l) -gt 1 ]
#then
    # ps -ef | grep ${CommName} | grep -v grep
#    exit
#fi


#rm ${lock}
#exit


while true
do 
    #curl -s -m 3 -H "HTTP_REMOTE_USER: shpakryi" http://mn-raps.vimpelcom.ru:8080/raps/ 1>/dev/null && v_restart_flag=0; 

    vWebAnswerFlag=$(curl -s -m 3 -H "HTTP_REMOTE_USER: shpakryi" http://mn-raps.vimpelcom.ru:8080/raps/ | grep -E '<a href="accounts.do">|<a href="sessions.do">|<a href="archivesessions.do">|<a href="pools.do">|<a href="clusters.do">' | wc -l)
    if [ ${vWebAnswerFlag} -eq 0 ]
    then
        let v_restart_flag++
        echo "Not answered at `date` (${v_restart_flag})" >> ${v_log_file}
    else
        v_restart_flag=0

        #echo "OK ${vWebAnswerFlag} $(/bin/cat /proc/meminfo | /bin/awk '/^MemFree:/ {free=$2};/^Buffers:/ {buffer=$2};/^Cached:/ {cache=$2};/^MemTotal:/ {total=$2}END {printf("%.2f\n",(free+buffer+cache)*100/total)}')%" >> ${v_log_file}

        # Need to output free memory % every 10 min 
        if [ ${v_OutMin_count} -ge 10 ]
        then
            echo "$(date +"%d.%m.%Y %H:%M:%S"): OK ${vWebAnswerFlag} $(/bin/cat /proc/meminfo | /bin/awk '/^MemFree:/ {free=$2};/^Buffers:/ {buffer=$2};/^Cached:/ {cache=$2};/^MemTotal:/ {total=$2}END {printf("Free mem: %.2f\n",(free+buffer+cache)*100/total)}')%" >> ${v_log_file}
            #let ++v_OutMin_count;
            v_OutMin_count=0;
        fi
    fi

    if [ ${v_restart_flag} -ge 6 ] 
    then 
        echo -e "ALARM\n\nRaps not answering on web rigth 5 times, trying to restart process" | /export/home/biller/mail.sh mail VNurmukhametov@spb.beeline.ru 
        echo -e "ALARM\n\nRaps not answering on web rigth 5 times, trying to restart process" >> ${v_log_file}
        cd /export/home/biller/opt/apache-tomcat-5.5.35/bin && ./shutdown.sh
        sleep 30
        rapsPid=$(ps -efwww | grep '/export/home/biller/opt/apache-tomcat-5.5.35/' | grep '/export/home/biller/opt/jre1.6.0_32/bin/java' | grep -v grep | awk '{print $2}')
        #rapsPid=$(ps -efwww | grep '/export/home/biller/opt/apache-tomcat-5.5.35/' | grep '/export/home/biller/soft/jdk1.7.0_04/bin/java' | grep -v grep | awk '{print $2}')
        if [ ! -z ${rapsPid} ]
        then 
            kill ${rapsPid}
            sleep 5
        fi
        rapsPid=$(ps -efwww | grep '/export/home/biller/opt/apache-tomcat-5.5.35/' | grep '/export/home/biller/opt/jre1.6.0_32/bin/java' | grep -v grep | awk '{print $2}')
        #rapsPid=$(ps -efwww | grep '/export/home/biller/opt/apache-tomcat-5.5.35/' | grep '/export/home/biller/soft/jdk1.7.0_04/bin/java' | grep -v grep | awk '{print $2}')
        if [ ! -z ${rapsPid} ]
        then 
            kill -9 ${rapsPid}
            sleep 5
        fi
        ./startup.sh && v_restart_flag=0
        sleep 300
        let v_OutMin_count+=6;
    fi
    sleep 60
    let ++v_OutMin_count;

    # check lock file
    if [ ! -f ${lock} ]
    then
        echo $$ > ${lock}
    fi

    # check log size, rotate
    v_log_file_size=$(ls -l ${v_log_file} | awk '{printf("%d",$5)}')
    
    if [ ${v_log_file_size} -ge ${v_log_size} ]
    then
        if [ -f ${v_log_file}\.1 ]
        then
            for i in $(ls ${v_log_file}\.* | sed -e 's/.*\.\([0-9]\+\)$/\1/g' | sort -nr)
            do
                if [ ${i} -lt ${v_log_rotate} ]
                then
                    let t=i+1
                    #echo "mv ${v_log_file}\.${i} ${v_log_file}\.${t}"  # for test, comment after
                    mv ${v_log_file}\.${i} ${v_log_file}\.${t}
                else
                    #echo "rm ${v_log_file}\.${i}"   # for test, comment after
                    rm ${v_log_file}\.${i}    
                fi
            done
            mv ${v_log_file} ${v_log_file}\.1
        else
            mv ${v_log_file} ${v_log_file}\.1
        fi
    fi
done

rm ${lock}

exit 0
