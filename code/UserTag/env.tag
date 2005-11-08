# Copyright 2004-2005 Interchange Development Group (http://www.icdevgroup.org/)
# Copyright 2001 Ed LaFrance <edl@newmediaems.com>
# Licensed under the GNU GPL v2. See file LICENSE for details.
# $Id: env.tag,v 1.10 2005-11-08 18:14:42 jon Exp $

Usertag env Order      arg
Usertag env PosNumber  1
UserTag env attrAlias  name arg
UserTag env Version    $Revision: 1.10 $
Usertag env Routine    <<EOR
sub {
	my $arg = shift;
	my $env = ::http()->{env};
	my $out;
	if (! $arg) {
		$out = "<table cellpadding='2' cellspacing='1' border='1'>\n";
		foreach ((keys %$env)) {
			$out .= "<tr><td><b>$_</b></td><td>";
			$out .= "$env->{$_}</td>\n</tr><tr>\n";
		}
		$out .= "</table>\n";
	}
	else {
		$out = $env->{$arg};
	}
	return $out;
}
EOR
