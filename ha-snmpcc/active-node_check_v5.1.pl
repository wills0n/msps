#!/export/home/biller/opt/perl/bin/perl -w

# Last modified: Tue Feb 27 14:45 MSD 2015
# add mail send

use strict;
use DBI;
use POSIX qw(strftime);
use MIME::Lite;


#$ENV{'LD_ASSUME_KERNEL'} = '2.2.5';
#$ENV{'ORACLE_BASE'} = '/opt/oracle';
#$ENV{'ORACLE_HOME'} = $ENV{'ORACLE_BASE'}."/product/8.1.7";
#$ENV{'ORA_NLS33'} = $ENV{'ORACLE_HOME'}."/ocommon/nls/admin/data";
#$ENV{'LC_CTYPE'} = 'ru_RU.KOI8-R';
#$ENV{'NLS_LANG'} = 'AMERICAN_AMERICA.CL8KOI8R';
#$ENV{'PATH'} = $ENV{'PATH'}.":".$ENV{'ORACLE_HOME'}."/bin";

#my $MAX_TIMEOUT = 24 * 3600;		# no more than 24 hours
my $MAX_TIMEOUT = 1;		# no more than 24 hours (Oracle)
my %nodes = ();
my ($dbh,$sth,$q);
#$dbh = DBI->connect("DBI:Oracle:ipware", "biller", "6i_3v8d4j")
$dbh = DBI->connect("DBI:Oracle:", q{biller/6i_3v8d4j@(DESCRIPTION=(ADDRESS_LIST=(FAILOVER=TRUE)(ADDRESS=(PROTOCOL=TCP)(HOST=mn-ipware-db.vimpelcom.ru)(PORT=1521))(ADDRESS=(PROTOCOL=TCP)(HOST=dr-ipware-db.vimpelcom.ru)(PORT=1521)))(CONNECT_DATA=(SERVICE_NAME=IPWAREDB)))},"")
        or die("Cannot connect to IPWARE: $DBI::errstr\n");

# take list of nodes from snmp node list 
$q = q{
    SELECT NODE_NAME as name, NODE_IP as node_ip, NODE_COMMUNITY as comm
    FROM IDB_NODE_V
    WHERE NODE_ID != 0
        AND NODE_SNMPLOG = 't'
        AND NODE_COMMUNITY IS NOT NULL
    UNION
    SELECT EQ_NAME as name, EQ_IPADDR as node_ip, EQ_COMMUNITY as comm
    FROM IDB_MGN_NODE_V
    WHERE EQ_TYPE != 0
        AND EQ_ID != 0
        AND EQ_COMMUNITY IS NOT NULL
        };

$sth = $dbh->prepare($q);
$sth->execute();

while( my $href = $sth->fetchrow_hashref ) {

        $href->{'NODE_IP'} =~ s/\s+//g;
	my $name = $href->{'NAME'} || '';

	$nodes{$href->{'NODE_IP'}}{'name'} = "$name";

}

$sth->finish();

my $qq = q{
           select n.node_id, n.node_ip, n.descr, to_char(t.last_seen,'YYYY-MM-DD HH24:Mi:SS') tdate
           from nodes n, ports p, port_last t
           where p.port_name = 'Uptime'
             and p.port_id = t.port_id
             and t.last_seen < (sysdate - ?)
             and n.node_id = p.node_id
           order by t.last_seen,n.node_ip
         };


my $select = $dbh->prepare($qq);


$select->execute($MAX_TIMEOUT);

my %Line = ();
while(my $href = $select->fetchrow_hashref() ) {

	if ( exists $nodes{$href->{'NODE_IP'}} ){
		$Line{$href->{'TDATE'}}{$href->{'NODE_IP'}} = $nodes{$href->{'NODE_IP'}}{'name'};
	}
}

my $vCount = 0;
my $NodeTable = "";
printf("%-20s%-50s  %s\n",'NODE IP','NODE NAME','LAST DATE');
$NodeTable .= sprintf("%-18s  %-50s  %s\n",'NODE IP','NODE NAME','LAST DATE');
foreach my $vDate (sort {$b cmp $a} keys %Line){
    foreach my $vIP (sort keys %{$Line{$vDate}}){
        printf("%-18s  %-50s  %s\n",$vIP,$Line{$vDate}{$vIP},$vDate);
        $NodeTable .= sprintf("%-18s  %-50s  %s\n",$vIP,$Line{$vDate}{$vIP},$vDate);
        ++$vCount;
    }
}


$select->finish();
$dbh->disconnect();


# Send mail through mailhost.vimpelcom.ru, only <name>@beeline.ru
my $From = 'YuShpak@beeline.ru';
#my $To = 'IShcherbo@beeline.ru,AGAndrosov@beeline.ru,EKlimov@beeline.ru,SKoshelev@beeline.ru,YuShpak@beeline.ru';
my $To = 'YuShpak@beeline.ru';
my $Subject = 'SNMP Nodes Check';


my $MSGBODY = qq{
                 <HTML>
                     <BODY>
                         rows: $vCount
                         <BR><BR>
                         <PRE>$NodeTable</PRE>
                    </BODY>
                 </HTML>
                };

my $msg = MIME::Lite->new(
            From        =>  $From,
            To          =>  $To,
            Subject     =>  $Subject,
            Type => 'HTML',
            Data => $MSGBODY
);


$msg->send('smtp', 'mailhost.vimpelcom.ru', Timeout => 60 );
