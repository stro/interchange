# Vend::Config - Configure Interchange
#
# $Id: Config.pm,v 2.81 2002-11-15 13:43:10 mheins Exp $
#
# Copyright (C) 1996-2002 Red Hat, Inc. <interchange@redhat.com>
#
# This program was originally based on Vend 0.2 and 0.3
# Copyright 1995 by Andrew M. Wilcox <amw@wilcoxsolutions.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA  02111-1307  USA.

package Vend::Config;
require Exporter;

@ISA = qw(Exporter);

@EXPORT		= qw( config global_config config_named_catalog );

@EXPORT_OK	= qw( get_catalog_default get_global_default parse_time parse_database);

use strict;
use vars qw(
			$VERSION $C
			@Locale_directives_ary @Locale_directives_scalar
			@Locale_directives_code
			@Locale_directives_currency @Locale_keys_currency
			$GlobalRead  $SystemCodeDone $SystemGroupsDone $CodeDest
			);
use Safe;
use Fcntl;
use Vend::Parse;
use Vend::Util;
use Vend::Data;

$VERSION = substr(q$Revision: 2.81 $, 10);

my %CDname;

for( qw(search refresh cancel return secure unsecure submit control checkout) ) {
	$Global::LegalAction{$_} = 1;
}

@Locale_directives_currency = (
qw/
		CommonAdjust
		PriceCommas
		PriceDivide
		PriceField
		PriceDefault
		SalesTax
		Levies
		TaxShipping

/	);

@Locale_keys_currency = (
qw/
	currency_symbol
	frac_digits
	int_curr_symbol
	int_frac_digits
	mon_decimal_point
	mon_grouping
	price_picture
	mon_thousands_sep
	n_cs_precedes
	negative_sign
	p_cs_precedes
	p_sep_by_space
	positive_sign

/   );

@Locale_directives_scalar = (
qw/
		AutoEnd
        Autoload
		CategoryField
        CommonAdjust
		DescriptionField
        HTMLsuffix
		ImageDir
		ImageDirSecure
		PageDir
		PriceCommas
		PriceDefault
        PriceDivide
        PriceField
		SalesTax
        SpecialPageDir
		StaticPath
		TaxShipping

/   );

@Locale_directives_ary = (
qw/
	AutoModifier
	Levies
	PriceAdjustment
	ProductFiles
	UseModifier
/   );

# These are extra routines that are run if certain directives are
# updated
# Form:
#
# [ 'Directive', \&routine, [ @args ] ],
# 
# @args are optional.
# 
@Locale_directives_code = (
	[ 'ProductFiles', \&Vend::Data::update_productbase ],
);

my %HashDefaultBlank = (qw(
					SOAP			1
					Mail			1
					DatabaseDefault	1
					Accounting		1
					Levy			1
				));

my %DumpSource = (qw(
					SpecialPage			1
					GlobalSub			1
				));

my %DontDump = (qw(
					GlobalSub			1
					SpecialPage			1
				));

my %UseExtended = (qw(
					Catalog				1
					SubCatalog			1
					Variable			1
				));

my $StdTags;

use vars qw/ $configfile /;

### This is unset when interchange script is run, so that the default
### when used by an external program is not to compile subroutines
$Vend::ExternalProgram = 1;

# Report a fatal error in the configuration file.
sub config_error {
	my $msg = shift;
	if(@_) {
		$msg = errmsg($msg, @_);
	}

	local($^W);
	$msg = errmsg("%s\nIn line %s of the configuration file '%s':\n%s\n",
			$msg,
			$.,
			$configfile,
			$Vend::config_line,
	);
	if ($Vend::ExternalProgram) {
		warn "$msg\n" unless $Vend::Quiet;
	}
	else {
		logGlobal({level => 'warn'}, $msg);
		die "$msg\n";
	}
}

sub config_warn {
	my $msg = shift;
	if(@_) {
		$msg = errmsg($msg, @_);
	}

	local($^W);

	::logGlobal({level => 'notice'},
				"%s\nIn line %s of the configuration file '%s':\n%s\n",
						$msg,
						$.,
						$configfile,
						$Vend::config_line,
	);
}

sub setcat {
	$C = $_[0] || $Vend::Cfg;
}

sub global_directives {

	my $directives = [
#   Order is not really important, catalogs are best first

#   Directive name      Parsing function    Default value

	['RunDir',			 'root_dir',     	 $Global::RunDir || 'etc'],
	['DebugFile',		  undef,     	     ''],
	['ConfigDir',		  undef,	         'etc/lib'],
	['ConfigDatabase',	 'config_db',	     ''],
	['ConfigParseComments',	'yesno',		'Yes'],
	['ConfigAllBefore',	 'array',	         "$Global::VendRoot/catalog_before.cfg"],
	['ConfigAllAfter',	 'array',	         "$Global::VendRoot/catalog_after.cfg"],
	['Message',          'message',           ''],
	['Capability',		 'capability',		 ''],
	['Require',			 'require',			 ''],
	['Suggest',			 'suggest',			 ''],
	['VarName',          'varname',           ''],
	['Windows',          undef,               $Global::Windows || ''],
	['LockType',         undef,           	  $Global::Windows ? 'none' : ''],
	['DumpStructure',	 'yesno',     	     'No'],
	['DumpAllCfg',	     'yesno',     	     'No'],
	['DisplayErrors',    'yesno',            'No'],
	['DeleteDirective', sub {
							my $c = $Global::DeleteDirective || {};
							shift;
							my @sets = map { lc $_ } split /[,\s]+/, shift;
							@{$c}{@sets} = map { 1 } @sets;
							return $c;
						 },            ''],
	['Inet_Mode',         'yesno',            (
												defined $Global::Inet_Mode
												||
												defined $Global::Unix_Mode
												)
												? ($Global::Inet_Mode || 0) : 'No'],
	['Unix_Mode',         'yesno',            (
												defined $Global::Inet_Mode
												||
												defined $Global::Unix_Mode
												)
												? ($Global::Unix_Mode || 0) : 'Yes'],
	['TcpMap',           'hash',             ''],
	['Environment',      'array',            ''],
	['TcpHost',           undef,             'localhost 127.0.0.1'],
	['AcceptRedirect',	 'yesno',			 'No'],
	['SendMailProgram',  'executable',		 [
												$Global::SendMailLocation,
											   '/usr/sbin/sendmail',
											   '/usr/lib/sendmail',
											   'Net::SMTP',
											  ]
										  ],
	['EncryptProgram',  'executable',		 [ 'gpg', 'pgpe', 'none', ] ],
	['PIDfile',     	  undef,             "$Global::VendRoot/etc/$Global::ExeName.pid"],
	['SocketFile',     	 'array',            "$Global::VendRoot/etc/socket"],
	['SocketPerms',      'integer',          0600],
	['SOAP',     	     'yesno',            'No'],
	['SOAP_Socket',       'array',            ''],
	['SOAP_Perms',        'integer',          0600],
	['MaxRequestsPerChild','integer',           50],
	['StartServers',      'integer',          0],
	['PreFork',		      'yesno',            0],
	['SOAP_MaxRequests', 'integer',           50],
	['SOAP_StartServers', 'integer',          1],
	['SOAP_Host',         undef,              'localhost 127.0.0.1'],
	['IPCsocket',		 undef,	     	 	 "$Global::VendRoot/etc/socket.ipc"],
	['HouseKeeping',     'integer',          60],
	['Mall',	          'yesno',           'No'],
	['TagGroup',		 'tag_group',		 $StdTags],
	['TagInclude',		 'tag_include',		 'ALL'],
	['ActionMap',		 'action',			 ''],
	['FormAction',		 'action',			 ''],
	['MaxServers',       'integer',          10],
	['GlobalSub',		 'subroutine',       ''],
	['Database',		 'database',         ''],
	['FullUrl',			 'yesno',            'No'],
	['Locale',			 'locale',            ''],
	['HitCount',		 'yesno',            'No'],
	['IpHead',			 'yesno',            'No'],
	['IpQuad',			 'integer',          '1'],
	['TagDir',      	 'root_dir_array', 	 'code'],
	['TemplateDir',      'root_dir_array', 	 ''],
	['DomainTail',		 'yesno',            'Yes'],
	['AcrossLocks',		 'yesno',            'No'],
	['RobotUA',			 'list_wildcard',      ''],
	['RobotIP',			 'list_wildcard_full', ''],
	['RobotHost',		 'list_wildcard_full', ''],
	['HostnameLookups',	 'yesno',            'No'],
	['TolerateGet',		 'yesno',            'No'],
	['PIDcheck',		 'integer',          '0'],
	['LockoutCommand',    undef,             ''],
	['SafeUntrap',       'array',            'ftfile sort'],
	['SafeTrap',         'array',            ':base_io'],
	['NoAbsolute',		 'yesno',			 'No'],
	['AllowGlobal',		 'boolean',			 ''],
	['AddDirective',	 'directive',		 ''],
	['UserTag',			 'tag',				 ''],
	['CodeDef',			 'mapped_code',		 ''],
	['HotDBI',			 'boolean',			 ''],
	['AdminUser',		  undef,			 ''],
	['AdminHost',		  undef,			 ''],
	['HammerLock',		 'integer',     	 30],
	['DataTrace',		 'integer',     	 0],
	['ShowTimes',		 'yesno',	     	 0],
	['ErrorFile',		  undef,     	     undef],
	['SysLog',			 'hash',     	     undef],
	['Logging',			 'integer',     	 0],
	['CheckHTML',		  undef,     	     ''],
	['UrlSepChar',		 'url_sep_char',     '&'],
	['Variable',	  	 'variable',     	 ''],
	['Profiles',	  	 'profile',     	 ''],
	['Catalog',			 'catalog',     	 ''],
	['SubCatalog',		 'catalog',     	 ''],
	['AutoVariable',	 'autovar',     	 'UrlJoiner'],

	];
	return $directives;
}


sub catalog_directives {

	my $directives = [
#   Order is somewhat important, the first 6 especially

#   Directive name      Parsing function    Default value

	['ErrorFile',        undef,              'error.log'],
	['ActionMap',		 'action',			 ''],
	['FormAction',		 'action',			 ''],
	['ItemAction',		 'action',			 ''],
	['PageDir',          'relative_dir',     'pages'],
	['SpecialPageDir',   undef,     		 'special_pages'],
	['ProductDir',       'relative_dir',     'products'],
	['OfflineDir',       'relative_dir',     'offline'],
	['ConfDir',          'relative_dir',	 'etc'],
	['ConfigDir',        'relative_dir',	 'config'],
	['TemplateDir',      'dir_array', 		 ''],
	['ConfigDatabase',	 'config_db',	     ''],
	['ConfigParseComments',	'yesno',		'Yes'],
	['Require',			 'require',			 ''],
	['Suggest',			 'suggest',			 ''],
	['Message',          'message',           ''],
	['Variable',	  	 'variable',     	 ''],
	['VarName',          'varname',           ''],
	['Limit',			 'hash',    'option_list 5000 chained_cost_levels 32'],
	['ScratchDefault',	 'hash',     	 	 ''],
	['Profile',			 'locale',     	 	 ''],
	['ValuesDefault',	 'hash',     	 	 ''],
	['ProductFiles',	 'array_complete',  'products'],
	['PageTables',		 'array_complete',  ''],
	['PageTableMap',	 'hash',			qq{
												expiration_date expiration_date
												show_date       show_date
												page_text       page_text
												base_page       base_page
												code            code
											}],
	['DisplayErrors',    'yesno',            'No'],
	['ParseVariables',	 'yesno',     	     'No'],
	['SpecialPage',		 'special', 'order ord/basket results results search results flypage flypage'],
	['DirectoryIndex',	 undef,				 ''],
	['Sub',				 'subroutine',       ''],
	['VendURL',          'url',              undef],
	['SecureURL',        'url',              undef],
	['History',          'integer',          0],
	['OrderReport',      undef,       		 'etc/report'],
	['ScratchDir',       'relative_dir',     'tmp'],
	['SessionDB',  		 undef,     		 ''],
	['SessionType', 	 undef,     		 'File'],
	['SessionDatabase',  'relative_dir',     'session'],
	['SessionLockFile',  undef,     		 'etc/session.lock'],
	['DatabaseDefault',  'hash',	     	 ''],
	['DatabaseAuto',	 'dbauto',	     	 ''],
	['Database',  		 'database',     	 ''],
	['Autoload',		 undef,		     	 ''],
	['AutoEnd',			 undef,		     	 ''],
	['Replace',			 'replace',     	 ''],
	['Member',		  	 'variable',     	 ''],
	['WritePermission',  'permission',       'user'],
	['ReadPermission',   'permission',       'user'],
	['SessionExpire',    'time',             '1 hour'],
	['SaveExpire',       'time',             '30 days'],
	['MailOrderTo',      undef,              undef],
	['SendMailProgram',  'executable',		$Global::SendMailProgram],
	['PGP',              undef,       		 ''],
# GLIMPSE
	['Glimpse',          'executable',       ''],
# END GLIMPSE
	['Locale',           'locale',           ''],
	['Route',            'locale',           ''],
	['LocaleDatabase',   'configdb',         ''],
	['ExecutionLocale',   undef,             'C'],
	['DefaultLocale',     undef,             ''],
	['DbDatabase',        'dbdatabase',        ''],
	['RouteDatabase',     'configdb',        ''],
	['DirectiveDatabase', 'dbconfig',        ''],
	['VariableDatabase',  'dbconfig',        ''],
	['DirConfig',         'dirconfig',        ''],
	['FileDatabase',	 undef,				 ''],
	['RequiredFields',   undef,              ''],
	['NoSearch',         'wildcard',         'userdb'],
	['OrderCounter',	 undef,     	     ''],
	['MimeType',         'hash',             ''],
	['AliasTable',	 	 undef,     	     ''],
	['ImageAlias',	 	 'hash',     	     ''],
	['TableRestrict',	 'hash',     	     ''],
	['Filter',		 	 'hash',     	     ''],
	['ImageDirSecure',   undef,     	     ''],
	['ImageDirInternal', undef,     	     ''],
	['ImageDir',	 	 undef,     	     ''],
	['UseCode',		 	 undef,     	     'yes'],
	['SetGroup',		 'valid_group',      ''],
	['UseModifier',		 'array',     	     ''],
	['AutoModifier',	 'array',     	     ''],
	['MaxQuantityField', undef,     	     ''],
	['MinQuantityField', undef,     	     ''],
	['LogFile', 		  undef,     	     'etc/log'],
	['Pragma',		 	 'boolean_value',    ''],
	['DynamicData', 	 'boolean',     	 ''],
	['NoImport',	 	 'boolean',     	 ''],
	['NoImportExternal', 'yesno',	     	 'no'],
	['CommonAdjust',	 undef,  	     	 ''],
	['PriceAdjustment',	 'array',  	     	 ''],
	['PriceBreaks',	 	 'array',  	     	 ''],
	['PriceDivide',	 	 undef,  	     	 1],
	['PriceCommas',		 'yesno',     	     'Yes'],
	['MixMatch',		 'yesno',     	     'No'],
	['DifferentSecure',	 'boolean',  	     ''],
	['AlwaysSecure',	 'boolean',  	     ''],
	['Password',         undef,              ''],
	['AdminSub',		 'boolean',			 ''],
	['ExtraSecure',		 'yesno',     	     'No'],
	['FallbackIP',		 'yesno',     	     'No'],
	['WideOpen',		 'yesno',     	     'No'],
	['Promiscuous',		 'yesno',     	     'No'],
	['Cookies',			 'yesno',     	     'Yes'],
	['CookieName',		 undef,     	     ''],
	['CookiePattern',	 'regex',     	     '[-\w:.]+'],
	['CookieLogin',      'yesno',            'No'],
	['CookieDomain',     undef,              ''],
	['MasterHost',		 undef,     	     ''],
	['UserTag',			 'tag', 	    	 ''],
	['CodeDef',			 'mapped_code',    	 ''],
	['RemoteUser',		 undef,     	     ''],
	['TaxShipping',		 undef,     	     ''],
	['FractionalItems',  'yesno',			 'No'],
	['SeparateItems',    'yesno',			 'No'],
	['PageSelectField',  undef,     	     ''],
	['NonTaxableField',  undef,     	     ''],
	['CyberCash',	 	 'warn',     	     ''],
	['CreditCardAuto',	 'yesno',     	     'No'],
	['NoCache',	     	 'boolean',    	     ''],
	['ClearCache',	     'yesno',     	     'No'],
	['FormIgnore',	     'boolean',    	     ''],
	['EncryptProgram',	 undef,     	     $Global::EncryptProgram || ''],
	['EncryptKey',		 undef,     	     ''],
	['AsciiTrack',	 	 undef,     	     ''],
	['TrackFile',	 	 undef,     	     ''],
	['TrackPageParam',	 'hash',     	     ''],
	['SalesTax',		 undef,     	     ''],
	['SalesTaxFunction', undef,     	     ''],
	['StaticDBM',  	 	 undef,     	     ''],
	['Static',   	 	 'yesno',     	     'No'],
	['StaticAll',		 'yesno',     	     'No'],
	['StaticDepth',		 undef,     	     '1'],
	['StaticFly',		 'yesno',     	     'No'],
	['StaticLogged',	 'yesno',     	     'No'],
	['StaticDir',		 undef,     	     ''],
	['StaticIndex',		 undef,     	     ''], 					  
	['StaticSessionDefault',	 'hash',     ''],
	['StaticTrack',		 undef,     	     ''],
	['SOAP',			 'yesno',			 'No'],
	['SOAP_Enable',		 'hash',			 ''],
	['UserDB',			 'locale',	     	 ''], 
	['UserDatabase',	 undef,		     	 ''],  #undocumented
	['RobotLimit',		 'integer',		      0],
	['OrderLineLimit',	 'integer',		      0],
	['StaticPage',		 'boolean',     	     ''],
	['StaticPath',		 undef,     	     '/'],
	['StaticPattern',	 'regex',     	     ''],
	['StaticSuffix',	 undef,     	     '.html'],
	['HTMLsuffix',	     undef,     	     '.html'],
	['CustomShipping',	 undef,     	     ''],
	['DefaultShipping',	 undef,     	     'default'],
	['UpsZoneFile',		 undef,     	     ''],
	['OrderProfile',	 'profile',     	 ''],
	['SearchProfile',	 'profile',     	 ''],
	['OnFly',		 	 undef,     	     ''],
	['HTMLmirror',		 'yesno',            'No'],
	['CategoryField',    undef,              'category'],
	['DescriptionField', undef,              'description'],
	['PriceDefault',	 undef,              'price'],
	['PriceField',		 undef,              'price'],
	['Cron',		 	 'hash',     	 	 ''],
	['Shipping',         'locale',           ''],
	['Accounting',	 	 'locale',     	 	 ''],
	['Levies',		 	 'array',     	 	 ''],
	['Levy',		 	 'locale',     	 	 ''],
	['AutoVariable',	 'autovar',     	 ''],

	];

	push @$directives, @$Global::AddDirective
		if $Global::AddDirective;
	return $directives;
}

sub get_parse_routine {
	my $parse = shift
		or return undef;
	my $routine;
	if(ref $parse eq 'CODE') {
		$routine = $parse;
	}
	else {
		no strict 'refs';
		$routine = \&{'parse_' . $parse};
	}

	if(ref($routine) ne 'CODE') {
		config_error('Unknown parse routine %s', "parse_$parse");
	}

	return $routine;
	
}

sub set_directive {
	my ($directive, $value, $global) = @_;
	my $directives;

	if($global)	{ $directives = global_directives(); }
	else		{ $directives = catalog_directives(); }

	my ($d, $dir, $parse);
	no strict 'refs';
	foreach $d (@$directives) {
		next unless (lc $directive) eq (lc $d->[0]);
		$parse = get_parse_routine($d->[1]);
		$dir = $d->[0];
		$value = $parse->($dir, $value)
			if $parse;
		last;
	}
	return [$dir, $value] if defined $dir;
	return undef;
}


sub get_catalog_default {
	my ($directive) = @_;
	my $directives = catalog_directives();
	my $value;
	for(@$directives) {
		next unless (lc $directive) eq (lc $_->[0]);
		$value = $_->[2];
	}
	return undef unless defined $value;
	return $value;
}

sub get_global_default {
	my ($directive) = @_;
	my $directives = global_directives();
	my $value;
	for(@$directives) {
		next unless (lc $directive) eq (lc $_->[0]);
		$value = $_->[2];
	}
	return undef unless defined $value;
	return $value;
}

sub evaluate_ifdef {
	my ($ifdef, $reverse, $global) = @_;
#::logDebug("ifdef '$ifdef'");
	my $status;
	$ifdef =~ /^\s*(\@?)(\w+)\s*(.*)/;
	$global = $1 || $global || undef;
	my $var  = $2;
	my $cond = $3;
	my $var_ref = ! $global ? $C->{Variable} : $Global::Variable;
#::logDebug("Variable value '$var_ref->{$var}'");
	if (! $cond) {
		$status = ! (not $var_ref->{$var});
	}
	elsif ($cond) {
		my $val = $var_ref->{$var} || '';
		my $safe = new Safe;
		my $code = "q{$val}" . " " . $cond;
		$status = $safe->reval($code);
		if($@) {
			config_warn(
				errmsg("Syntax error in ifdef evaluation at line %s of %s",
						$.,
						$configfile,
					),
			);
			$status = '';
		}
	}
#::logDebug("ifdef status '$status', reverse=" . !(not $reverse));
	return $reverse ? ! $status : $status;
}

# This is what happens when ParseVariables is true
sub substitute_variable {
	my($val) = @_;
	1 while $val =~ s/__([A-Z][A-Z_0-9]*?[A-Z0-9])__/$C->{Variable}->{$1}/g;
	# Only parse once for globals so they can contain other
	# global and catalog variables
	$val =~ s/\@\@([A-Z][A-Z_0-9]+[A-Z0-9])\@\@/$Global::Variable->{$1}/g;
	return $val;
}

# Parse the configuration file for directives.  Each directive sets
# the corresponding variable in the Vend::Cfg:: package.  E.g.
# "DisplayErrors No" in the config file sets Vend::Cfg->{DisplayErrors} to 0.
# Directives which have no defined default value ("undef") must be specified
# in the config file.

my($directives, $directive, %parse);

sub config {
	my($catalog, $dir, $confdir, $subconfig, $existing, $passed_file) = @_;
	my($d, $parse, $var, $value, $lvar);

	if(ref $existing eq 'HASH') {
#::logDebug("existing=$existing");
		$C = $existing;
	}
	else {
		undef $existing;
		$C = {};
		$C->{CatalogName} = $catalog;
		$C->{VendRoot} = $dir;

		unless (defined $subconfig) {
			$C->{ErrorFile} = 'error.log';
			$C->{ConfigFile} = 'catalog.cfg';
		}
		else {
			$C->{ConfigFile} = "$catalog.cfg";
			$C->{BaseCatalog} = $subconfig;
		}
	}

	unless($directives) {
		$directives = catalog_directives();
		foreach $d (@$directives) {
			my $ucdir = $d->[0];
			$directive = lc $d->[0];
			next if $Global::DeleteDirective->{$directive};
			$CDname{$directive} = $ucdir;
			$parse{$directive} = get_parse_routine($d->[1]);
		}
	}

	no strict 'refs';

	if(! $subconfig and ! $existing ) {
		foreach $d (@$directives) {
			my $ucdir = $d->[0];
			$directive = lc $d->[0];
			next if $Global::DeleteDirective->{$directive};
			$parse = $parse{$directive};

			$value = ( 
						! defined $MV::Default{$catalog} or
						! defined $MV::Default{$catalog}{$ucdir}
					 )
					 ? $d->[2]
					 : $MV::Default{$catalog}{$ucdir};

			if (defined $parse and defined $value) {
#::logDebug("parsing default directive=$directive ucdir=$ucdir parse=$parse value=$value CDname=$CDname{$directive}");
				$value = $parse->($ucdir, $value);
			}
			$C->{$CDname{$directive}} = $value;
		}
	}

	my(@include) = ($passed_file || $C->{ConfigFile});
	my $done_one;
	my ($db, $dname, $nm);
	my ($before, $after);
	my $recno = 'C0001';

	my @hidden_config;
	if(! $existing and ! $subconfig) {
		@hidden_config = grep -f $_, 
								 "$C->{CatalogName}.site",
								 "$Global::ConfDir/$C->{CatalogName}.before",
								 @{$Global::ConfigAllBefore},
							 ;

		# Backwards because of unshift;
		for (@hidden_config) {
			unshift @include, $_;
		}

		@hidden_config = grep -f $_, 
								 "$Global::ConfDir/$C->{CatalogName}.after",
								 @{$Global::ConfigAllAfter},
							 ;

		for (@hidden_config) {
			push @include, $_;
		}
	}

	# %MV::Default holds command-line mods to config, which we write
	# to a file for easier processing 
	if(! $existing and defined $MV::Default{$catalog}) {
		my $fn = "$Global::RunDir/$catalog.cmdline";
		open(CMDLINE, ">$fn")
			or die "Can't create cmdline configfile $fn: $!\n";
		for(@{$MV::DefaultAry{$catalog}}) {
			my ($d, $v) = split /\s+/, $_, 2;
			if($v =~ /\n/) {
				$v = "<<EndOfMvD\n$v\nEndOfMvD\n";
			}
			else {
				$v .= "\n";
			}
			printf CMDLINE '%-19s %s', $d, $v;
		}
		close CMDLINE;
		push @include, $fn;
	}

	my $allcfg;
	if($Global::DumpAllCfg) {
		open ALLCFG, ">$Global::RunDir/allconfigs.cfg"
			and $allcfg = 1;
	}
	# Create closure that reads and sets config values
	my $read = sub {
		my ($lvar, $value, $tie, $var) = @_;

		# parse variables in the value if necessary
		if($C->{ParseVariables} and $value =~ /(?:__|\@\@)/) {
			save_variable($CDname{$lvar}, $value);
			$value = substitute_variable($value);
		}

		# call the parsing function for this directive
		$parse = $parse{$lvar};
		$value = $parse->($CDname{$lvar}, $value) if defined $parse and ! $tie;

		# and set the $C->directive variable
		if($tie) {
			watch ( $CDname{$lvar}, $value );
		}
		else {
			$C->{$CDname{$lvar}} = $value;
		}
	};

#print "include starts with @include\n";
CONFIGLOOP:
	while ($configfile = shift @include) {
		my $tellmark;
		if(ref $configfile) {
			($configfile, $tellmark)  = @$configfile;
#print "recalling $configfile (pos $tellmark)\n";
		}

	# See if anything is defined in options to do before the
	# main configuration file.  If there is a file, then we
	# will do it (after pushing the main one on @include).
	
	-f $configfile && open(CONFIG, "< $configfile")
		or do {
			my $msg = "Could not open configuration file '" . $configfile .
					"' for catalog '" . $catalog . "':\n$!";
			if(defined $done_one) {
				warn "$msg\n";
				open (CONFIG, '');
			}
			else {
				die "$msg\n";
			}
		};
	print ALLCFG "# READING FROM $configfile\n" if $allcfg;
	seek(CONFIG, $tellmark, 0) if $tellmark;
#print "seeking to $tellmark in $configfile, include is @include\n";
	my ($ifdef, $begin_ifdef);
	while(<CONFIG>) {
		if($allcfg) {
			print ALLCFG $_
				unless /^#?include\s+/i;
		}
		chomp;			# zap trailing newline,
		# Look for meta commands (ifdef, endif, include) after '#'?
		my $leadinghash = $C->{ConfigParseComments} ? '#?' : '';
		if(/^\s*${leadinghash}endif\s*$/i) {
#print "found $_\n";
			undef $ifdef;
			undef $begin_ifdef;
			next;
		}
		if(/^\s*${leadinghash}if(n?)def\s+(.*)/i) {
			if(defined $ifdef) {
				config_error("Can't overlap ifdef at line %s of %s", $., $configfile);
			}
			$ifdef = evaluate_ifdef($2,$1);
			$begin_ifdef = $.;
#print "found $_\n";
			next;
		}
		if(defined $ifdef) {
			next unless $ifdef;
		}
		if(/^\s*${leadinghash}include\s+(.+)/i) {
#print "found $_\n";
			my $spec = $1;
			$spec = substitute_variable($spec) if $C->{ParseVariables};
			my $ref = [ $configfile, tell(CONFIG)];
#print "saving config $configfile (pos $ref->[1])\n";
			#unshift @include, [ $configfile, tell(CONFIG) ];
			unshift @include, $ref;
			close CONFIG;
			unshift @include, grep -f $_, glob($spec);
			next CONFIGLOOP;
		}

		my ($lvar, $value, $var, $tie) =
			read_config_value($_, \*CONFIG, $allcfg);

		next unless $lvar;

		# Use our closure defined above
		$read->($lvar, $value, $tie);

		# If we have passed off configuration to a database we stop here...
		last if $C->{ConfigDatabase}->{ACTIVE};

		# See if we want to load the config database
		if(! $db and $C->{ConfigDatabase}->{LOAD}) {
			$db = $C->{ConfigDatabase}->{OBJECT}
				or config_error(
					"ConfigDatabase $C->{ConfigDatabase}->{'name'} not active.");
			$dname = $C->{ConfigDatabase}{name};
		}

		# Actually load ConfigDatabase if present
		if($db) {
			$nm = $CDname{$lvar};
			my ($extended, $status);
			undef $extended;

			# set directive name
			$status = Vend::Data::set_field($db, $recno, 'directive', $nm);
			defined $status
				or config_error(
					"ConfigDatabase failed for %s, field '%s'",
					$dname,
					'directive',
					);

			# use extended value field if necessary or directed
			if (length($value) > 250 or $UseExtended{$nm}) {
				$extended = $value;
				$extended =~ s/(\S+)\s*//;
				$value = $1 || '';
				$status = Vend::Data::set_field($db, $recno, 'extended', $extended);
				defined $status
					or config_error(
						"ConfigDatabase failed for %s, field '%s'",
						$dname,
						'extended',
						);
			}

			# set value -- just a name if extended was used
			$status = Vend::Data::set_field($db, $recno, 'value', $value);
			defined $status
				or config_error(
						"ConfigDatabase failed for %s, field '%s'",
						$dname,
						'value',
					);

			$recno++;
		}
		
	}
	$done_one = 1;
	close CONFIG;

	# See if we have an active configuration database
	if($C->{ConfigDatabase}->{ACTIVE}) {
		my ($key,$value,$dir,@val);
		my $name = $C->{ConfigDatabase}->{name};
		$db = $C->{ConfigDatabase}{OBJECT} or 
			config_error("ConfigDatabase called ACTIVE with no database object.\n");
		my $items = $db->array_query("select * from $name order by code");
		my $one;
		foreach $one ( @$items ) {
			($key, $dir, @val) = @$one;
			$value = join " ", @val;
			$value =~ s/\s/\n/ if $value =~ /\n/;
			$value =~ s/^\s+//;
			$value =~ s/\s+$//;
			$lvar = lc $dir;
			$read->($lvar, $value);
		}
	}

	# We need to make this directory if it isn't already there....
	if(! $existing and $C->{ScratchDir} and ! -e $C->{ScratchDir}) {
		mkdir $C->{ScratchDir}, 0700
			or die "Can't make temporary directory $C->{ScratchDir}: $!\n";
	}

	if(defined $ifdef) {
		config_error("Failed to close #ifdef on line %s.", $begin_ifdef);
	}

} # end CONFIGLOOP

	return $C if $existing;

	# check for unspecified directives that don't have default values

	# but set some first if appropriate
	set_defaults();

	REQUIRED: {
		last REQUIRED if defined $subconfig;
		last REQUIRED if defined $Vend::ExternalProgram;
		foreach $var (keys %CDname) {
			if (! defined $C->{$CDname{$var}}) {
				my $msg = errmsg(
					"Please specify the %s directive in the configuration file '%s'",
					$CDname{$var},
					$configfile,
				);

				die "$msg\n";
			}
		}
	}

	finalize_mapped_code();

	# Ugly legacy stuff so API won't break
	$C->{Special} = $C->{SpecialPage} if defined $C->{SpecialPage};
	return $C;
}

sub read_here {
	my($handle, $marker, $allcfg) = @_;
	my $foundeot = 0;
	my $startline = $.;
	my $value = '';
	while (<$handle>) {
		print ALLCFG $_ if $allcfg;
		if ($_ =~ m{^$marker$}) {
			$foundeot = 1;
			last;
		}
		$value .= $_;
	}
	return undef unless $foundeot;
	#untaint
	$value =~ /([\000-\377]*)/;
	$value = $1;
	return $value;
}

sub config_named_catalog {
	my ($cat_name, $source, $db_only, $dbconfig) = @_;
	my ($g,$c);

	$g = $Global::Catalog{$cat_name};
	unless (defined $g) {
		logGlobal( "Can't find catalog '%s'" , $cat_name );
		return undef;
	}

	$Vend::Log_suppress = 1;

	unless ($db_only or $Vend::Quiet) {
		logGlobal( "Config '%s' %s%s", $g->{'name'}, $source );
	}
	undef $Vend::Log_suppress;

    chdir $g->{'dir'}
            or die "Couldn't change to $g->{'dir'}: $!\n";

	if($db_only) {
		logGlobal(
			"Config table '%s' (file %s) for catalog %s from %s",
			$db_only,
			$dbconfig,
			$g->{'name'},
			$source,
			);
		my $cfg = $Global::Selector{$g->{script}}
			or die errmsg("'%s' not a catalog (%s).", $g->{name}, $g->{script});
		undef $cfg->{Database}{$db_only};
		$Vend::Cfg = config(
				$g->{name},
				$g->{dir},
				undef,
				undef,
				$cfg,
				$dbconfig,
				)
			or die errmsg("error configuring catalog %s table %s: %s",
							$g->{name},
							$db_only,
							$@,
					);
		open_database();
		close_database();
		return $Vend::Cfg;
	}

    eval {
        $c = config($g->{'name'},
					$g->{'dir'},
					undef,
					$g->{'base'} || undef,
# OPTION_EXTENSION
#					$Vend::CommandLine->{$g->{'name'}} || undef
# END OPTION_EXTENSION
					);
    };

    if($@) {
		my $msg = $@;
        logGlobal( "%s config error: %s" , $g->{'name'}, $msg );
     	return undef;
    }

	if (defined $g->{base}) {
		open_database(1);
		dump_structure($c, $g->{name}) if $Global::DumpStructure;
		return $c;
	}

	eval {
		$Vend::Cfg = $c;	
		$::Variable = $Vend::Cfg->{Variable};
		$::Pragma   = $Vend::Cfg->{Pragma};
		Vend::Data::read_salestax();
		Vend::Data::read_shipping();
		open_database(1);
		my $db;
		close_database();
	};

	undef $Vend::Cfg;
    if($@) {
		my $msg = $@;
		$msg =~ s/\s+$//;
        logGlobal( "%s config error: %s" , $g->{'name'}, $msg );
     	return undef;
    }

	dump_structure($c, $g->{name}) if $Global::DumpStructure;

	my $stime = scalar localtime();
	Vend::Util::writefile(">$Global::RunDir/status.$g->{name}", "$stime\n");
	Vend::Util::writefile(">$c->{ConfDir}/status.$g->{name}", "$stime\n");

	return $c;

}


use File::Find;

my %extmap = qw/
	ia	ItemAction
	fa	FormAction
	am	ActionMap
	oc	OrderCheck
	ut	UserTag
	fi	Filter
	fw	Widget
	lc	LocaleChange
	tag	UserTag
	ct	CoreTag
/;

for( values %extmap ) {
	$extmap{lc $_} = $_;
}

sub get_system_groups {

	my @files;
	my $wanted = sub {
		return if (m{^\.} || ! -f $_);
		$File::Find::name =~ m{/([^/]+)/([^/.]+)\.(\w+)$}
			or return;
		my $group = $1;
		my $tname = $2;
		my $ext = $extmap{lc $3} or return;
		$ext =~ /Tag$/ or return;
		push @files, [ $group, $tname ];
	};
	File::Find::find($wanted, @$Global::TagDir);

	$Global::TagGroup ||= {};
	for(@files) {
		my $g = $Global::TagGroup->{":$_->[0]"} ||= [];
		push @$g, $_->[1];
	}
	return;
}

sub get_system_code {

	return if $CodeDest;
	return if $Vend::ControllingInterchange;
	
	# defined means don't go here anymore
	$SystemCodeDone = '';
	my @files;
	my $wanted = sub {
		return if (m{^\.} || ! -f $_);
		return unless m{^[^.]+\.(\w+)$};
		my $ext = $extmap{lc $1} or return;
		push @files, [ $File::Find::name, $ext];
	};
	File::Find::find($wanted, @$Global::TagDir);

	local($configfile);
	for(@files) {
		$CodeDest = $_->[1];

		$configfile = $_->[0];
		open SYSTAG, "< $configfile"
			or config_error("read system tag file %s: %s", $configfile, $!);
		while(<SYSTAG>) {
			my($lvar, $value) = read_config_value($_, \*SYSTAG);
			next unless $lvar;
			$GlobalRead->($lvar, $value);
		}
		close SYSTAG;
	}

	undef $CodeDest;
	# 1 means read system tag directories
	$SystemCodeDone = 1;
}

sub read_config_value {
	local($_) = shift;
	return undef unless $_;
	my ($fh, $allcfg) = @_;

	my $lvar;
	my $tie;

	chomp;			# zap trailing newline,
	s/^\s*#.*//;            # comments,
				# mh 2/10/96 changed comment behavior
				# to avoid zapping RGB values
				#
	s/\s+$//;		#  trailing spaces
	return undef unless $_;

	local($Vend::config_line);
	$Vend::config_line = $_;
	# lines read from the config file become untainted
	m/^[ \t]*(\w+)\s+(.*)/ or config_error("Syntax error");
	my $var = $1;
	my $value = $2;
	($lvar = $var) =~ tr/A-Z/a-z/;

	config_error("Unknown directive '%s'", $lvar), next
		unless defined $CDname{$lvar};

	my($codere) = '[-\w_#/.]+';

	if ($value =~ /^(.*)<<(\w+)\s*/) {                  # "here" value
		my $begin  = $1 || '';
		$begin .= "\n" if $begin;
		my $mark = $2;
		my $startline = $.;
		$value = $begin . read_here($fh, $mark);
		unless (defined $value) {
			config_error (sprintf('%d: %s', $startline,
				qq#no end marker ("$mark") found#));
		}
	}
	elsif ($value =~ /^(.*)<&(\w+)\s*/) {                # "here sub" value
		my $begin  = $1 || '';
		$begin .= "\n" if $begin;
		my $mark  = $2;
		my $startline = $.;
		$value = $begin . read_here($fh, $mark, $allcfg);
		unless (defined $value) {
			config_error (sprintf('%d: %s', $startline,
				qq#no end marker ("$mark") found#));
		}
		eval {
			require Tie::Watch;
		};
		unless ($@) {
			$tie = 1;
		}
		else {
			config_warn(
				"No Tie::Watch module installed at %s, setting %s to default.",
				$startline,
				$var,
			);
			$value = '';
		}
	}
	elsif ($value =~ /^(\S+)?(\s*)?<\s*($codere)$/o) {   # read from file
		my $confdir = $C ? $C->{ConfigDir} : $Global::ConfigDir;
		$value = $1 || '';
		my $file = $3;
		$value .= "\n" if $value;
		unless ($confdir) {
			config_error(
				"%s: Can't read from file until ConfigDir defined",
				$CDname{$lvar},
			);
		}
		$file = $CDname{$lvar} unless $file;
		$file = "$confdir/$file" unless $file =~ m!^/!;
		$file = escape_chars($file);			# make safe for filename
		my $tmpval = readfile($file);
		unless( defined $tmpval ) {
			config_warn(
					"%s: read from non-existent file %s, skipping.",
					$CDname{$lvar},
					$file,
			);
			return undef;
		}
		chomp($tmpval) unless $tmpval =~ m!.\n.!;
		$value .= $tmpval;
	}
	return($lvar, $value, $var, $tie);
}

# Parse the global configuration file for directives.  Each directive sets
# the corresponding variable in the Global:: package.  E.g.
# "DisplayErrors No" in the config file sets Global::DisplayErrors to 0.
# Directives which have no default value ("undef") must be specified
# in the config file.
sub global_config {
	my(%parse, $var, $value, $lvar, $parse);
	my($directive, $seen_catalog);
	no strict 'refs';

	%CDname = ();

	my $directives = global_directives();

	$Global::Structure = {} unless $Global::Structure;

	# Prevent parsers from thinking it is a catalog
	undef $C;

	foreach my $d (@$directives) {
		$directive = lc $d->[0];
		$CDname{$directive} = $d->[0];
		$parse = get_parse_routine($d->[1]);
		$parse{$directive} = $parse;
		undef $value;
		$value = ( 
					! defined $MV::Default{mv_global} or
					! defined $MV::Default{mv_global}{$d->[0]}
				 )
				 ? $d->[2]
				 : $MV::Default{mv_global}{$d->[0]};

		if (defined $DumpSource{$CDname{$directive}}) {
			$Global::Structure->{ $CDname{$directive} } = $value;
		}

		if (defined $parse and defined $value) {
			$value = $parse->($d->[0], $value);
		}

		if(defined $value) {
			${'Global::' . $CDname{$directive}} = $value;

			$Global::Structure->{ $CDname{$directive} } = $value
				unless defined $DontDump{ $CDname{$directive} };
		}

	}

	my (@include) = $Global::ConfigFile; 

	# Create closure for reading of value

	my $read = sub {
		my ($lvar, $value, $tie) = @_;

		unless (defined $CDname{$lvar}) {
			config_error("Unknown directive '%s'", $var);
			return;
		}

		if (defined $DumpSource{$CDname{$directive}}) {
			$Global::Structure->{ $CDname{$directive} } = $value;
		}

		# call the parsing function for this directive
		$parse = $parse{$lvar};
		$value = $parse->($CDname{$lvar}, $value) if defined $parse;

		# and set the Global::directive variable
		${'Global::' . $CDname{$lvar}} = $value;
		$Global::Structure->{ $CDname{$lvar} } = $value
			unless defined $DontDump{ $CDname{$lvar} };
	};

	$GlobalRead = $read;
	my $done_one;
GLOBLOOP:
	while ($configfile = shift @include) {
		my $tellmark;
		if(ref $configfile) {
			($configfile, $tellmark)  = @$configfile;
#print "recalling $configfile (pos $tellmark)\n";
		}

	-f $configfile && open(GLOBAL, "< $configfile")
		or do {
			my $msg = errmsg(
						"Could not open global configuration file '%s': %s",
						$configfile,
						$!,
						);
			if(defined $done_one) {
				warn "$msg\n";
				open (GLOBAL, '');
			}
			else {
				die "$msg\n";
			}
		};
	seek(GLOBAL, $tellmark, 0) if $tellmark;
#print "seeking to $tellmark in $configfile, include is @include\n";
	my ($ifdef, $begin_ifdef);
	while(<GLOBAL>) {
		# Look for meta commands (ifdef, endif, include) after '#'?
		my $leadinghash = $Global::ConfigParseComments ? '#?' : '';
		if(/^\s*${leadinghash}endif\s*$/i) {
#print "found $_";
			undef $ifdef;
			undef $begin_ifdef;
			next;
		}
		if(/^\s*${leadinghash}if(n?)def\s+(.*)/i) {
#print "found $_";
			if(defined $ifdef) {
				config_error(
					"Can't overlap ifdef at line %s of %s",
					$.,
					$configfile,
				);
			}
			$ifdef = evaluate_ifdef($2,$1,1);
			$begin_ifdef = $.;
			next;
		}
		if(defined $ifdef) {
			next unless $ifdef;
		}
		if(/^\s*${leadinghash}include\s+(.+)/) {
#print "found $_";
			my $spec = $1;
			my $ref = [ $configfile, tell(GLOBAL)];
#print "saving config $configfile (pos $ref->[1])\n";
			unshift @include, $ref;
			close GLOBAL;
			chomp;
			unshift @include, grep -f $_, glob($spec);
			next GLOBLOOP;
		}

		my ($lvar, $value, $tie) = read_config_value($_, \*GLOBAL);
		next unless $lvar;
		$read->($lvar, $value, $tie);

	}
	close GLOBAL;
	$done_one = 1;
} # end GLOBLOOP;

	# In case no user-supplied config has been given...returns
	# with no effect if that has been done already.
	get_system_code() unless defined $SystemCodeDone;

	# Do some cleanup
	set_global_defaults();

	# check for unspecified directives that don't have default values
	foreach $var (keys %CDname) {
		last if defined $Vend::ExternalProgram;
		if (!defined ${'Global::' . $CDname{$var}}) {
			die "Please specify the $CDname{$var} directive in the\n" .
			"configuration file '$Global::ConfigFile'\n";
		}
	}

	# Inits Global UserTag entries
	ADDTAGS: {
		Vend::Parse::global_init;
	}
	undef $GlobalRead;

	finalize_mapped_code();

	dump_structure($Global::Structure, "$Global::RunDir/$Global::ExeName")
		if $Global::DumpStructure and ! $Vend::ExternalProgram;

	%CDname = ();
	return 1;
}

# Use Tie::Watch to attach subroutines to config variables
sub watch {
	my($name, $value) = @_;
	$C->{Tie_Watch} = [] unless $C->{Tie_Watch};
	push @{$C->{Tie_Watch}}, $name;

	my ($ref, $orig);
#::logDebug("Contents of $name: " . uneval_it($C->{$name}));
	if(ref($C->{$name}) =~ /ARRAY/) {
#::logDebug("watch ref=array");
		$ref = $C->{$name};
		$orig = [ @{ $C->{$name} } ];
	}
	elsif(ref($C->{$name}) =~ /HASH/) {
#::logDebug("watch ref=hash");
		$ref = $C->{$name};
		$orig = { %{ $C->{$name} } };
	}
	else {
#::logDebug("watch ref=scalar");
		$ref = \$C->{$name};
		$orig = $C->{$name};
	}
#::logDebug("watch ref=$ref orig=$orig name=$name value=$value");
	$C->{WatchIt} = { _mvsafe => $C->{ActionMap}{_mvsafe} } if ! $C->{WatchIt};
	parse_action('WatchIt', "$name $value");
	my $coderef = $C->{WatchIt}{$name}
		or return undef;
	my $recode = sub {
					package Vend::Interpolate;
					init_calc();
					my $key = $_[0]->Args(-fetch)->[0];
					return $coderef->(@_, $key);
				};
	package Vend::Interpolate;
	$Vend::Config::C->{WatchIt}{$name} = Tie::Watch->new(
					-variable => $ref,
					-fetch => [$recode,$orig],
					);
}

sub get_wildcard_list {
	my($var, $value, $base) = @_;

	$value =~ s/^\s+//;
	$value =~ s/\s+$//;
	return '' if ! $value;

	if($value !~ /\|/) {
		$value =~ s/([\\\+\|\[\]\(\){}])/\\$1/g;
		$value =~ s/\./\\./g;
		$value =~ s/\*/.*/g;
		$value =~ s/\?/./g;
		my @items = grep /\S/, split /\s*,\s*/, $value;
		for (@items) {
			s/\s+/\\s+/g;
			my $extra = $_;
			if ($base && $extra =~ s/^\.\*\\\.//){
				push(@items,$extra) if $extra;
			}
		}
		$value = join '|', @items;
	}
	return parse_regex($var, $value);
}

# Set up an ActionMap or FormAction
sub parse_action {
	my ($var, $value, $mapped) = @_;
	return {} if ! $value;

	return if $Vend::ExternalProgram;

	my $c;
	if($mapped) {
		$c = $mapped;
	}
	elsif(defined $C) {
		$c = $C->{$var};
	}
	else {
		no strict 'refs';
		$c = ${"Global::$var"};
	}

	if (defined $C and ! $c->{_mvsafe}) {
		my $calc = Vend::Interpolate::reset_calc();
		$c->{_mvsafe} = $calc;
	}
	my ($name, $sub) = split /\s+/, $value, 2;

	# Untaint and strip this pup
	$sub =~ s/^\s*([\000-\377]*\S)\s*//;
	$sub = $1;

	if($sub !~ /\s/) {
		$c->{$name} = $Global::GlobalSub->{$_}
			if defined $Global::GlobalSub->{$_};
		return $c;
	}
	elsif ( ! $mapped and $sub !~ /^sub\b/) {
		my $code = <<EOF;
sub {
				return Vend::Interpolate::interpolate_html(<<EndOfThisHaiRYTHING);
$sub
EndOfThisHaiRYTHING
}
EOF
		$c->{$name} = eval $code;
	}
	elsif (! $C or $Global::AllowGlobal->{$C->{CatalogName}}) {
		package Vend::Interpolate;
		$c->{$name} = eval $sub;
	}
	else {
		package Vend::Interpolate;
		$c->{$name} = $c->{_mvsafe}->reval($sub);
	}
	if($@) {
		config_warn("Action '%s' did not compile correctly.", $name);
	}
	return $c;
	
}

sub get_directive {
	my $name = shift;
	$name = $CDname{lc $name} || $name;
	no strict 'refs';
	if($C) {
		return $C->{$name};
	}
	else {
		return ${"Global::$name"};
	}
}

# Changes configuration directives into Variable settings, i.e.
# DescriptionField becomes __DescriptionField__, ProductFiles becomes
# __ProductFiles_0__, ProductFiles_1__, etc. Doesn't handle hash keys
# that have non-word chars.

sub parse_autovar {
	my($var, $val) = @_;

	return '' if ! $val;

	my @dirs = grep /\w/, split /[\s,\0]+/, $val;

	my $name;
	foreach $name (@dirs) {
		next unless $name =~ /^\w+$/;
		my $val = get_directive($name);
		if(! ref $val) {
			parse_variable('Variable', "$name $val");
		}
		elsif ($val =~ /ARRAY/) {
			for(my $i = 0; $i < @$val; $i++) {
				my $an = "${name}_$i";
				parse_variable('Variable', "$an $val->[$i]");
			}
		}
		elsif ($val =~ /HASH/) {
			my ($k, $v);
			while ( ($k, $v) = each %$val) {
				next unless $k =~ /^\w+$/;
				parse_variable('Variable', "$k $v");
			}
		}
		else {
			config_warn('%s directive not parsable by AutoVariable', $name);
		}
	}
}


# Checks to see if a globalsub, sub, usertag, or Perl module is present
# If called with a third parameter, is just "suggestion"
# If called with a fourth parameter, is just capability check

sub parse_capability {
	return parse_require(@_, 1, 1);
}

sub parse_tag_group {
	my ($var, $setting) = @_;

	my $c;
	if(defined $C) {
		$c = $C->{$var} || {};
	}
	else {
		no strict 'refs';
		$c = ${"Global::$var"} || {};
	}
	
	$setting =~ tr/-/_/;
	$setting =~ s/[,\s]+/ /g;
	$setting =~ s/^\s+//;
	$setting =~ s/\s+$//;

	my @pairs = Text::ParseWords::shellwords($setting);

	while(@pairs) {
		my ($group, $sets) = splice @pairs, 0, 2;
		my @sets = grep $_, split /\s+/, $sets;
		my @groups = grep /:/, @sets;
		@sets = grep $_ !~ /:/, @sets;
		for(@groups) {
			next unless $c->{$_};
			push @sets, @{$c->{$_}};
		}
		$c->{$group} = \@sets;
	}
	return $c;
}

my %incmap = qw/TagInclude TagGroup/;
sub parse_tag_include {
	my ($var, $setting) = @_;

	my $c;
	my $g;

	my $mapper = $incmap{$var} || 'TagGroup';
	if(defined $C) {
		$c = $C->{$var} || {};
		$g = $C->{$mapper} || {};
	}
	else {
		no strict 'refs';
		$c = ${"Global::$var"} || {};
		$g = ${"Global::$mapper"} || {};
	}
	
	$setting =~ s/"/ /g;
	$setting =~ s/^\s+//;
	$setting =~ s/\s+$//;
	$setting =~ s/[,\s]+/ /g;

	if($setting eq 'ALL') {
		return { ALL => 1 };
	}

	delete $c->{ALL};

	get_system_groups() unless $SystemGroupsDone;

	my @incs = Text::ParseWords::shellwords($setting);

	for(@incs) {
		my @things;
		my $not = 0;
		if(/:/) {
			$not = 1 if s/^!//;
			if(! $g->{$_}) {
				config_warn(
					"unknown %s %s included from %s",
					$mapper,
					$_,
					$var,
				);
			}
			else {
				@things = @{$g->{$_}}
			}
		}
		else {
			@things = ($_);
		}
		for(@things) {
			my $not = s/^!// ? ! $not : $not;
			$c->{$_} = not $not;
		}
	}
	return $c;
}

sub parse_suggest {
	return parse_require(@_, 1);
}

sub parse_require {
	my($var, $val, $warn, $cap) = @_;

	return if $Vend::ExternalProgram;
	return if $Vend::ControllingInterchange;

	my $carptype;
	my $error_message;

	if($val =~ s/\s+"(.*)"//s) {
		$error_message = "\a\n\n$1\n";
	}

	if($cap) {
		$carptype = sub { return; };
	}
	elsif($warn) {
		$carptype = sub { return parse_message('', @_) };
		$error_message = "\a\n\nSuggest %s %s for proper catalog operation. Not all functions will work!\n"
			unless $error_message;
	}
	else {
		$carptype = \&config_error;
		$error_message = 'Required %s %s not present. Aborting catalog.'
			unless $error_message;
	}

	my $vref = $C ? $C->{Variable} : $Global::Variable;
	my $require;
	my $testsub = sub { 0 };
	my $name;
	if($val =~ s/^globalsub\s+//i) {
		$require = $Global::GlobalSub;
		$name = 'GlobalSub';
	}
	elsif($val =~ s/^sub\s+//i) {
		$require = $C->{Sub};
		$name = 'Sub';
	}
	elsif($val =~ s/^taggroup\s+//i) {
		$require = $Global::UserTag->{Routine};
		my @groups = grep /\S/, split /[\s,]+/, $val;
		my @needed;
		my $ref;
		for (@groups) {
			if($ref = $Global::TagGroup->{$_}) {
				push @needed, @$ref;
			}
			else {
				push @needed, $_;
			}
		}
		$name = "TagGroup $val member";
		$val = join " ", @needed;
	}
	elsif($val =~ s/^usertag\s+//i) {
		$require = $Global::UserTag->{Routine};
		$name = 'UserTag';
	}
	elsif($val =~ s/^(?:perl)?module\s+//i) {
		$require = {};
		$name = 'Perl module';
		$testsub = sub {
			my $module = shift;
			my $oldtype;
			if($module =~ s/\.pl$//) {
				$oldtype = '.pl';
			}
			$module =~ /[^\w:]/ and return undef;
			if(! $C or $Global::AllowGlobal->{$C->{CatalogName}}) {
				eval "require $module$oldtype;";
				return ! $@;
			}
			else {
				# Since we aren't safe to actually require, we will 
				# just look for a readable module file
				$module =~ s!::!/!g;
				$oldtype = '.pm' if ! $oldtype;
				my $found;
				for(@INC) {
					next unless -f "$_/$module$oldtype" and -r _;
					$found = 1;
				}
				return $found;
			}
		};
	}
	my @requires = grep /\S/, split /\s+/, $val;

	my $uname = uc $name;
	$uname =~ s/.*\s+//;
	for(@requires) {
		$vref->{"MV_REQUIRE_${uname}_$_"} = 1;
		next if defined $require->{$_};
		next if $testsub->($_);
		delete $vref->{"MV_REQUIRE_${uname}_$_"};
		$carptype->( $error_message, $name, $_ );
	}
	return '';	
}

# Sets the special variable remap array
#

my $Varnames;
INITVARS: {
	local($/);
	$Varnames = <DATA>;
}

sub parse_varname {
	my($item,$settings) = @_;

	return if $Vend::ExternalProgram;

	my($iv,$vn,$k,$v,@set);
#logDebug("parse_varname: $settings");
	if(defined $C) {
		return '' if ! $settings;
		$C->{IV} = { %{$Global::IV} } if ! $C->{IV};
		$C->{VN} = { %{$Global::VN} } if ! $C->{VN};
		$iv = $C->{IV};
		$vn = $C->{VN};
	}
	else {
		if (! $Global::VarName) {
			unless (-s "$Global::ConfDir/varnames" && -r _) {
				$settings = $Varnames . "\n$settings";
				Vend::Util::writefile("$Global::ConfDir/varnames", $Varnames);
			}
			else {
				$settings = Vend::Util::readfile("$Global::ConfDir/varnames");
			}
		}
		undef $Varnames;
		$Global::IV = {} if ! $Global::IV;
		$Global::VN = {} if ! $Global::VN;
		$iv = $Global::IV;
		$vn = $Global::VN;
	}

	@set = grep /\S/, split /\s+/, $settings;
	while( $k = shift @set, $v = shift @set ) {
		$vn->{$k} = $v;
		$iv->{$v} = $k;
	}
	return 1;
}


# Allow addition of a new catalog directive
sub parse_directive {
	my($name, $val) = @_;

	return '' unless $val;
	my($dir, $parser, $default) = split /\s+/, $val, 3 ;
	$parser = undef unless defined &{"parse_$parser"};
	$default = '' if ! $default or $default eq 'undef';
	$Global::AddDirective = [] unless $Global::AddDirective;
	push @$Global::AddDirective, [ $dir, $parser, $default ];
	return $Global::AddDirective;
}

# Allow a subcatalog value to completely replace a base value
sub parse_replace {
	my($name, $val) = @_;

	return {} unless $val;

	$C->{$val} = get_catalog_default($val);
	$C->{$name}->{$val} = 1;
	$C->{$name};
}


# Send a message during configuration, goes to terminal if during
# daemon startup, always goes to error log
sub parse_message {
	my($name, $val) = @_;

	return '' unless $val;

	return 1 if $Vend::Quiet;

	my $strip;
	my $info_only;
	## strip trailing whitespace if -n beins message
	while($val =~ s/^-([ni])\s+//) {
		$1 eq 'n' and $val =~ s/^-n\s+// and $strip = 1 and $val =~ s/\s+$//;
		$info_only = 1 if $1 eq 'i';
	}

	my $msg = errmsg($val,
						$name,
						$.,
						$configfile,
				);

	if($info_only and $Global::Foreground) {
		print $msg;
	}
	else {
		logGlobal({level => 'info', strip => $strip },
				errmsg($val,
						$name,
						$.,
						$configfile,
				)
		);
	}
}


# Warn about directives no longer supported in the configuration file.
sub parse_warn {
	my($name, $val) = @_;

	return '' unless $val;

	::logGlobal({level => 'info'},
				errmsg("Directive %s no longer supported at line %s of %s.",
						$name,
						$.,
						$configfile,
				)
	);
}

# Each of the parse functions accepts the value of a directive from the
# configuration file as a string and either returns the parsed value or
# signals a syntax error.

# Sets a boolean array for any type of item
sub parse_boolean {
	my($item,$settings) = @_;
	my(@setting) = split /[\s,]+/, $settings;
	my $c;

	my $val = $item eq "StaticPage" ? '' : 1;

	if(defined $C) {
		$c = $C->{$item} || {};
	}
	else {
		no strict 'refs';
		$c = ${"Global::$item"} || {};
	}

	for (@setting) {
		$c->{$_} = $val;
	}
	return $c;
}

# Sets a boolean array, but configurable value with tag=value
sub parse_boolean_value {
	my($item,$settings) = @_;
	my(@setting) = split /[\s,]+/, $settings;
	my $c;

	if(defined $C) {
		$c = $C->{$item} || {};
	}
	else {
		no strict 'refs';
		$c = ${"Global::$item"} || {};
	}

	for (@setting) {
		my ($k,$v);
		if(/=/) {
			($k,$v) = split /=/, $_, 2;
		}
		else {
			$k = $_;
			$v = 1;
		}
		$c->{$k} = $v;
	}
	return $c;
}

use POSIX qw(
				setlocale localeconv
				LC_ALL		LC_CTYPE	LC_COLLATE
				LC_MONETARY	LC_NUMERIC	LC_TIME
			);

# Sets the special locale array. Tries to use POSIX setlocale,
# accepts a 'custom' setting with the proper definitions of
# decimal_point,  mon_thousands_sep, and frac_digits (the only supported at
# the moment).  Otherwise uses US-English settings if not set.
#
sub parse_locale {
	my($item,$settings) = @_;
	return ($settings || '') unless $settings =~ /[^\d.]/;
	$settings = '' if "\L$settings" eq 'default';
	my $name;
	my ($c, $store);
	if(defined $C) {
		$c = $C->{$item} || { };
		$C->{$item . "_repository"} = {}
			unless $C->{$item . "_repository"};
		$store = $C->{$item . "_repository"};
	}
	else {
		no strict 'refs';
		$c = ${"Global::$item"} || {};
		${"Global::$item" . "_repository"} = {}
			unless ${"Global::$item" . "_repository"};
		$store = ${"Global::$item" . "_repository"};
	}

	# Try POSIX first if Locale.
	$name = POSIX::setlocale(POSIX::LC_ALL, $settings)
		if $item eq 'Locale' and $settings !~ /\s/;

	my ($eval, $safe);
	if ($name and $item eq 'Locale') {
		$store->{$name} = POSIX::localeconv();
	}
	elsif ($settings =~ s/^\s*([-\w.@]+)\s+//) {
		$name = $1;

		undef $eval;
		$settings =~ /^\s*{/
			and $settings =~ /}\s*$/
				and $eval = 1;
		$eval and ! $safe and $safe = new Safe;
		if(! defined $store->{$name} and $item eq 'Locale') {
			if(POSIX::setlocale(POSIX::LC_ALL, $name) ) {
				$store->{$name} = POSIX::localeconv();
			}
		}

		my($sethash);
		if ($eval) {
			$sethash = $safe->reval($settings)
				or config_warn("bad Locale setting in %s: %s", $name,$settings),
						$sethash = {};
		}
		else {
			$settings =~ s/^\s+//;
			$settings =~ s/\s+$//;
			$sethash = {};
			%{$sethash} = Text::ParseWords::shellwords($settings);
		}
		$c = $store->{$name} || {};
		my $nodefaults = delete $sethash->{MV_LOCALE_NO_DEFAULTS};
		for (keys %{$sethash}) {
			$c->{$_} = $sethash->{$_};
		}
	}
	else {
		config_error("Bad locale setting $settings.\n");
	}

	$C->{LastLocale} = $name if $C and $item eq 'Locale';

	$store->{$name} = $c unless $store->{$name};

	return $c;
}

#
# Sets a structure like Locale but with the depth and access via key
# No evaled structure setting, only key-value with shell quoting
# 
sub parse_structure {
	my ($item, $settings) = @_;
	return {} unless $settings;
	my $key;
	my @rest;
	($key, @rest) = Text::ParseWords::shellwords($settings);
	my ($c, $e);
	if(defined $C) {
		$c = $C->{$item};
		$e = $c->{$key} || { };
	}
	else {
		no strict 'refs';
		$c = ${"Global::$item"};
		$e = $c->{$key} || {};
	}

	while(scalar @rest) {
		my $k = shift @rest;
		$e->{$k} = shift @rest;
	}
	$c->{$key} = $e;
	return $c;
}


# Sets the special page array
sub parse_special {
	my($item,$settings) = @_;
	return {} unless $settings;
	my(%setting) = grep /\S/, split /[\s,]+/, $settings;
	for (keys %setting) {
		if($Global::NoAbsolute and file_name_is_absolute($setting{$_}) ) {
			config_warn("Absolute file name not allowed: %s", $setting{$_});
			next;
		}
		$C->{$item}{$_} = $setting{$_};
	}
	return $C->{$item};
}

# Sets up a hash value from a configuration directive, syntax is
# 
#   Directive  "key" "value"
# 
# quotes are optional if word-only chars

sub parse_hash {
	my($item,$settings) = @_;
	if (! $settings) {
		return $HashDefaultBlank{$item} ? '' : {};
	}

	my $c;

	if(defined $C) {
		$c = $C->{$item} || {};
	}
	else {
		no strict 'refs';
		$c = ${"Global::$item"} || {};
	}

	return Vend::Util::hash_string($settings,$c);
}

# Set up illegal values for certain directives
my %IllegalValue = (

		AutoModifier => { qw/   mv_mi 1
								mv_si 1
								mv_ib 1
								group 1
								code  1
								sku   1
								quantity 1
								item  1     /
						},
		UseModifier => { qw/   mv_mi 1
								mv_si 1
								mv_ib 1
								group 1
								code  1
								sku   1
								quantity 1
								item  1     /
						}
);


# Set up defaults for certain directives
my $Have_set_global_defaults;

# Set the default search files based on ProductFiles setting
# Honor a NO_SEARCH parameter in the Database structure
# Set MV_DEFAULT_SEARCH_FILE to the {file} entry,
# and set MV_DEFAULT_SEARCH_TABLE to the table name.
#
# Error out if not SubCatalog and can't find a setting.
#
sub set_default_search {
	my $setting = $C->{ProductFiles};

	if(! $setting) {
		return 1 if $C->{BaseCatalog};
		return (undef, errmsg("No ProductFiles setting!") );
	}
	
	my @fout;
	my @tout;
	my $nofile;
	my $notable;

	if ($C->{Variable}{MV_DEFAULT_SEARCH_FILE}) {
		@fout =
			grep /\S/,
			split /[\s,]+/,
			$C->{Variable}{MV_DEFAULT_SEARCH_FILE};
		$nofile = 1;
		for(@fout) {
			next if /\./;
			next unless exists $C->{Database}{$_};
			$_ = $C->{Database}{$_}{file};
		}
	}
	if ($C->{Variable}{MV_DEFAULT_SEARCH_TABLE}) {
		@tout =
			grep defined $C->{Database}{$_},
				split /[\s,]+/,
				$C->{Variable}{MV_DEFAULT_SEARCH_TABLE}
		;
		$notable = 1;
	}

	for(@$setting) {
		next if $C->{Database}{$_}{NO_SEARCH};
		push @tout, $_ unless $notable;
		next unless defined $C->{Database}{$_}{file};
		push @fout, $C->{Database}{$_}{file}
			unless $nofile;
	}
	unless (scalar @fout) {
		return 1 if $C->{BaseCatalog};
		return (undef, errmsg("No default search file!") );
	}
	$C->{Variable}{MV_DEFAULT_SEARCH_FILE}  = \@fout;
	$C->{Variable}{MV_DEFAULT_SEARCH_TABLE} = \@tout;
	return 1;
}

my %Default = (
		UserDB => sub {
					shift;
					my $set = $C->{UserDB_repository};
					for(keys %$set) {
						next unless defined $set->{$_}{admin};
						$C->{AdminUserDB} = {} unless $C->{AdminUserDB};
						$C->{AdminUserDB}{$_} = $set->{$_}{admin};
					}
					return 1;
				},
		Glimpse => sub {
					return 1 unless shift;
					require Vend::Glimpse;
					return 1;
				},
		SOAP_Socket => sub {
					shift;
					return 1 if $Have_set_global_defaults;
					$Global::SOAP_Socket = ['7780']
						if $Global::SOAP and ! $Global::SOAP_Socket;
					return 1;
				},
		TcpMap => sub {
					shift;
					return 1 if defined $Have_set_global_defaults;
					my (@sets) = keys %{$Global::TcpMap};
					if(scalar @sets == 1 and $sets[0] eq '-') {
						$Global::TcpMap = {};
					}
					return 1 if @sets;
					$Global::TcpMap->{7786} = '-';
					return 1;
				},
		Database => sub {
			my @del;
			for ( keys %{$C->{Database}}) {
				push @del, $_ unless defined $C->{Database}{$_}{type};
			}
			for(@del) {
#::logDebug("deleted non-existent db $_");
				delete $C->{Database}{$_};
			}
			return 1;
		},
		Locale => sub {
						my $repos = $C->{Locale_repository}
							or return 1;
						if ($C->{DefaultLocale}) {
							my $def = $C->{DefaultLocale};
							$C->{Locale} = $repos->{$def};
						}
						else {
							for(keys %$repos) {
								if($repos->{$_}{default}) {
									$C->{Locale} = $repos->{$_};
									$C->{DefaultLocale} = $_;
								}
							}
							if(! $C->{DefaultLocale} and $C->{LastLocale}) {
								$C->{DefaultLocale} = $C->{LastLocale};
								$C->{Locale} = $repos->{$C->{LastLocale}};
							}
						}
						return 1;
					},
		ProductFiles => \&set_default_search,
);

sub set_global_defaults {
	## Nothing here currently
}

sub set_defaults {
	for(keys %Default) {
		my ($status, $error) = $Default{$_}->($C->{$_});
		next if $status;
		return config_error(
				errmsg(
					'Directive %s returned default setting error: %s',
					$_,
					$error
				)
		);
	}
	$Have_set_global_defaults = 1;
	return;
}

sub parse_url_sep_char {
	my($var,$val) = @_;

	$val =~ s/\s+//g;

	if($val =~ /[\w%]/) {
		config_error(
			errmsg("%s character value '%s' must not be word character or %%.", $var, $val)
		);
	}
	elsif(length($val) > 1) {
		config_error(
			"%s character value '%s' longer than one character.",
			$var,
			$val,
		);
	}
	elsif($val !~ /[&;:]/) {
		config_warn("%s character value '%s' not a recommended value.", $var, $val);
	}

	if($val eq '&') {
		$Global::UrlJoiner = $Global::Variable->{MV_HTML4_COMPLIANT} ? '&amp;' : '&';
		$Global::UrlSplittor = qr/\&/;
	}
	else {
		$Global::UrlJoiner = $val;
		$Global::UrlSplittor = qr/[&$val]/o;
	}
	return $val;
}

sub check_legal {
	my ($directive, $value) = @_;
	return 1 unless defined $IllegalValue{$directive}->{$value};
	config_error ("\nYou may not use a value of '$value' in the $directive directive.");
}

sub parse_array {
	my($item,$settings) = @_;
	return '' unless $settings;
	my(@setting) = grep /\S/, split /[\s,]+/, $settings;

	my $c;

	if(defined $C) {
		$c = $C->{$item} || [];
	}
	else {
		no strict 'refs';
		$c = ${"Global::$item"} || [];
	}

	for (@setting) {
		check_legal($item, $_);
		push @{$c}, $_;
	}
	$c;
}

sub parse_array_complete {
	my($item,$settings) = @_;
	return '' unless $settings;
	my(@setting) = grep /\S/, split /[\s,]+/, $settings;

	my $c = [];

	for (@setting) {
		check_legal($item, $_);
		push @{$c}, $_;
	}

	$c;
}

sub parse_list_wildcard {
	my $value = get_wildcard_list(@_,0);
	return '' unless length($value);
	return qr/$value/i;
}

sub parse_list_wildcard_full {
	my $value = get_wildcard_list(@_,1);
	return '' unless length($value);
	return qr/^($value)$/i;
}

# Make a dos-ish regex into a Perl regex, check for errors
sub parse_wildcard {
	my($var, $value) = @_;
	return '' if ! $value;

	$value =~ s/\./\\./g;
	$value =~ s/\*/.*/g;
	$value =~ s/\?/./g;
	$value =~
		s[({(?:.+?,)+.+?})]
		 [ local $_ = $1; tr/{,}/(|)/; $_ ]eg;
	$value =~ s/\s+/|/g;
	eval {  
		my $never = 'NeVAirBE';
		$never =~ m{$value};
	};

	if($@) {
		config_error("Bad regular expression in $var.");
	}
	return $value;
}


# Check that a regex won't cause a syntax error. Uses m{}, which
# should be used for all user-input regexes.
sub parse_regex {
	my($var, $value) = @_;

	eval {  
		my $never = 'NeVAirBE';
		$never =~ m{$value};
	};

	if($@) {
		config_error("Bad regular expression in $var.");
	}
	return $value;
}

# Prepend the Global::VendRoot pathname to the relative directory specified,
# unless it already starts with a leading /.

sub parse_root_dir {
	my($var, $value) = @_;
	return '' unless $value;
	$value = "$Global::VendRoot/$value"
		unless Vend::Util::file_name_is_absolute($value);
	$value =~ s./+$..;
	return $value;
}

sub parse_root_dir_array {
	my($var, $value) = @_;
	return [] unless $value;

	no strict 'refs';
	my $c = ${"Global::$var"} || [];

	my @dirs = grep /\S/, Text::ParseWords::shellwords($value);

	foreach my $dir (@dirs) {
		$dir = "$Global::VendRoot/$dir"
			unless Vend::Util::file_name_is_absolute($dir);
		$dir =~ s./+$..;
		push @$c, $dir;
	}
	return $c;
}

sub parse_dir_array {
	my($var, $value) = @_;
	return [] unless $value;
	$value = "$C->{VendRoot}/$value"
		unless Vend::Util::file_name_is_absolute($value);
	$value =~ s./+$..;
	$C->{$var} = [] unless $C->{$var};
	my $c = $C->{$var} || [];
	push @$c, $value;
	return $c;
}

# Prepend the CatalogRoot pathname to the relative directory specified,
# unless it already starts with a leading /.

sub parse_relative_dir {
	my($var, $value) = @_;

	config_error(
	  "No leading / allowed if NoAbsolute set. Contact administrator.\n"
	  )
	  if Vend::Util::file_name_is_absolute($value) and $Global::NoAbsolute;
	config_error(
	  "No leading ../.. allowed if NoAbsolute set. Contact administrator.\n"
	  )
	  if $value =~ m#^\.\./.*\.\.# and $Global::NoAbsolute;

	$C->{Source}{$var} = $value;

	$value = "$C->{VendRoot}/$value"
		unless Vend::Util::file_name_is_absolute($value);
	$value =~ s./+$..;
	$value;
}

# Ensure only an integer value in the directive
sub parse_integer {
	my($var, $value) = @_;
	$value = hex($value) if $value =~ /^0x[\dA-Fa-f]+$/;
	$value = oct($value) if $value =~ /^0[0-7]+$/;
	config_error("The $var directive (now set to '$value') must be an integer\n")
		unless $value =~ /^\d+$/;
	$value;
}

# Make sure no trailing slash in VendURL etc.
sub parse_url {
	my($var, $value) = @_;
	$value =~ s,/+$,,;
	$value;
}

# Parses a time specification such as "1 day" and returns the
# number of seconds in the interval, or undef if the string could
# not be parsed.

sub time_to_seconds {
	my($str) = @_;
	my($n, $dur);

	($n, $dur) = ($str =~ m/(\d+)[\s\0]*(\w+)?/);
	return undef unless defined $n;
	if (defined $dur) {
		local($_) = $dur;
		if (m/^s|sec|secs|second|seconds$/i) {
		}
		elsif (m/^m|min|mins|minute|minutes$/i) {
			$n *= 60;
		}
		elsif (m/^h|hour|hours$/i) {
			$n *= 60 * 60;
		}
		elsif (m/^d|day|days$/i) {
			$n *= 24 * 60 * 60;
		}
		elsif (m/^w|week|weeks$/i) {
			$n *= 7 * 24 * 60 * 60;
		}
		else {
			return undef;
		}
	}

	$n;
}

sub parse_valid_group {
	my($var, $value) = @_;

	return '' unless $value;

	my($name,$passwd,$gid,$members) = getgrnam($value);

	config_error("$var: Group name '$value' is not a valid group\n")
		unless defined $gid;
	$name = getpwuid($<);
	config_error("$var: Interchange user '$name' not in group '$value'\n")
		unless $members =~ /\b$name\b/;
	$gid;
}

sub parse_executable {
	my($var, $initial) = @_;
	my($x);
	my(@tries);
	
	if(ref $initial) {
		@tries = @$initial;
	}
	else {
		@tries = $initial;
	}

	TRYEXE:
	foreach my $value (@tries) {
#::logDebug("trying $value for $var");
		my $root = $value;
		$root =~ s/\s.*//;

		return $value if $Global::Windows;
		if( ! defined $value or $value eq '') {
			$x = '';
		}
		elsif( $value eq 'none') {
			$x = 'none';
			last;
		}
		elsif( $value =~ /^\w+::[:\w]+\w$/) {
			## Perl module like Net::SMTP
			eval {
				eval "require $value";
				die if $@;
				$x = $value;
			};
			last if $x;
		}
		elsif ($root =~ m#^/# and -x $root) {
			$x = $value;
			last;
		}
		else {
			my @path = split /:/, $ENV{PATH};
			for (@path) {
				next unless -x "$_/$root";
				$x = $value;
				last TRYEXE;
			}
		}
	}
	config_error( errmsg(
					"Can't find executable (%s) for the %s directive\n",
					join('|', @tries),
					$var,
					)
		) unless defined $x;
#::logDebug("$var=$x");
	return $x;
}

sub parse_time {
	my($var, $value) = @_;
	my($n);

	$C->{Source}->{$var} = [$value];

	$n = time_to_seconds($value);
	config_error("Bad time format ('$value') in the $var directive\n")
	unless defined $n;
	$n;
}

# Determine catalog structure from Catalog config line(s)
sub parse_catalog {
	my ($var, $setting) = @_;
	my $num = ! defined $Global::Catalog ? 0 : $Global::Catalog;
	return $num unless (defined $setting && $setting); 

	my($name,$base,$dir,$script, @rest);
	($name,@rest) = Text::ParseWords::shellwords($setting);

	my %remap = qw/
					base      base
					alias     alias
					aliases   alias
					directory dir
					dir       dir
					script    script
					directive directive
					fullurl   full_url
					full      full_url
					/;

	my ($cat, $key, $value);
	if ($Global::Catalog{$name}) {
		# already defined
		$cat   = $Global::Catalog{$name};
		$key   = shift @rest;
		$value = shift @rest;
	}
	elsif(
			$var =~ /subcatalog/i and
			@rest > 2
			and file_name_is_absolute($rest[1]) 
		  )
	{
		$cat = {
			name   => $name,
			base   => $rest[0],
			dir    => $rest[1],
			script => $rest[2],
		};
		splice(@rest, 0, 3);
		$cat->{alias} = [ @rest ]
			if @rest;
	}
	elsif( file_name_is_absolute($rest[0]) ) {
		$cat = {
			name   => $name,
			dir    => $rest[0],
			script => $rest[1],
		};
		splice(@rest, 0, 2);
		$cat->{alias} = [ @rest ]
			if @rest;
	}
	else {
		$key   = shift @rest;
		$value = shift @rest;
		$cat = { name   => $name };
	}

	$key = $remap{$key} if $key && defined $remap{$key};

	if(! $key) {
		# Nada
	}
	elsif($key eq 'alias' or $key eq 'server') {
		$cat->{$key} = [] if ! $cat->{$key};
		push @{$cat->{$key}}, $value;
		push @{$cat->{$key}}, @rest if @rest;
	}
	elsif($key eq 'global') {
		$cat->{$key} = $Global::AllowGlobal->{$name} = is_yes($value);
	}
	elsif($key eq 'directive') {
		no strict 'refs';
		my $p = $value;
		my $v = join " ", @rest;
		$cat->{$key} = {} if ! $cat->{$key};
		my $ref = set_directive($p, $v, 1);

		if(ref $ref->[1] =~ /HASH/) {
			if(! $cat->{$key}{$ref->[0]} ) {
				$cat->{$key}{$ref->[0]} =  { %{"Global::$ref->[0]"} };
			}
			for (keys %{$ref->[1]}) {
				$cat->{$key}{$ref->[0]}{$_} = $ref->[1]->{$_};
			}
		}
		else {
			$cat->{$key}{$ref->[0]} = $ref->[1];
		}
	}
	else {
		$cat->{$key} = $value;
	}

#::logDebug ("parsing catalog $name = " . uneval_it($cat));

	$Global::Catalog{$name} = $cat;

	# Define the main script name and array of aliases
	return ++$num;
}

my %Hash_ref = (  qw!
							FILTER_FROM   FILTER_FROM
							FILTER_TO     FILTER_TO 
							COLUMN_DEF    COLUMN_DEF
							DEFAULT       DEFAULT
							DEFAULT_SESSION       DEFAULT_SESSION
							FIELD_ALIAS   FIELD_ALIAS
							NUMERIC       NUMERIC
							WRITE_CATALOG WRITE_CATALOG
					! );

my %Ary_ref = (   qw!
						NAME                NAME
						BINARY              BINARY 
						PRECREATE           PRECREATE 
						POSTCREATE          POSTCREATE 
						INDEX               INDEX 
						ALTERNATE_DSN       ALTERNATE_DSN
						ALTERNATE_USER      ALTERNATE_USER
						ALTERNATE_PASS      ALTERNATE_PASS
						ALTERNATE_BASE_DN   ALTERNATE_BASE_DN
						ALTERNATE_LDAP_HOST ALTERNATE_LDAP_HOST
						ALTERNATE_BIND_DN   ALTERNATE_BIND_DN
						ALTERNATE_BIND_PW   ALTERNATE_BIND_PW
					! );

sub parse_config_db {
	my($name, $value) = @_;
	my ($d, $new);
	unless (defined $value && $value) { 
		$d = {};
		return $d;
	}

	if($C) {
		$d = $C->{ConfigDatabase};
	}
	else {
		$d = $Global::ConfigDatabase;
	}

	my($database,$remain) = split /[\s,]+/, $value, 2;

	$d->{'name'} = $database;
	
	if(!defined $d->{'file'}) {
		my($file, $type) = split /[\s,]+/, $remain, 2;
		$d->{'file'} = $file;
		if(		$type =~ /^\d+$/	) {
			$d->{'type'} = $type;
		}
		elsif(	$type =~ /^(dbi|sql)\b/i	) {
			$d->{'type'} = 8;
			if($type =~ /^dbi:/) {
				$d->{DSN} = $type;
			}
		}
# LDAP
		elsif(	$type =~ /^ldap\b/i) {
			$d->{'type'} = 9;
			if($type =~ /^ldap:(.*)/i) {
				$d->{LDAP_HOST} = $1;
			}
		}
# END LDAP
		elsif(	"\U$type" eq 'TAB'	) {
			$d->{'type'} = 6;
		}
		elsif(	"\U$type" eq 'PIPE'	) {
			$d->{'type'} = 5;
		}
		elsif(	"\U$type" eq 'CSV'	) {
			$d->{'type'} = 4;
		}
		elsif(	"\U$type" eq 'DEFAULT'	) {
			$d->{'type'} = 1;
		}
		elsif(	$type =~ /[%]{1,3}|percent/i	) {
			$d->{'type'} = 3;
		}
		elsif(	$type =~ /line/i	) {
			$d->{'type'} = 2;
		}
		else {
			$d->{'type'} = 1;
			$d->{DELIMITER} = $type;
		}
	}
	else {
		my($p, $val) = split /\s+/, $remain, 2;
		$p = uc $p;

		if(defined $Hash_ref{$p}) {
			my($k, $v);
			my(@v) = Vend::Util::quoted_comma_string($val);
			@v = grep defined $_, @v;
			$d->{$p} = {} unless defined $d->{$p};
			for(@v) {
				($k,$v) = split /\s*=\s*/, $_;
				$d->{$p}->{$k} = $v;
			}
		}
		elsif(defined $Ary_ref{$p}) {
			my(@v) = Text::ParseWords::shellwords($val);
			$d->{$p} = [] unless defined $d->{$p};
			push @{$d->{$p}}, @v;
		}
		else {
			defined $d->{$p}
			and ! defined $C->{DatabaseDefault}{$p}
				and config_warn(
						"ConfigDatabase %s scalar parameter %s redefined to '%s', was %s.",
						$d->{name},
						$p,
						$val,
						$d->{$p},
					);
			$d->{$p} = $val;
		}
	}

#::logDebug("d object: " . uneval_it($d));
	if($d->{ACTIVE} and ! $d->{OBJECT}) {
		my $name = $d->{'name'};
		$d->{OBJECT} = Vend::Data::import_database($d)
			or config_error("Config database $name failed import.\n");
	}
	elsif($d->{LOAD} and ! $d->{OBJECT}) {
		my $name = $d->{'name'};
		$d->{OBJECT} = Vend::Data::import_database($d)
			or config_error("Config database $name failed import.\n");
		if( $d->{type} == 8 ) {
			$d->{OBJECT}->set_query("delete from $name where 1 = 1");
		}
	}

	return $d;
	
}

sub parse_dbauto {
	my ($var, $value) = @_;
	return '' unless $value;
	my @inc = Vend::Table::DBI::auto_config($value);
	my %noed;
	for(@inc) {
		my ($t, $thing) = @$_;
		parse_boolean('NoImport', $t) unless $noed{$t}++;
		parse_database('Database', "$t $thing");
	}
	return 1;
}

sub parse_database {
	my ($var, $value) = @_;
	my ($c, $new);

	if (! $value) {
		$c = {};
		return $c;
	}

#::logDebug("parse_database: $value");
	$c = $C ? $C->{Database} : $Global::Database;

	my($database,$remain) = split /[\s,]+/, $value, 2;

	if( ! defined $c->{$database} ) {
		$c->{$database} = { 'name' => $database, included_from => $configfile };
		$new = 1;
	}

	my $d = $c->{$database};

	if($new) {
		my($file, $type) = split /[\s,]+/, $remain, 2;
		$d->{'file'} = $file;
		if(		$type =~ /^\d+$/	) {
			$d->{'type'} = $type;
		}
		elsif(	$type =~ /^(dbi|sql)\b/i	) {
			$d->{'type'} = 8;
			if($type =~ /^dbi:/) {
				$d->{DSN} = $type;
			}
		}
# LDAP
		elsif(	$type =~ /^ldap\b/i) {
			$d->{'type'} = 9;
			if($type =~ /^ldap:(.*)/i) {
				$d->{LDAP_HOST} = $1;
			}
		}
# END LDAP
		elsif(	$type =~ /^ic:(\w*)(:(.*))?/ ) {
			my $class = $1;
			my $dir = $3;
			$d->{DIR} = $dir if $dir;
			if($class =~ /^default$/i) {
				# Do nothing
			}
			elsif($class) {
				$class = uc $class;
				if(! $Vend::Data::db_config{$class}) {
					config_error("unrecognized IC database class: %s (from %s)", $class, $type);
				}
				$d->{Class} = $class;
			}
			$d->{'type'} = 6;
		}
		elsif(	"\U$type" eq 'TAB'	) {
			$d->{'type'} = 6;
		}
		elsif(	"\U$type" eq 'PIPE'	) {
			$d->{'type'} = 5;
		}
		elsif(	"\U$type" eq 'CSV'	) {
			$d->{'type'} = 4;
		}
		elsif(	"\U$type" eq 'DEFAULT'	) {
			$d->{'type'} = 1;
		}
		elsif(	$type =~ /[%]{1,3}|percent/i	) {
			$d->{'type'} = 3;
		}
		elsif(	$type =~ /line/i	) {
			$d->{'type'} = 2;
		}
		else {
			$d->{'type'} = 1;
			$d->{DELIMITER} = $type;
		}
		if    ($d->{'type'} eq '8')	{ $d->{Class} = 'DBI'						}
		elsif ($d->{'type'} eq '9') { $d->{Class} = 'LDAP'						}
		else 						{ $d->{Class} = $Global::Default_database	}

		if($C->{DatabaseDefault}) {
			while ( my($k, $v) = each %{$C->{DatabaseDefault}}) {
				$d->{$k} = $v;
			}
		}

		$d->{HOT} = 1 if $d->{Class} eq 'MEMORY';
#::logDebug("parse_database: type $type -> $d->{type}");
	}
	else {
		my($p, $val) = split /\s+/, $remain, 2;
		$p = uc $p;
#::logDebug("parse_database: parameter $p = $val");

		if(defined $Hash_ref{$p}) {
			my($k, $v);
			my(@v) = Vend::Util::quoted_comma_string($val);
			@v = grep defined $_, @v;
			$d->{$p} = {} unless defined $d->{$p};
			for(@v) {
				($k,$v) = split /\s*=\s*/, $_;
				$d->{$p}->{$k} = $v;
			}
		}
		elsif(defined $Ary_ref{$p}) {
			my(@v) = Text::ParseWords::shellwords($val);
			$d->{$p} = [] unless defined $d->{$p};
			push @{$d->{$p}}, @v;
		}
		elsif ($p =~ /^(MEMORY|SDBM|GDBM|DB_FILE|LDAP)$/i) {
			$d->{Class} = uc $p;
		}
		elsif ($p eq 'ALIAS') {
			if (defined $c->{$val}) {
				config_warn("Database '%s' already exists, can't alias.", $val);
			}
			else {
				$c->{$val} = $d;
			}
		}
		elsif ($p eq 'MAP') {
			my @f = split(/\s+/, $val);
			my %parms;
			my %map_options = (fallback => 1);
			my ($map_table, $map_column);
			
			if (@f < 2) {
				config_error("At least two parameters needed for MAP.");
			} elsif (@f == 2) {
				@f = ($f[0], 'default', $f[1]);
			}

			my $field = shift @f;

			if (@f % 2) {
				config_error("Incomplete parameter list for MAP.");
			}

			# now we have a valid configuration and change the database type
			# if necessary

			unless ($d->{type} eq 10) {
				$d->{OrigClass} = $d->{Class};
				$d->{Class} = 'SHADOW';
				$d->{type} = 10;
			}

			while (@f) {
				my $map_key = shift @f;
				my $map_value = shift @f;

				if (exists $map_options{$map_key}) {
					# option like fallback
					$d->{MAP}->{$field}->{$map_key} = $map_value;
				} else {
					# mapping direction
					if ($map_value =~ /::/) {
						($map_table, $map_value) = split (/::/, $map_value);
						$d->{MAP}->{$field}->{$map_key} = {table => $map_table,
														  column => $map_value};
					} else {
						$d->{MAP}->{$field}->{$map_key} = {column => $map_value};
					}
				}
			}
		}

		else {
			defined $d->{$p}
			and ! defined $C->{DatabaseDefault}{$p}
				and
				config_warn(
					"Database %s scalar parameter %s redefined to '%s', was %s.",
					$d->{name},
					$p,
					$val,
					$d->{$p},
				);
			$d->{$p} = $val;
		}
		$d->{HOT} = 1 if $d->{Class} eq 'MEMORY';
	}

	return $c;
}

sub get_configdb {
	my ($var, $value) = @_;
	my ($table, $file, $type);
	unless ($C->{Database}{$value}) {
		return if $Vend::ExternalProgram;
		($table, $file, $type) = split /\s+/, $value, 3;
		$file = "$table.txt" unless $file;
		$type = 'TAB' unless $type;
		parse_database('Database',"$table $file $type");
		unless ($C->{Database}{$table}) {
			config_warn(
				"Bad $var value '%s': %s\n%s",
				"Database $table $file $type",
				uneval($C->{Database}),
			);
			return '';
		}
	}
	else {
		$table = $value;
	}

	my $db;
	unless ($db = $C->{Database}{$table}) {
		return if $Vend::ExternalProgram;
		my $err = $@;
		config_warn("Bad $var '%s': %s", $table, $err);
		return '';
	}
	$db = Vend::Data::import_database($db);
	if(! $db) {
		my $err = $@;
		config_warn("Bad $var '%s': %s", $table, $err);
		return '';
	}
	return ($db, $table);
}

my %Columnar = (Locale => 1);

sub parse_configdb {
	my ($var, $value) = @_;

	my ($file, $type);
	return '' if ! $value;
	local($Vend::Cfg) = $C;
	my ($db, $table) = get_configdb($var, $value);

	return '' if ! $db;

	my ($k, @f);	# key and fields
	my @l;			# refs to locale repository
	my @n;			# names of locales
	my @h;			# names of locales

	my $base_direc = $var;
	$base_direc =~ s/Database$//;
	my $repos_name = $base_direc . '_repository';
	my $repos = $C->{$repos_name} ||= {};

	@n = $db->columns();
	shift @n;
	my $i;
	if($Columnar{$base_direc}) {
		my @l;
		for(@n) {
			$repos->{$_} ||= {};
			push @l, $repos->{$_};
		}
		my $i;
		while( ($k , undef, @f ) = $db->each_record) {
			for ($i = 0; $i < @f; $i++) {
				next unless length($f[$i]);
				$l[$i]->{$k} = $f[$i];
			}
		}
	}
	else {
		while( ($k, undef, @f ) = $db->each_record) {
			for ($i = 0; $i < @f; $i++) {
				next unless length($f[$i]);
				$repos->{$k}{$n[$i]} = $f[$i];
			}
		}
	}
	$db->close_table();
	return $table;
}

sub parse_dirconfig {
	my ($var, $value) = @_;

	return '' if ! $value;
	$value =~ s/(\w+)\s+//;
	my $direc = $1;
#::logDebug("direc=$direc value=$value");
	 
	my $ref = $C->{$direc};

	unless(ref($ref) eq 'HASH') {
		config_error("DirConfig called for non-hash configuration directive.");
	}

	my $source = $C->{$var}   || {};
	my $sref = $source->{$direc} || {};

	my @dirs = grep -d $_, glob($value);
	foreach my $dir (@dirs) {
		opendir(DIRCONFIG, $dir)
			or next;
		my @files = grep /^\w+$/, readdir(DIRCONFIG);
		for(@files) {
			next unless -f "$dir/$_";
#::logDebug("reading key=$_ from $dir/$_");
			$ref->{$_} = readfile("$dir/$_", $Global::NoAbsolute, 0);
			$sref->{$_} = "$dir/$_";
		}
	}
	$source->{$direc} = $sref;
	return $source;
}

sub parse_dbconfig {
	my ($var, $value) = @_;

	my ($file, $type);
	return '' if ! $value;
	local($Vend::Cfg) = $C;

	my ($db, $table) = get_configdb($var, $value);

	return '' if ! $db;

	my ($k, @f);	# key and fields
	my @l;			# refs to locale repository
	my @n;			# names of locales
	my @h;			# names of locales

	@n = $db->columns();
	shift @n;
	my $extra;
	for(@n) {
		my $real = $CDname{lc $_};
		if (! ref $Vend::Cfg->{$real} or $Vend::Cfg->{$real} !~ /HASH/) {
			# ignore non-existent directive, but put in hash
			my $ref = {};
			push @l, $ref;
			push @h, [$real, $ref];
			next;
		}
		push @l, $Vend::Cfg->{$real};
	}
	my $i;
	while( ($k, undef, @f ) = $db->each_record) {
#::logDebug("Got key=$k f=@f");
		for ($i = 0; $i < @f; $i++) {
			next unless length($f[$i]);
			$l[$i]->{$k} = $f[$i];
		}
	}
	for(@h) {
		$Vend::Cfg->{Hash}{$_->[0]} = $_->[1];
	}
	$db->close_table();
	return $table;
}

sub parse_dbdatabase {
	my ($var, $value) = @_;

	return '' if ! $value;
	local($Vend::Cfg) = $C;
	my ($db, $table) = get_configdb($var, $value);
	$db = $db->ref();
	my $kindex = $db->config('KEY_INDEX');
#::logDebug("kindex=$kindex");
	local($^W) = 0;
	my ($k, @f);	# key and fields
	my @l;			# refs to locale repository
	my @n;			# names of locales
	my $name;		# names of current locale

	@n = $db->columns();
	$k = 0;
	foreach $name (@n) {
		next if $k++ == $kindex;
		my $file = $db->field('_file', $name);
		my $type = $db->field('_type', $name);
		next unless $file and $type;
		parse_database('', "$name $file $type");
	}
	while( ($k , @f ) = $db->each_record) {
		next if $k =~ /^_/;
		my $i;
		for ($i = 0; $i < @f; $i++) {
			next if $i == $kindex;
			next unless length $f[$i];
#::logDebug("f-i=$f[$i] i=$i kindex=$kindex");
			Vend::Config::parse_database('', "$n[$i] $k $f[$i]");
		}
	}
	$db->close_table();
	return $table;
}

sub parse_profile {
	my ($var, $value) = @_;
	my ($c, $ref, $sref, $i);

	if($C) {
		$C->{"${var}Name"} = {} if ! $C->{"${var}Name"};
		$sref = $C->{Source};
		$ref = $C->{"${var}Name"};
		$c = $C->{$var} || [];
	}
	else {
		no strict 'refs';
		$sref = $Global::Source;
		${"Global::${var}Name"} = {}
			 if ! ${"Global::${var}Name"};
		$ref = ${"Global::${var}Name"};
		$c = ${"Global::$var"} || [];
	}

	$sref->{$var} = $value;

	my (@files) = glob($value);
	for(@files) {
		next unless $_;
		config_error(
		  "No leading / allowed if NoAbsolute set. Contact administrator.\n")
		if m.^/. and $Global::NoAbsolute;
		config_error(
		  "No leading ../.. allowed if NoAbsolute set. Contact administrator.\n")
		if m#^\.\./.*\.\.# and $Global::NoAbsolute;
		push @$c, (split /\s*[\r\n]+__END__[\r\n]+\s*/, readfile($_));
	}
	for($i = 0; $i < @$c; $i++) {
		if($c->[$i] =~ s/(^|\n)__NAME__\s+([^\n\r]+)\r?\n//) {
			my $name = $2;
			$ref->{$name} = $i;
		}
	}

	return $c;
}

# Designed to parse catalog subroutines and all vars
sub save_variable {
	my ($var, $value) = @_;
	my ($c, $name, $param);

	if(defined $C) {
		$c = $C->{$var};
	}
	else { 
		no strict 'refs';
		$c = ${"Global::$var"};
	}

	if ($var eq 'Variable' || $var eq 'Member') {
		$value =~ s/^\s*(\w+)\s*//;
		$name = $1;
		return 1 if defined $c->{'save'}->{$name};
		$value =~ s/\s+$//;
		$c->{'save'}->{$name} = $value;
	}
	elsif ( !defined $C) { 
		return 0;
	}
	elsif ( defined $C->{Source}{$var} && ref $C->{Source}{$var}) {
		push @{$C->{Source}{$var}}, $value;
	}
	elsif ( defined $C->{Source}{$var}) {
		$C->{Source}{$var} .= "\n$value";
	}
	else {
		$C->{Source}{$var} = $value;
	}
	return 1;

}

my %tagCanon = ( qw(

	group			Group
	actionmap		ActionMap
	arraycode		ArrayCode
	hashcode		HashCode
	coretag  		CoreTag
	filter			Filter
	formaction		FormAction
	ordercheck		OrderCheck
	usertag			UserTag
	systemtag		SystemTag
	widget  		Widget

	alias			Alias
	addattr  		addAttr
	attralias		attrAlias
	cannest			canNest
	description  	Description
	documentation	Documentation
	gobble			Gobble
	hasendtag		hasEndTag
	implicit		Implicit
	interpolate		Interpolate
	invalidatecache	InvalidateCache
	isendanchor		isEndAnchor
	norearrange		noRearrange
	order			Order
	posnumber		PosNumber
	posroutine		PosRoutine
	maproutine		MapRoutine
	noreparse		NoReparse
	required		Required
	routine			Routine
	version			Version
));


my %tagAry 	= ( qw! Order 1 Required 1 Version 1 ! );
my %tagHash	= ( qw!
                attrAlias   1
                Implicit    1
				! );
my %tagBool = ( qw!
                ActionMap   1
                addAttr     1
                canNest     1
                Filter      1
                FormAction  1
                hasEndTag   1
                Interpolate 1
                isEndAnchor 1
                isOperator  1
                ItemAction  1
				noRearrange	1
		NoReparse   1
                OrderCheck  1
                UserTag     1
				! );

my %current_dest;
my %valid_dest = qw/
					actionmap        ActionMap
					coretag          UserTag
					filter           Filter
					formaction       FormAction
					itemaction       ItemAction
					ordercheck       OrderCheck
					usertag          UserTag
					hashcode         HashCode
					arraycode        ArrayCode
					widget           Widget
				/;

sub finalize_mapped_code {
	my $c = $C ? $C->{CodeDef} : $Global::CodeDef;
	my $ref;
	my $cfg;

	if(! $C and my $ref = $c->{Filter}) {
		next unless $ref = $ref->{Routine};
		for(keys %$ref) {
			$Vend::Interpolate::Filter{$_} = $ref->{$_};
		}
	}

	if(! $C and $ref = $c->{OrderCheck} and $ref->{Routine}) {
		$Vend::Order::OrderCheck = $ref->{Routine};
	}

	no strict 'refs';
	for my $type (qw/ ActionMap FormAction ItemAction /) {
		my $ref;
		my $r;
		next unless $r = $c->{$type};
		next unless $ref = $r->{Routine};
		my $cfg = $C
				  ? ($C->{$type}		||= {})
				  : (${"Global::$type"}	||= {})
				  ;
		for(keys %$ref ) {
			$cfg->{$_} = $ref->{$_};
		}
	}
}

my %Compiled = qw/
					Routine     Routine
					PosRoutine  PosRoutine
					HashCode    Routine
					ArrayCode   Routine
				/;

sub parse_mapped_code {
	my ($var, $value) = @_;

	return {} if ! $value;

	## Can't give CodeDef a default or this will be premature
	get_system_code() unless defined $SystemCodeDone;

	my($tag,$p,$val) = split /\s+/, $value, 3;
	
	# Canonicalize
	$p = $tagCanon{lc $p};
	$tag =~ tr/-/_/;
	$tag =~ s/\W//g
		and config_warn("Bad characters removed from '%s'.", $tag);

	my $repos = $C ? ($C->{CodeDef} ||= {}) : ($Global::CodeDef ||= {});

	my $dest = $valid_dest{lc $p} || $current_dest{$tag} || $CodeDest;

	if(! $dest) {
		config_warn("no destination for %s %s, skipping.", $var, $tag);
		return $repos;
	}
	$current_dest{$tag} = $dest;
	$repos->{$dest} ||= {};

	my $c = $repos->{$dest};

	if($Compiled{$p}) {
		$c->{$Compiled{$p}} ||= {};
		parse_action($var, "$tag $val", $c->{$Compiled{$p}} ||= {});
	}
	elsif(defined $tagAry{$p}) {
		my(@v) = Text::ParseWords::shellwords($val);
		$c->{$p}{$tag} = [] unless defined $c->{$p}{$tag};
		push @{$c->{$p}{$tag}}, @v;
	}
	elsif(defined $tagHash{$p}) {
		my(%v) = Text::ParseWords::shellwords($val);
		$c->{$p}{$tag} = {} unless defined $c->{$p}{$tag};
		for (keys %v) {
		  $c->{$p}{$tag}{$_} = $v{$_};
		}
	}
	elsif(defined $tagBool{$p}) {
		$c->{$p}{$tag} = 1
			unless defined $val and $val =~ /^[0nf]/i;
	}
	else {
		config_warn("%s %s scalar parameter %s redefined.", $var, $tag, $p)
			if defined $c->{$p}{$tag};
		$c->{$p}{$tag} = $val;
	}

	return $repos;
}

# Parses the user tags
sub parse_tag {
	my ($var, $value) = @_;
	my ($new);

	return if $Vend::ExternalProgram;

	unless (defined $value && $value) { 
		return {};
	}

	return parse_mapped_code($var, $value)
		if $var ne 'UserTag';

	get_system_code() unless defined $SystemCodeDone;

	my $c = defined $C ? $C->{UserTag} : $Global::UserTag;

	my($tag,$p,$val) = split /\s+/, $value, 3;
	
	# Canonicalize
	$p = $tagCanon{lc $p};
	$tag =~ tr/-/_/;
	$tag =~ s/\W//g
		and config_warn("Bad characters removed from '%s'.", $tag);

	unless ($p) {
		config_warn("Bad user tag parameter '%s' for '%s', skipping.", $p, $tag);
		return $c;
	}

	if($CodeDest and $CodeDest eq 'CoreTag') {
		return $c unless $Global::TagInclude->{$tag} || $Global::TagInclude->{ALL};
	}

	if($p eq 'Routine' or $p eq 'PosRoutine') {
		if (defined $c->{Source}->{$tag}->{$p}){
			config_error(
				errmsg(
					"Duplicate usertag %s found",
					$tag,
				)
			);
		}
		if (defined $C && defined $Global::UserTag->{Source}->{$tag}->{$p}){
			config_warn(
				errmsg(
					"Local usertag %s overrides global definition",
					$tag,
				)
			);
		}

		my $sub;
		$c->{Source}->{$tag}->{$p} = $val;
		unless(!defined $C or $Global::AllowGlobal->{$C->{CatalogName}}) {
			my $safe = new Safe;
			my $code = $val;
			$code =~ s'$Vend::Session->'$foo'g;
			$code =~ s'$Vend::Cfg->'$bar'g;
			$safe->trap(@{$Global::SafeTrap});
			$safe->untrap(@{$Global::SafeUntrap});
			$sub = $safe->reval($code);
			if($@) {
				config_warn(
						"UserTag '%s' subroutine failed safe check: %s",
						$tag,
						$@,
				);
				return $c;
			}
		}
		local($^W) = 1;
		my $fail = '';
		{
			local $SIG{'__WARN__'} = sub {$fail .= "$_[0]\n";};
			eval {
				package Vend::Interpolate;
				$sub = eval $val;
			};
		}
		if($@) {
			config_warn(
						"UserTag '%s' subroutine failed compilation:\n\n\t%s",
						$tag,
					"$@ (warnings=$fail)",
			);
			return $c;
		}
		elsif($fail) {
			config_warn(
						"Warning while compiling UserTag '%s':\n\n\t%s",
					$tag,
						$fail,
			);
			return $c;
		}
		config_warn(
				"UserTag '%s' code is not a subroutine reference",
				$tag,
		) unless ref($sub) eq 'CODE';

		$c->{$p}{$tag} = $sub;
		$c->{Order}{$tag} = []
			unless defined $c->{Order}{$tag};
	}
	elsif (! $C and $p eq 'MapRoutine') {
		$val =~ s/^\s+//;
		$val =~ s/\s+$//;
		no strict 'refs';
		$c->{Routine}{$tag} = \&{"$val"};
		$c->{Order}{$tag} = []
			unless defined $c->{Order}{$tag};
	}
	elsif(defined $tagAry{$p}) {
		my(@v) = Text::ParseWords::shellwords($val);
		$c->{$p}{$tag} = [] unless defined $c->{$p}{$tag};
		push @{$c->{$p}{$tag}}, @v;
	}
	elsif(defined $tagHash{$p}) {
		my(%v) = Text::ParseWords::shellwords($val);
		$c->{$p}{$tag} = {} unless defined $c->{$p}{$tag};
		for (keys %v) {
		  $c->{$p}{$tag}{$_} = $v{$_};
		}
	}
	elsif(defined $tagBool{$p}) {
		$c->{$p}{$tag} = 1
			unless defined $val and $val =~ /^[0nf]/i;
	}
	else {
		config_warn("UserTag %s scalar parameter %s redefined.", $tag, $p)
			if defined $c->{$p}{$tag};
		$c->{$p}{$tag} = $val;
	}

	return $c;
}

sub parse_eval {
	my($var,$value) = @_;
	return '' unless $value =~ /\S/;
	return if $Vend::ExternalProgram;
	return eval $value;
}

# Designed to parse all Variable settings
sub parse_variable {
	my ($var, $value) = @_;
	my ($c, $name, $param);

	# Allow certain catalogs global subs
	unless (defined $value and $value) { 
		$c = { 'save' => {} };
		return $c;
	}

	if(defined $C) {
		$c = $C->{$var};
	}
	else {
		no strict 'refs';
		$c = ${"Global::$var"};
	}

	($name, $param) = split /\s+/, $value, 2;
	chomp $param;
	$c->{$name} = $param;
	return $c;
}


# Parse Sub and GlobalSub
sub parse_subroutine {
	my ($var, $value) = @_;
	my ($c, $name);

	return if $Vend::ExternalProgram;

#::logDebug("parsing subroutine $var, " . substr($value, 0, 20) ) unless $C;
	unless (defined $value and $value) { 
		$c = {};
		return $c;
	}
#::logDebug("into parse for $var") unless $C;

	no strict 'refs';
	$c = defined $C ? $C->{$var} : ${"Global::$var"};

	$value =~ s/^(\w+\s+)?\s*sub\s+(\w+\s*)?{/sub {/;

	if($1 and $2) {
		$name = $1;
		my $alt = $2;
		$name =~ s/\s+//;
		$alt =~ s/\s+//;
		config_warn("%s %s: named also %s?", $var, $name, $alt);
		
	}
	else {
		$name = $1 || $2;
	}

	unless ($name) {
		config_error(
			errmsg(
				"Bad %s: no subroutine name",
				$var,
			)
		);
	}

	$name =~ s/\s+//g;
#::logDebug("into parse for $var, found sub named $name") unless $C;
	# Untainting
	$value =~ /([\000-\377]*)/;
	$value = $1;

	if(! defined $C) {
		$c->{$name} = eval $value;
	}
	elsif($Global::AllowGlobal->{$C->{CatalogName}}) {
		package Vend::Interpolate;
		$c->{$name} = eval $value;
	}
	else {
		package Vend::Interpolate;
		my $calc = Vend::Interpolate::reset_calc();
		package Vend::Config;
		$C->{ActionMap} = { _mvsafe => $calc }
			if ! defined $C->{ActionMap}{_mvsafe};
		$c->{$name} = $C->{ActionMap}{_mvsafe}->reval($value);
	}

#::logDebug("Parsing subroutine/variable (C=$C) $var=$name");
	config_error("Bad $var '$name'") if $@;
#::logDebug("Parsed subroutine/variable $var=$name code=$c->{$name}") unless $C;
	return $c;
}

sub parse_delimiter {
	my ($var, $value) = @_;

	return "\t" unless (defined $value && $value); 

	$C->{Source}->{$var} = $value;
	
	$value =~ /^CSV$/i and return 'CSV';
	$value =~ /^tab$/i and return "\t";
	$value =~ /^pipe$/i and return "\|";
	$value =~ s/^\\// and return $value;
	$value =~ s/^'(.*)'$/$1/ and return $value;
	return quotemeta $value;
}

# Returns 1 for Yes and 0 for No.

sub parse_yesno {
	my($var, $value) = @_;
	$_ = $value;
	if (m/^y/i || m/^t/i || m/^1/ || m/^on/i) {
		return 1;
	}
	elsif (m/^n/i || m/^f/i || m/^0/ || m/^of/i) {
		return 0;
	}
	else {
		config_error("Use 'yes' or 'no' for the $var directive\n");
	}
}

sub parse_permission {
	my($var, $value) = @_;

	$_ = $value;
	tr/A-Z/a-z/;
	if ($_ ne 'user' and $_ ne 'group' and $_ ne 'world') {
		config_error("Permission must be one of 'user', 'group', or 'world' for the $var directive\n");
	}
	$_;
}

$StdTags = <<'EOF';
				:core "
					accessories
					area
					assign
					attr_list
					banner
					calc
					calcn
					cart
					catch
					cgi
					charge
					checked
					control
					control_set
					counter
					currency
					data
					default
					description
					discount
					dump
					ecml
					either
					error
					export
					field
					file
					filter
					flag
					fly_list
					fly_tax
					handling
					harness
					html_table
					import
					include
					index
					input_filter
					item_list
					log
					loop
					mail
					msg
					mvasp
					nitems
					onfly
					options
					order
					page
					perl
					price
					process
					profile
					query
					read_cookie
					record
					region
					row
					salestax
					scratch
					scratchd
					search_region
					selected
					set
					set_cookie
					seti
					setlocale
					shipping
					shipping_desc
					soap
					sql
					strip
					subtotal
					tag
					time
					timed_build
					tmp
					tmpn
					total_cost
					tree
					try
					update
					userdb
					value
					value_extended
					warnings
				"
				:base "
						area
						cgi
						data
						either
						filter
						flag
						loop
						page
						query
						scratch
						scratchd
						set
						seti
						tag
						tmp
						tmpn
						value
				"
				:commerce "
						assign
						cart
						charge
						currency
						description
						discount
						ecml
						error
						field
						fly_list
						fly_tax
						handling
						item_list
						nitems
						onfly
						options
						order
						price
						salestax
						shipping
						shipping_desc
						subtotal
						total_cost
						userdb
				"
				:data "
						data
						export
						field
						flag
						import
						index
						query
						record
						sql
				"
				:form "
					accessories
					cgi
					checked
					error
					flag
					input_filter
					msg
					process
					profile
					selected
					update
					value_extended
					warnings
				"
				:debug "
					catch
					dump
					error
					flag
					harness
					log
					msg
					tag
					try
					warnings
				"
				:file "
					counter
					file
					include
					log
					value_extended
				"
				:http "
					area
					cgi
					filter
					input_filter
					page
					process
					read_cookie
					set_cookie
					value_extended
				"
				:crufty "
					banner
					default
					ecml
					html_table
					onfly
					sql
				"
				:text "
					row
					strip
					filter
				"
				:html "
					accessories
					checked
					filter
					html_table
					process
				"
				:mail "
					mail
				"
				:perl "
					perl
					calc
					calcn
					mvasp
				"
				:time "
					time
				"
EOF

1;

__DATA__
mv_all_chars             ac
mv_arg                   mv_arg
mv_base_directory        bd
mv_begin_string          bs
mv_case                  cs
mv_cat                   mv_cat
mv_column_op             op
mv_coordinate            co
mv_delay_page            dp
mv_dict_end              de
mv_dict_fold             df
mv_dict_limit            di
mv_dict_look             dl
mv_dict_order            do
mv_exact_match           em
mv_field_names           fn
mv_first_match           fm
mv_head_skip             hs
mv_index_delim           ix
mv_list_only             lo
mv_matchlimit            ml
mv_max_matches           mm
mv_min_string            ms
mv_more_id               mi
mv_more_matches          MM
mv_negate                ne
mv_numeric               nu
mv_orsearch              os
mv_pc                    mv_pc
mv_profile               mp
mv_range_alpha           rg
mv_range_look            rl
mv_range_max             rx
mv_range_min             rm
mv_record_delim          dr
mv_return_all            ra
mv_return_delim          rd
mv_return_fields         rf
mv_return_file_name      rn
mv_return_reference      rr
mv_return_spec           rs
mv_search_field          sf
mv_search_file           fi
mv_search_immediate      si
mv_search_line_return    lr
mv_search_page           sp
mv_searchspec            se
mv_searchtype            st
mv_session_id            id
mv_sort_field            tf
mv_sort_option           to
mv_spelling_errors       er
mv_sql_query             sq
mv_substring_match       su
mv_unique                un
mv_value                 va
