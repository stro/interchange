UserTag file-info Order name
UserTag file-info attrAlias file name
UserTag file-info addAttr
UserTag file-info Routine <<EOR
sub {
	my ($fn, $opt) = @_;
	if($opt->{server}) {
		$fn = "$Global::VendRoot/$fn"
	}
	elsif($opt->{conf}) {
		$fn = "$Global::ConfDir/$fn"
	}
	elsif($opt->{run}) {
		$fn = "$Global::RunDir/$fn"
	}
	my @stat = stat($fn);
	my %info;
	my @ary;
	my $size  = $stat[7] < 1024
					 ? $stat[7]
					 : ( $stat[7] < 1024 * 1024
						? sprintf ("%.2fK", $stat[7] / 1024)
						: sprintf ("%.2fM", $stat[7] / 1024 / 1024)
						);
	if($opt->{flags}) {
		$opt->{flags} =~ s/\W//g;
		my @flags = split //, $opt->{flags};
		for(@flags) {
			s/(.)/"-$1 _"/ee;
		}
		return join "\t", @flags;
	}
	if($opt->{size}) {
		return $stat[7];
	}
	if($opt->{time}) {
		return $stat[9];
	}
	if($opt->{date}) {
		if($opt->{gmt}) {
			return POSIX::strftime('%c', gmtime($stat[9]));
		}
		else {
			return POSIX::strftime('%c', localtime($stat[9]));
		}
	}
	$opt->{fmt} = '%f bytes, last modified %Y-%m-%d %H:%M:%S'
		if ! $opt->{fmt};
	$opt->{fmt} =~ s/%f/$size/g;
	if($opt->{gmt}) {
		return POSIX::strftime($opt->{fmt}, gmtime($stat[9]));
	}
	else {
		return POSIX::strftime($opt->{fmt}, localtime($stat[9]));
	}
}
EOR

