#!/usr/bin/perl -w

#write to log file and look on it size.

BEGIN { 
    push @INC, '/export/home/biller/soft/File-ReadBackwards-1.05/blib/lib/';
}

use File::ReadBackwards;
use Time::Local;

sub readRapsLog;
sub log_write($$);
sub log_rotate($$);

#$| = 1; # buffer off

##START Take dir where script is
my @Pwd = split(/\//,$ENV{'PWD'});
my @SS = split(/\//,$ENV{'_'});
pop(@SS);
if ( "@SS" eq "@Pwd" ) {
    $sDir = $ENV{'PWD'};
} else {
   shift(@Pwd);
   while ( $SS[0] eq ".." ) {
      shift(@SS);
      pop(@Pwd);
   }
   my $sDir = ""; #script dir
   for( my $i=0; $i<=$#Pwd; $i++ ) {
      $sDir=$sDir . "\/" . $Pwd[$i];
   }
   for( $i=0; $i<=$#SS; $i++ ) {
      $sDir=$sDir . "\/" . $SS[$i];
   }
}
##END


my $w_log_file=$sDir . "/raps_speed_log.v3.1.log"; #Log file name
my $w_log_size=10240000; #in bytes
my $w_log_count=10;

my $string="";

my $debug=0;

open(LWFN, ">> $w_log_file") or die("Cannot open $w_log_file\n");

$b1= "#" x 120 ;
#"############################################################################################";
$b2="-" x 118;
#"------------------------------------------------------------------------------------------";

$log_file="/export/home/biller/opt/apache-tomcat-5.5.35/server/webapps/raps/WEB-INF/logs/raps.log";

my $sleep_time=60;
my $interval=0;
if (defined($ARGV[0])){
   chomp($sleep_time=$ARGV[0]);
#   print $sleep_time . "\n";
   if(defined($ARGV[1])){
      chomp($interval=$ARGV[1]);
#      print $interval ."\n";
   }
}



$string=sprintf("%s\n",$b1);
#print $debug ? $string : "" ;
log_write($string,$debug);


readRapsLog($log_file);
foreach $cip (keys %record) {

  if( !defined($tl1{$cip})){
     $tl1{$cip}=$record{$cip}{'recordTime'};
  }
  if( !defined($record{$cip}{'recordTime'})){
     $record{$cip}{'recordTime'} = $tl1{$cip};
  }
  if (!defined($td1{$cip})){
     $td1{$cip}=$time{$cip};
  }
  if (!defined($time{$cip})){
     $time{$cip}=$td1{$cip};
  }

 undef($record{$cip}{'recordTime'});
 undef($time{$cip});
  }


my $FT="true";
my $count=0;
#for ( $n=0; $n<=$ARGV[1]; $n++ ) {
while ($FT eq "true") {
   #sleep(600);
#   sleep($ARGV[0]);
    sleep $sleep_time;


    @aTime = localtime();
    ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset) = ($aTime[0],$aTime[1],$aTime[2],$aTime[3],$aTime[4],$aTime[5]);
    $year = 1900 + $yearOffset; ++$month;
    if ($month < 10) {
             $month = "0" . $month;
    }

   $theTime = "$dayOfMonth.$month.$year $hour:$minute:$second";
   
   $string=sprintf("#date: %-112s#\n#$b2#\n",$theTime);
   #print $debug ? $string : "" ; 
   log_write($string,$debug);


   readRapsLog($log_file);

   foreach $cip ( sort keys %record) {

    if( !defined($tl1{$cip})){
       $tl1{$cip}=$record{$cip}{'recordTime'};
    }
    if( !defined($record{$cip}{'recordTime'})){
       $record{$cip}{'recordTime'} = $tl1{$cip};
    }
    if (!defined($td1{$cip})){
       $td1{$cip}=$time{$cip};
    }
    if (!defined($time{$cip})){
       $time{$cip}=$td1{$cip};
    }

#       $count{$cip}=1;
#    }else{
       $dtl = $record{$cip}{'recordTime'} - $tl1{$cip};
       $dtd = $time{$cip} - $td1{$cip};
       if ( $dtd == 0 ) {
            $dev=0;
       } else {
          #$dev = $dtl/$dtd;
          $dev = sprintf "%.2f", $dtl/$dtd;
       }
       $out="$cip: Delta record time: $dtl;  Delta log time: $dtd;  =>  $dtl/$dtd = $dev;   Log time: $logtime{$cip}";

       $string=sprintf("#%-118s#\n", $out); 
       #print $debug ? $string : "" ; 
       log_write($string,$debug);

       $tl1{$cip}=$record{$cip}{'recordTime'};
       $td1{$cip}=$time{$cip};

       $string=sprintf("#%s#\n",$b2);
       #print $debug ? $string : "" ; 
       log_write($string,$debug);

       undef($record{$cip}{'recordTime'});
       undef($time{$cip});
   }
   $string=sprintf("%s\n",$b1);
   #print $debug ? $string : "" ; 
   log_write($string,$debug);

   $count++;

   if ($interval<$count && $interval!=0) {
      $FT="false";
#      print "$FT $ARGV[1] $count\n";
   }

   my ($device, $inode, $mode, $nlink, $uid, $gid, $rdev, $size,$atime, $mtime, $ctime, $blksize, $blocks) = stat($w_log_file) or return;

   if ( $size >= $w_log_size ) {
      close(LWFN) or die("Cannot close.\n");
      log_rotate($w_log_file,$w_log_count);
      open(LWFN, ">> $w_log_file") or die("Cannot open.\n");
   }

}

close(LWFN);
exit(0);

sub readRapsLog() {
   my $log_file = shift;
   $bw = File::ReadBackwards->new( $log_file ) or  die "can't read $log_file $!" ;
   my $count=0;
   while( defined( $log_line = $bw->readline ) ) {
            if ( $log_line =~ m/^\[DEBUG\] \[(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)\,(\d*)\] \[com\.gldn\.raps\.collector\.AccountingReceiverWorker\] \[CollectorWorker\-\/(.*)\] record received: \[(.*)\]$/i ) {

                 ($YY,$MM,$DD,$HH,$MI,$SS) = ($1,$2-1,$3,$4,$5,$6);
                 $cip = $8;

                 @record = split(/;/,$9);
                 
                 for( $i=0; $i <= $#record; $i++){
                    ($Name, $Value) = split(/=/,$record[$i]);
                    if( $Name eq "recordTime" ){
                        if(!defined($record{$cip}{$Name})){
                           $record{$cip}{$Name}=substr($Value,0,10);
                           $time{$cip} = timelocal($SS,$MI,$HH,$DD,$MM,$YY);
                           ($sec,$min,$hour,$mday,$mon,$year) = localtime(substr($Value,0,10));
                           $Yy=$year+1900;
                           $Mm=$mon+1;
                           $logtime{$cip} = "$Yy-$Mm-$mday $hour:$min:$sec";
                        }
                    }
                 }

            
            $count++;

            if ( $count > 100 ) {
                $bw->close();
                last;
                exit(0);
            }

           }

   }

   return %record, %time,%logtime;
}

sub log_write($$){
   my $string = shift;
   my $debug = shift;
   #print LWFN $string;
   # no buffer write
   syswrite(LWFN,$string,length($string)); # ???
   print $debug ? $string : "" ;
}

sub log_rotate($$) {
#   print "log rotate function\n" ;
   my $filename = shift;
   my $filecount= shift;
#   print "$filename $filecount\n";


   for ( my $i=$filecount-1; $i>=0; $i-- ) {
      my $n = $i==0 ? "" : "." . $i;
      my $nn = $i+1;
#      print "$i - $filename$n => $filename.$nn\n";
      if ( -e "$filename$n" ) {
          #print("rename(\"$filename$n\", \"$filename.$nn\");\n");
          rename("$filename$n", "$filename.$nn") or die("\"$filename$n\", \"$filename.$nn\");\n");

 #     print $i;

      }
   }


}

exit(0);
