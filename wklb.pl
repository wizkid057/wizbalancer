#!/usr/bin/perl

# Read config file
# NAME:LISTEN_PORT[,LISTEN_PORT[,...]]:START_LOCAL_PORT:COUNT

($config) = @ARGV;

if (!$config) {
	print "Must specify config file on command line\n";
	exit;
}

if ( ! -e $config ) {
	print "Config file $config doesnt exist\n";
	exit;
}

open(X,"<$config");

print "# Generated load balancer from config file $config\n";

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


foreach $lb (@lb) {
	for($i=0;$i<$lbcount{$lb};$i++) {
	}
}

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

$f = $pr."\n\n".$f;
print $f;
print "# End generated config\n";

sub cool_header {
	my $s = "";
	my ($lb) = @_;
	for($i=0;$i<length($lb)+6;$i++) { 
		$s .= "#"; 
	}
	$s .= "\n## $lb ##\n"; 
	for($i=0;$i<length($lb)+6;$i++) { 
		$s .= "#"; 
	} 
	$s .= "\n\n";
	return $s;
}

