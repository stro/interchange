UserTag read-ui-template Order file 
UserTag read-ui-template addAttr
UserTag read-ui-template Documentation <<EOD
[read-ui-template file="<filespec>" element=name* structure=1|0]

Returns the description of a page as described by a [comment] [/comment]
containing different named elements:

	element: item [: optional data value]

If there is an optional data item, element becomes a hash reference
and is set as a key/value pair with "item" being the key. There can
be multiple keys. Otherwise, "element" is set to a value of "item" as the data.

If the element=name is set in the tag call, then only that element is
returned. IF called by a subroutine wanting an array, an array reference
is returned. Otherwise, a newline-separated set of values is returned.

If the structure=1 is passed in the tag call, a structure is passed
with the page name as the key, and its elements as a hash reference, i.e.

	($ref) = $Tag->read_ui_template('templates/*');

$ref will be like:

  {
    standard => {
                    ui_template_description => 'Standard ....',
                    ui_template_elements => 'LOGOBAR, MENUBAR, LEFTSIDE, UI_CONTENT ....',

                },
    standalone => {
                    ui_template_description => 'Standalone no left side ....',
                    ui_template_elements => 'LOGOBAR, MENUBAR, UI_CONTENT, ....',

                },

EOD

UserTag read-ui-template Routine <<EOR
sub {
	my ($fn, $opt) = @_;
	my @files;
	my $return_structure;
	if(ref $fn) {
		@files = @$fn;
	}
	else {
		@files = glob($fn);
	}

	my $data;
	my %out;
	my @out;
	foreach my $fn (@files) {
		my $name = $fn;
		# force substitution of [L..]-stuff off
		my $savelocale = delete $Vend::Cfg->{Locale};
		$data = Vend::Util::readfile($fn);
		$Vend::Cfg->{Locale} = $savelocale;
		next unless length($data);
		$name =~ s:.*/::;
		my $ref = {};
		$data =~ m{\[comment\]\s*(ui_.*?)\[/comment\]}s;
		my $structure = $1 || '';
		next unless $structure;
		my @lines = split /\n/, $structure;
		my $found;
		for(;;) {
			my $i = -1;
			for(@lines) {
				$i++;
				next unless s/\\$//;
				$found = $i;
				last;
			}
			last unless defined $found;
			if (defined $found) {
				my $add = splice @lines, $found + 1, 1;
#::logDebug("Add is '$add', found index=$found");
				$lines[$found] .= $add;
#::logDebug("Complete line now is '$lines[$found]'");
				undef $found;
			}
		}
		$ref->{ui_definition} = join "\n", @lines;
		my $current;
	
		for(@lines) {
			if(/^\s*ui_/) {
				my ($el, $el_item, $el_data) = split /\s*:\s*/, $_;
#::logDebug("found el=$el el_item=$el_item el_data=$el_data");
				if(defined $el_data) {
					$ref->{$el} = { } if ! ref($ref->{$el});
					$ref->{$el}{$el_item} = $el_data;
				}
				else {
					$ref->{$el} = $el_item;
				}
			}
			elsif ( /^(\w+)\s*:\s*(.*)$/) {
				$current = $1;
				$ref->{element}{$current} = $2;
				$ref->{ui_display_order} = [] if ! $ref->{ui_display_order};
				push @{$ref->{ui_display_order}}, $current;
			}
			elsif( /^\s+(\w+)\s*:\s*(.*)/ ) {
				my ($fn, $fv) = ( lc($1), $2 );
				$ref->{$fn}{$current} = $fv;
			}
		}
		if($opt->{structure}) {
			$out{$fn} = $ref;
		}
		elsif($opt->{element}) {
			push @out, $ref->{$opt->{element}};
		}
		else {
			push @out, $ref;
		}
	}

	if(wantarray) {
		return \%out if $opt->{structure};
		return \@out;
	}
	elsif($opt->{structure}) {
		return ::uneval(\%out);
	}
	else {
		return join "\n", @out;
	}

}
EOR
