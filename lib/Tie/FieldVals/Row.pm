package Tie::FieldVals::Row;
use strict;
use warnings;

=head1 NAME

Tie::FieldVals::Row - a hash tie for rows (records) of Tie::FieldVals data

=head1 VERSION

This describes version B<0.10> of Tie::FieldVals::Row.

=cut

our $VERSION = '0.10';

=head1 SYNOPSIS

    use Tie::FieldVals::Row;

    my %person;
    my @keys = qw(Forename Surname DateOfBirth Gender);
    my $row_obj = tie %person, 'Tie::FieldVals::Row', fields=>\@keys;

    # set the row
    $row_obj->set_from_string($row_str,override_keys=>1);

    # compare the row
    if ($row_obj->match(Forename=>'Mary'))
    {
	# do something
    }

=head1 DESCRIPTION

This is a Tie object to map a row (record) of enhanced Field:Value data to
a hash.  This sets fixed keys so that they match the columns of the data.
Values can go over more than one line.  Fields can have multiple values.

Field names cannot have spaces in them, indeed, they must consist of plain
alphanumeric characters or underscores.  They are case-sensitive.

=cut

use 5.006;
use strict;
use Carp;

# to make taint happy
$ENV{PATH} = "/bin:/usr/bin:/usr/local/bin";
$ENV{CDPATH} = '';
$ENV{BASH_ENV} = '';

# for debugging
my $DEBUG = 0;

=head1 OBJECT METHODS
 
=head2 set_from_string

Set the hash data from an enhanced Field:Value data string.

$row_obj->set_from_string($record_str);

$row_obj->set_from_string($record_str,
    override_keys=>1);

The format of the string is basically a multi-line string
in Field:Value format, with the addition that if a line does
not start with a known fieldname followed by a colon, that
the contents of that line is added to the value of the previous
field.

If a particular FieldName is repeated, its value is added to
the existing value of that FieldName, and it becomes a
multi-value field.

If override_keys is true, then the official fields, the legal
keys to this hash, are reset from the Field: contents of this
string.

=cut
sub set_from_string ($$;%) {
    my $self = shift;
    my $record_str = shift;
    my %args = (
	override_keys=>0,
	@_
	);

    # if we are overriding the keys, simply clear
    # the whole self-hash
    if ($args{override_keys})
    {
	%{$self->{FIELDS}} = ();
	$self->{OPTIONS}->{fields} = [];
    }
    else
    {
	# otherwise call the Tied CLEAR
	$self->CLEAR();
    }

    # the lines contain either field:value pairs
    # or continuations of the previous field's value
    my @fields = ();
    my @lines = split(/\n/, $record_str);
    my $cur_field = '';
    while (@lines)
    {
	my $line = shift @lines;
	if ($line =~ /^([a-zA-Z][-_a-zA-Z0-9]*):(.*)$/)
	{
	    my $field = $1;
	    my $val = $2;
	    if ($args{override_keys}
		|| exists $self->{FIELDS}->{$field})
	    {
		$cur_field = $field;
		if (!defined $self->{FIELDS}->{$field})
		{
		    $self->{FIELDS}->{$field} = [];
		}
		push @{$self->{FIELDS}->{$field}}, $val;
		if ($args{override_keys})
		{
		    push @{$self->{OPTIONS}->{fields}}, $field;
		}
	    }
	    elsif ($cur_field)
	    {
		# not a field -- must be a value
		# append the current line to the last field
		my $count = @{$self->{FIELDS}->{$cur_field}};
		${$self->{FIELDS}->{$cur_field}}[$count - 1] .= "\n$line";
	    }
	}
	elsif ($cur_field)
	{
	    # append the current line to the last field
	    my $count = @{$self->{FIELDS}->{$cur_field}};
	    ${$self->{FIELDS}->{$cur_field}}[$count - 1] .= "\n$line";
	}
    }
} # set_from_string

=head2 set_from_xml_string

Set the hash data from an XML string.

$row_obj->set_from_xml_string($record_str);

$row_obj->set_from_xml_string($record_str,
    override_keys=>1);

The format of this XML string is as follows:

    <record>
	<Field>Value</Field>
	<AnotherField>AnotherValue</AnotherField>
	...
    </record>

If a particular FieldName is repeated, its value is added to
the existing value of that FieldName, and it becomes a
multi-value field.

If override_keys is true, then the official fields, the legal
keys to this hash, are reset from the <Field> contents of this
string.

=cut
sub set_from_xml_string ($$;%) {
    my $self = shift;
    my $record_str = shift;
    my %args = (
	override_keys=>0,
	@_
	);

    # if we are overriding the keys, simply clear
    # the whole self-hash
    if ($args{override_keys})
    {
	%{$self->{FIELDS}} = ();
	$self->{OPTIONS}->{fields} = [];
    }
    else
    {
	# otherwise call the Tied CLEAR
	$self->CLEAR();
    }

    # record_str should contain ...<record>...</record>
    # or just the fields
    if ($record_str =~ m#<record>(.*)</record>#s)
    {
	$record_str = $1;
    }
    # now record_str should just contain the fields
    # eg <Author>...</Author>...<Review>..</Review>
    my @all_fields = split(/(<[a-zA-Z][-_a-zA-Z0-9]*>|<\/[a-zA-Z][-_a-zA-Z0-9]*>)/, $record_str);
    while (@all_fields)
    {
	my $fld = shift @all_fields;
	# is this a valid start-tag?
	if ($fld =~ m#<([a-zA-Z][-_a-zA-Z0-9]*)>#)
	{
	    my $field = $1;
	    # is this a legal key?
	    if ($args{override_keys}
		|| exists $self->{FIELDS}->{$field})
	    {
		my $val = shift @all_fields;
		# restore the special characters to their real meanings
		$val =~ s/&gt;/>/g;
		$val =~ s/&lt;/</g;
		$val =~ s/&quot;/"/g;
		$val =~ s/&apos;/'/g;
		$val =~ s/&amp;/&/g;
		if (!defined $self->{FIELDS}->{$field})
		{
		    $self->{FIELDS}->{$field} = [];
		}
		push @{$self->{FIELDS}->{$field}}, $val;
	    }
	    if ($args{override_keys})
	    {
		push @{$self->{OPTIONS}->{fields}}, $field;
	    }
	}
    }
} # set_from_xml_string

=head2 get_as_string

Returns the hash data as a string in the same format as
expected by L</set_from_string>.

my $str = $row_obj->get_as_string();

=cut
sub get_as_string ($) {
    my $self = shift;

    my $out = '';
    foreach my $field (@{$self->{OPTIONS}->{fields}})
    {
	my $num_vals = $self->field_count($field);
	for (my $i=0; $i < $num_vals; $i++)
	{
	    my $val = $self->FETCH({$field=>$i});
	    $out .= "${field}:";
	    $out .= $val;
	    $out .= "\n";
	}
    }
    $out =~ s/\n$//;

    return $out;
} # get_as_string

=head2 get_xml_string

Returns the hash data as an XML string in the same
format as expected by L</set_from_xml_string>.

my $str = $row_obj->get_xml_string();

=cut
sub get_xml_string ($) {
    my $self = shift;

    my $out = '';
    $out .= "<record>\n";
    foreach my $field (@{$self->{OPTIONS}->{fields}})
    {
	my $num_vals = $self->field_count($field);
	for (my $i=0; $i < $num_vals; $i++)
	{
	    my $val = $self->FETCH({$field=>$i});
	    $val =~ s/&/&amp;/g;
	    $val =~ s/</&lt;/g;
	    $val =~ s/>/&gt;/g;
	    $out .= "<${field}>";
	    $out .= $val;
	    $out .= "</${field}>";
	    $out .= "\n";
	}
    }
    $out .= "</record>\n";

    return $out;
} # get_xml_string

=head2 field_names

my @field_names = @{$row_obj->field_names()};

Return the names of the fields in the order they were defined,
rather than the random order that "keys" would give.
This will either be the array which was used when the hash
was tied, or the order that fields were read from a string
if set_from_string or set_from_xml_string is called with
override_fields true.

=cut
sub field_names ($) {
    my $self = shift;

    return $self->{OPTIONS}->{fields};
} # field_names

=head2 field_count

    my $cnt = $row_obj->field_count($field_name);

Return the number of different field values for the
given field in the given Row.  A multi-valued field
will give a count greater than 1.

If there is no value defined for the given field, then returns zero.

=cut
sub field_count ($$) {
    my $self = shift;
    my $field_name = shift;

    my $count = 0;
    if (!exists $self->{FIELDS}->{$field_name}
	|| !defined $self->{FIELDS}->{$field_name})
    {
	return 0;
    }

    if (ref($self->{FIELDS}->{$field_name}) eq 'ARRAY')
    {
	$count = @{$self->{FIELDS}->{$field_name}};
    }
    elsif (!ref($self->{FIELDS}->{$field_name}))
    {
	$count = 1;
    }
    else
    {
	warn "record->${field_name} not array";
	warn Dumper($self->{FIELDS});
    }

    return $count;
} # field_count

=head2 nice_value

    $self->nice_value(field_name=>$fname,
	field_value=>$value,
	reorder_value_fields=>{Name=>','});

Give the "nice" value of a field.  This is used for things like where
a field Name: is in the form of Lastname,Firstname
and one wishes to get the value in the form "Firstname Lastname".

If the given field is not in the B<reorder_value_fields> hash, then
the "nice" value of the field is simply the value of the field.

=cut
sub nice_value($%) {
    my $self = shift;
    my %args = (
	field_name=>'',
	field_value=>'',
	reorder_value_fields=>undef,
	@_
    );
    my $field_name = $args{field_name};
    my $val = $args{field_value};
    if ($val
	&& defined $args{reorder_value_fields}
	&& exists $args{reorder_value_fields}->{$field_name}
	&& defined $args{reorder_value_fields}->{$field_name})
    {
	$val = reorder_value($val,
	    $args{reorder_value_fields}->{$field_name});
    }
    return $val;
} # nice_value

=head2 reorder_value

    reorder_value($value,$separator)

Gives the value "reordered" around a separator char.
For example Lastname,Firstname becomes "Firstname Lastname"
if the separator is ','.

=cut
sub reorder_value($$) {
    my $value = shift;
    my $separator = shift;

    my $ret_val = $value;
    if ($value =~ m/${separator}/)
    {
	my ($first, $last) = split(/${separator}/, $value, 2);
	$ret_val = join(' ', ($last, $first))
    }
    $ret_val;
} # reorder_value

=head2 set_fields_as_vars

    $row_obj->set_fields_as_vars($package_name);

    $row_obj->set_fields_as_vars($package_name,
	field_ind=>$field_ind);

Sets the data of the hash as variables with the same name as the
field name; multi-valued fields have arrays of the field name.

These are set in the given package.

Arguments:

=over

=item field_ind

For multi-valued fields, the @I<Field> variable is set, but also the
$I<Field> variable will be set, to the value of the variable with
B<field_ind> index. (default: 0)

=item reorder_value_fields

Same as the argument in L</nice_value>.

=item nice_prefix

The prefix for the variable-name for the "nice" value of a variable.
(default: Nice_)

=item raw_prefix

The prefix for the variable-name for the unprocessed value of a variable.
(default: Raw_)

=back

=cut
sub set_fields_as_vars ($;%) {
    my $self = shift;
    my $pkg_name = shift;
    my %args = (
	field_ind=>0,
	reorder_value_fields=>undef,
	nice_prefix=>'Nice_',
	raw_prefix=>'Raw_',
	@_
    );

    my $field_ind = $args{field_ind};
    my $nice_prefix = $args{nice_prefix};
    my $raw_prefix = $args{raw_prefix};

    while (my ($key, $value) = each %{$self->{FIELDS}})
    {
	$key =~ m#([a-zA-Z0-9][-_a-zA-Z0-9]*)#; # keep taint happy
	my $field = $1;
	my $varname = "${pkg_name}::${field}";
	my $nice_varname = "${pkg_name}::${nice_prefix}${field}";
	my $raw_varname = "${pkg_name}::${raw_prefix}${field}";
	if (ref $value eq 'ARRAY')
	{
	    no strict 'refs';
	    my $num_vals = @{$value};
	    for (my $i=0; $i < $num_vals; $i++)
	    {
		my $tval = ${$value}[$i];
		$tval =~ m#([^`]*)#s;
		my $val = $1;
		my $niceval = $self->nice_value(field_name=>$field,
		    field_value=>$val,
		    reorder_value_fields=>$args{reorder_value_fields});
		if ($num_vals > 0)
		{
		    if ($i == 0)
		    {
			$$varname = $val;
			@$varname = ();
			$$nice_varname = $niceval;
			@$nice_varname = ();
		    }
		    elsif ($i == $field_ind)
		    {
			$$varname = $val;
			$$nice_varname = $niceval;
		    }
		    $$varname[$i] = $val;
		    $$nice_varname[$i] = $niceval;
		}
		else
		{
		    $$varname = $val;
		    $$nice_varname = $niceval;
		}
	    }
	}
	elsif (!ref $value)
	{
	    no strict 'refs';
	    $value =~ m#([^`]*)#s;
	    my $val = $1;
	    my $niceval = $self->nice_value(field_name=>$field,
					    field_value=>$val,
		    reorder_value_fields=>$args{reorder_value_fields});
	    $$varname = $val;
	    $$nice_varname = $niceval;
	}
    }
} # set_fields_as_vars

=head2 match

    $row_obj->match(Author=>qr/Li.a/,
	    Universe=>'Buffy',
	    Year=>'> 2001')

Checks if this row matches the hash.
The hash is in the form of Field => value pairs, where
the value can be a plain value,
a comparison (< > = eq ne ...)
or a regular expression.

If the plain value or the comparison starts with '!'
then the sense of the comparison is reversed.

Returns:
    1 if matches all conditions, 0 if fails

=cut
sub match ($%) {
    my $self = shift;
    my %match = (@_);
    my $fields = $self->{FIELDS};
    my $retval = 0;

    my $found = 0;
    while (my ($fn, $re) = each %match)
    {
	my $val = $self->FETCH($fn);
	if (defined $val and is_matched($val, $re))
	{
	    $found++;
	}
    }
    $retval = 1 if $found == scalar keys %match;

    return $retval;
} # match

=head2 match_any

$row_obj->match_any($match_str);

Checks if any field in this row matches the string.

Returns:
    1 if any field matches the string, 0 if fails

=cut
sub match_any ($$) {
    my $self = shift;
    my $match_str = shift;
    my $fields = $self->{FIELDS};
    my $retval = 0;

    my $found = 0;
    while (my $fn = each %{$fields})
    {
	my $val = $self->FETCH($fn);
	if (defined $val and is_matched($val, $match_str))
	{
	    $found++;
	}
    }
    $retval = 1 if ($found > 0);

    return $retval;
} # match_any

=head1 Tie-Hash METHODS

=head2 TIEHASH

Create a new instance of the object as tied to a hash.

    tie %person, 'Tie::FieldVals::Row', fields=>\@keys;

The B<fields> argument defines the names of the legal fields.
Legal fields can also be set from a string when using the B<override_keys>
argument to L</set_from_string> or L</set_from_xml_string>.

=cut
sub TIEHASH {
    carp &whowasi if $DEBUG;
    my $class = shift;
    my %args = (
	fields=>undef,
	@_
    );
    if (!defined $args{fields})
    {
	croak "Tie::FieldVals::Row -- no fields given";
    }
    my @keys = @{$args{fields}};

    my %hash;

    @hash{@keys} = (undef) x @keys;
    my $self = {};
    $self->{FIELDS} = \%hash;
    $self->{OPTIONS} = \%args;

    bless $self, $class;
} # TIEHASH

=head2 FETCH

Get a key=>value from the hash.
Some values may be multi-values, and can be gotten by array index.
If a key is not an official key, undefined is returned.

    $val = $hash{$key}
    $val = $hash{{$key=>0}}; # 0th element of $key field
    $val = $hash{[$key,2]}; # 3rd element of $key field
    $val = $hash{{$key=>undef}}; # whole key field as array ref

See also L</field_count> to determine whether a field is a multi-valued
field.

=cut
sub FETCH {
    carp &whowasi if $DEBUG;
    my ($self, $match) = @_;
    my $key = '';
    my $ind;
    my $matching = 0;

    if (ref $match) {
	# we're doing a compare, but only use the first
	# key - compare pair
	if (ref $match eq 'HASH') {
	    my @keys = keys %{$match};
	    $key = shift @keys;
	    $ind = $match->{$key};
	    $matching = 1;
	}
	elsif (ref $match eq 'ARRAY') {
	    $key = shift @{$match};
	    $ind = shift @{$match};
	    $matching = 1;
	}
	else {
	    carp "invalid match to FETCH hash";
	    return undef;
	}
    }
    else {
	$key = $match; # just a plain key
    }

    unless (exists $self->{FIELDS}->{$key}) {
	return undef;
    }

    if (ref $self->{FIELDS}->{$key} eq 'ARRAY') {
	my $count = @{$self->{FIELDS}->{$key}};
	# if ind is undefined, return whole array
	if ($matching
	    && !defined $ind) {
	    return $self->{FIELDS}->{$key};
	}
	# if there's only one, return it
	elsif ($count == 1) {
	    return @{$self->{FIELDS}->{$key}}[0];
	}
	elsif ($matching
	    && $ind < $count) {
	    return @{$self->{FIELDS}->{$key}}[$ind];
	}
	# if too big, get the last one
	elsif ($matching
	    && $ind >= $count) {
	    return @{$self->{FIELDS}->{$key}}[$count - 1];
	}
	# otherwise return the first field
	else {
	    return @{$self->{FIELDS}->{$key}}[0];
	}
    }
    else {
	return $self->{FIELDS}->{$key};
    }

} # FETCH

=head2 STORE

Add a key=>value to the hash.
Some values may be multi-values, and can be set by array index.
If a key is not an official key, nothing is set, and it
complains of error.

    $hash{$key} = $val;
    $hash{{$key=>0}} = $val; # 0th element of $key field
    $hash{[$key,2]} = $val; # 3rd element of $key field

=cut
sub STORE {
    carp &whowasi if $DEBUG;
    my ($self, $match, $val) = @_;
    my $key = '';
    my $ind = 0;
    my $matching = 0;

    if (ref $match) {
	# we're doing a compare, but only use the first
	# key - compare pair
	if (ref $match eq 'HASH') {
	    my @keys = keys %{$match};
	    $key = shift @keys;
	    $ind = $match->{$key};
	    $matching = 1;
	}
	elsif (ref $match eq 'ARRAY') {
	    $key = shift @{$match};
	    $ind = shift @{$match};
	    $matching = 1;
	}
	else {
	    carp "invalid match to STORE hash";
	    return undef;
	}
    }
    else {
	$key = $match; # just a plain key
    }
    unless (exists $self->{FIELDS}->{$key}) {

	croak "invalid key [$key] in hash\n";
	return;
    }

    if (ref $val) {
	$self->{FIELDS}->{$key} = $val;
    }
    elsif ($matching
	   && ref $self->{FIELDS}->{$key} eq 'ARRAY') {
	my $count = @{$self->{FIELDS}->{$key}};
	if ($ind >= $count) {
	    push @{$self->{FIELDS}->{$key}}, $val;
	}
	elsif ($ind >= 0 && $ind < $count) {
	    @{$self->{FIELDS}->{$key}}[$ind] = $val;
	}
	else {
	    @{$self->{FIELDS}->{$key}}[0] = $val;
	}
    }
    else {
	$self->{FIELDS}->{$key} = [$val];
    }

} # STORE

=head2 DELETE

Remove a key=>value from the hash, only if it exists.

=cut
sub DELETE {
    carp &whowasi if $DEBUG;
    my ($self, $key) = @_;

    return unless exists $self->{FIELDS}->{$key};

    my $ret = $self->{FIELDS}->{$key};

    $self->{FIELDS}->{$key} = undef;

    return $ret;
} # DELETE

=head2 CLEAR

Remove all the data from the hash.

=cut
sub CLEAR {
    carp &whowasi if $DEBUG;
    my $self = shift;

    $self->{FIELDS}->{$_} = undef foreach keys %{$self->{FIELDS}};
} # CLEAR

=head2 EXISTS

Does this key exist?

=cut
sub EXISTS {
    carp &whowasi if $DEBUG;
    my $self = shift;
    my $key = shift;

    return exists $self->{FIELDS}->{$key};
} # EXISTS

=head2 FIRSTKEY

Get the first key of this hash.

=cut
sub FIRSTKEY {
    carp &whowasi if $DEBUG;
    my $self = shift;

    my $a = keys %{$self->{FIELDS}};	# reset each() iterator
    each %{$self->{FIELDS}};
} # FIRSTKEY

=head2 NEXTKEY

Get the next key of this hash.

=cut
sub NEXTKEY {
    carp &whowasi if $DEBUG;
    my $self = shift;
    my $lastkey = shift; # previous key

    each %{$self->{FIELDS}};
} # NEXTKEY

sub DESTROY {
    carp &whowasi if $DEBUG;
}

=head1 PRIVATE METHODS

For developer reference only.
 
=head2 debug

Set debugging on.

=cut
sub debug { $DEBUG = @_ ? shift : 1 }

=head2 whowasi

For debugging: say who called this 

=cut
sub whowasi { (caller(1))[3] . '()' }

=head2 is_matched($str,$re)

Check if the string matches the expression.

=cut
sub is_matched {
    my($str,$re)=@_;
    if (ref $re eq 'Regexp') {
        return $str =~ /$re/ ? 1 : 0;
    }
    my $op;
    my $val;
    my $negate = 0;
    my $retval = 0;

    # if it starts with a ! and isn't !=
    # then negate the match
    if ($re and $re =~ /^![^=]/)
    {
	$negate = 1;
	$re =~ s/^!//;
    }
    if ( $re and $re =~/^(\S*)\s+(.*)/ ) {
	$op  = $1;
	$val = $2;

	my $numop = '< > == != <= >=';
	my $chrop = 'lt gt eq ne le ge';
	if (!($numop =~ /$op/) and !($chrop =~ /$op/)) {
	    $retval = ($str =~ /$re/ ? 1 : 0);
	}
	elsif ($numop =~ /$op/) {
	    my $num = ($str ? $str : 0);
	    if ($op eq '<' ) { $retval = ($num <  $val); }
	    elsif ($op eq '>' ) { $retval = ($num >  $val); }
	    elsif ($op eq '==') { $retval = ($num == $val); }
	    elsif ($op eq '!=') { $retval = ($num != $val); }
	    elsif ($op eq '<=') { $retval = ($num <= $val); }
	    elsif ($op eq '>=') { $retval = ($num >= $val); }
	} else {
	    if ($op eq 'lt') { $retval = ($str lt $val); }
	    elsif ($op eq 'gt') { $retval = ($str gt $val); }
	    elsif ($op eq 'eq') { $retval = ($str eq $val); }
	    elsif ($op eq 'ne') { $retval = ($str ne $val); }
	    elsif ($op eq 'le') { $retval = ($str le $val); }
	    elsif ($op eq 'ge') { $retval = ($str ge $val); }
	}

    }
    elsif ($re) {
        $retval = ($str =~ /$re/ ? 1 : 0);
    }
    else {
        $retval = ($str eq '' ? 1 : 0);
    }

    if ($negate)
    {
	return (!$retval);
    }
    return $retval;
}

=head1 REQUIRES

    Test::More
    Carp

=head1 SEE ALSO

perl(1).
L<Tie::FieldVals>

=head1 BUGS

Please report any bugs or feature requests to the author.

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    perlkat AT katspace dot com
    http://www.katspace.com

=head1 COPYRIGHT AND LICENCE

Copyright (c) 2004 by Kathryn Andersen

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of Tie::FieldVals::Row
__END__
