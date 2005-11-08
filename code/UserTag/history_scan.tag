# Copyright 2002-2005 Interchange Development Group (http://www.icdevgroup.org/)
# Licensed under the GNU GPL v2. See file LICENSE for details.
# $Id: history_scan.tag,v 1.19 2005-11-08 18:14:42 jon Exp $

UserTag history-scan Order   find exclude default
UserTag history-scan addAttr
UserTag history-scan Version $Revision: 1.19 $
UserTag history-scan Routine <<EOR
my %var_exclude = ( qw/
		mv_credit_card_number 1
		mv_pc                 1
		mv_session_id         1
		expand                1
		collapse              1
		expandall             1
		collapseall           1
		/);

sub {
	my ($find, $exclude, $default, $opt) = @_;
	$default ||= $Vend::Cfg->{SpecialPage}{catalog};
	my $ref = $Vend::Session->{History};

	use vars qw/$CGI $Tag/;

	$opt->{size_limit} ||= '1024';
	unless ($ref) {
		return $default if $opt->{pageonly};
		return $Tag->area($default);
	}
	my ($hist, $href, $cgi);
	$exclude = qr/$exclude/ if $exclude;
	my $include;
	$include = qr/$opt->{include}/ if $opt->{include};
	for (my $i = $#$ref - abs($opt->{count}); $i >= 0; $i--) {
		next if $ref->[$i][0] eq 'expired';
		if ($exclude and $ref->[$i][0] =~ $exclude) {
			next;
		}
		if ($include and $ref->[$i][0] !~ $include) {
			next;
		}
		if($find) {
			next unless $ref->[$i][0] =~ /$find/;
		}
		($href, $cgi) = @{$ref->[$i]};
		last;
	}
	unless ($href) {
		return $default if $opt->{pageonly};
		return $Tag->area($default);
	}
	$href =~ s|/+|/|g;
	$href =~ s|^/||;
	if ($opt->{pageonly}) {
		return $href;
	}
	my $form = '';
	if($opt->{var_exclude}) {
		for(split /[\s,\0]+/, $opt->{var_exclude}) {
			$var_exclude{$_} = 1;
		}
	}
	for(grep !$var_exclude{$_}, keys %$cgi) {
		$form .= "\n$_=";
		$form .= join("\n$_=", split /\0/, $cgi->{$_});
	}
	$form .= "\n$opt->{form}" if $opt->{form};
	my $string = $Tag->area( {
								href => $href,
								form => $form,
								no_session => $opt->{no_session},
							} );
	my $len = length($string);
	if($len > $opt->{size_limit}) {
		$len = $Tag->filter('commify.0', $len);
		my $m = errmsg(
					'Huge URL (%s bytes) exceeds %s byte limit, returning blank.',
					$len,
					$opt->{size_limit},
				);
		$Tag->error({ name => 'history-scan', set => $m })
			if $opt->{debug};
		return undef;
	}
	return $string;
}
EOR
