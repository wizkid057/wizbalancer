#!/usr/bin/perl

# Read config file
# NAME:LISTEN_PORT[,LISTEN_PORT[,...]]:START_LOCAL_PORT:COUNT

($config) = @ARGV;

$IPSET = "/usr/sbin/ipset";
$IPTABLES = "/sbin/iptables";

if (!$config) {
	print "Must specify config file on command line\n";
	exit;
}

if ( ! -e $config ) {
	print "Config file $config doesnt exist\n";
	exit;
}

open(X,"<$config");

( $ss, $mm, $hh, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime();
$date = sprintf( "%d-%02d-%02d %02d:%02d:%02d", ( $year += 1900, $mon += 1, $mday, $hh, $mm, $ss ) );

print cool_header("iptables load balancing script\nby wizkid057\n\nGenerated load balancer from config file $config\n$date");

while (<X>) {
	chomp($_);
	if ((substr($_,0,1) ne "#") && (length($_) > 0)) {
		($name,$ports,$start_port,$count) = split(/\:/,$_);
		push(@lb,$name);
		$lbports{$name} = $ports;
		$lbstart_port{$name} = $start_port;
		$lbcount{$name} = $count;

		print "# Service $name with listen ports $ports and $count local ports starting at $start_port\n";

	}
}

print "\n";

$h = cool_header("CHAIN DEFS");
foreach $lb (@lb) {
	push(@c,"LOAD_BALANCE_".$lb);
	push(@c,"LOAD_BALANCE_".$lb."_CLASSIFY");
	for($i=0;$i<$lbcount{$lb};$i++) {
		push(@c,"LB_".$lb."_CLASSIFY_".chr(ord('A')+$i));
		push(@l,"lb_".$lb."_".chr(ord('A')+$i));
	}
}
foreach $c (@c) {
	$h.="-N $c\n";
	$h.="-F $c\n";
}
$h.="\n";

$pr = cool_header("PREROUTING");
$pr .= "-A PREROUTING ! -i lo -j LOAD_BALANCE\n";
foreach $lb (@lb) {
	# prerouting section...
	@ports = split(/\,/,$lbports{$lb});
	if (scalar(@ports) > 1) {
		$portline = "-m multiport --dports ";
		foreach $p (@ports) { $portline .= $p . ","; }
		$portline = substr($portline,0,length($portline)-1);
	} else {
		$portline = "--dport ".$lbports{$lb};
	}

	$pr .= "-A LOAD_BALANCE -p tcp ".$portline." -j LOAD_BALANCE_".$lb."\n";

}

$f = "";
foreach $lb (@lb) {
	$t = cool_header($lb);

	for($i=0;$i<$lbcount{$lb};$i++) {
		$t .= "-A LOAD_BALANCE_".$lb." -p tcp -m set --match-set lb_".$lb."_".chr(ord('A')+$i)." src -j LB_".$lb."_CLASSIFY_".chr(ord('A')+$i)."\n";
	}


	$t .= "-A LOAD_BALANCE_".$lb." -j LB_".$lb."_CLASSIFY\n";
	for($i=0;$i<$lbcount{$lb}-1;$i++) {
		$t .= "-A LB_".$lb."_CLASSIFY -m statistic --mode random --probability ".sprintf("%.10f",(1/($lbcount{$lb}-$i)))." -j LB_".$lb."_CLASSIFY_".chr(ord('A')+$i)."\n";
	}
	$t .= "-A LB_".$lb."_CLASSIFY -j LB_".$lb."_CLASSIFY_".chr(ord('A')+$i)."\n";

	for($i=0;$i<$lbcount{$lb};$i++) {
		$t .= "-A LB_".$lb."_CLASSIFY_".chr(ord('A')+$i)." -j SET --add-set lb_".$lb."_".chr(ord('A')+$i)." src --exist\n";
		$t .= "-A LB_".$lb."_CLASSIFY_".chr(ord('A')+$i)." -p tcp -j REDIRECT --to-ports ".($lbstart_port{$lb}+$i)."\n";
	}	

	$t .= "\n";
	$f .= $t;
}

print cool_header("IPSETS");

foreach $l (@l) {
	print $IPSET." create $l hash:ip netmask 28 maxelem 65536 hashsize 2048 timeout 43200\n";
}
print "\n";
$f = $h.$pr."\n\n".$f;

@p = split(/\n/,$f);
foreach $p (@p) {
	if (substr($p,0,1) eq "-") {
		print $IPTABLES." ".$p;
	} else {
		print $p;
	}
	print "\n";
}
print "\n# Done\n\n";

sub cool_header {
	my $s = "";
	my ($lb) = @_;

	my @lines = split(/\n/,$lb);
	$longest = 0;
	my $line = "";
	foreach $line (@lines) {
		if (length($line) > $longest) { $longest = length($line); }
	}

	for($i=0;$i<$longest+6;$i++) { 
		$s .= "#"; 
	}
	$s .= "\n";

	foreach $line (@lines) {
		if (length($line) < $longest) {
			for($i=length($line);$i<$longest;$i++) { $line.=" "; }
		}
		$s .= "## $line ##\n";
	}
	for($i=0;$i<$longest+6;$i++) { 
		$s .= "#"; 
	} 
	$s .= "\n\n";
	return $s;
}

