package Tie::FieldVals::Join::Row;
use strict;
use warnings;

=head1 NAME

Tie::FieldVals::Join::Row - a hash tie for two rows of Tie::FieldVals data

=head1 VERSION

This describes version B<0.01> of Tie::FieldVals::Join::Row.

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use Tie::FieldVals::Row;
    use Tie::FieldVals::Join::Row;

    my %person;

    my @keys = qw(Forename Surname DateOfBirth Gender);

    tie %person, 'Tie::FieldVals::Row', fields=>\@keys;

    my %thing;

    my @keys2 = qw(Forename House Car TV);

    tie %thing, 'Tie::FieldVals::Row', fields=>\@keys2;

    my %person_thing;
    tie %person_thing, 'Tie::FieldVals::Join::Row,
	rows=>[\%person, \%thing];

=head1 DESCRIPTION

This is a Tie object to map two Tie::FieldVals::Row hashes to
one hash.

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

#================================================================
# Object Methods

=head1 OBJECT METHODS
 
=head2 set_from_strings

Set the hash data from some enhanced Field:Value data strings.

$hash_obj->set_from_strings([$str1, $str2]);

$hash_obj->set_from_strings([$str1, $str2],
    override_keys=>1);

=cut
sub set_from_strings ($$;%) {
    my $self = shift;
    my $str_arr_ref = shift;
    my %args = (
	override_keys=>0,
	@_
	);

    for (my $i=0; $i < @{$self->{ROWS}}
	and $i < @{$str_arr_ref}; $i++)
    {
	my $row_ref = $self->{ROWS}->[$i];
	my $row_obj = tied %{$row_ref};
	$row_obj->set_from_string($str_arr_ref->[$i], %args);
    }
    if ($args{override_keys})
    {
	# reset the fields
	$self->{FIELDS} = {};
	$self->{ROW_KEYS} = [];
	my $i=0;
	foreach my $row_ref (@{$self->{ROWS}})
	{
	    $self->{ROW_KEYS}->[$i] = {};
	    foreach my $key (keys %{$row_ref})
	    {
		$self->{FIELDS}->{$key} = 1;
		$self->{ROW_KEYS}->[$i]->{$key} = 1;
	    }
	    $i++;
	}
    }
} # set_from_strings

=head2 get_as_strings

Returns the hash data as an array of Field:Value strings.

my @str_array = $hash_obj->get_as_string();

=cut
sub get_as_strings ($) {
    my $self = shift;

    my @str_array = ();
    foreach my $row_ref (@{$self->{ROWS}})
    {
	my $row_obj = tied %{$row_ref};
	push @str_array, $row_obj->get_as_string();
    }
    return @str_array;
} # get_as_strings

=head2 field_count

    my $cnt = $hash_obj->field_count($field_name);

Return the number of different field values for the
given field in the given record.  A multi-valued field
will give a count greater than 1.

If there is no value defined for the given field, then returns zero.

=cut
sub field_count ($$) {
    my $self = shift;
    my $field_name = shift;

    my $count = 0;
    my $val = undef;
    for (my $i=0; $i < @{$self->{ROWS}}; $i++)
    {
	if (exists $self->{ROW_KEYS}->[$i]->{$field_name})
	{
	    my $fr = {$field_name=>undef};
	    $val = $self->{ROWS}->[$i]->{$fr};
	}
    }
    if (!defined $val)
    {
	return 0;
    }

    if (ref $val eq 'ARRAY')
    {
	$count = @{$val};
    }
    elsif (!ref $val)
    {
	$count = 1;
    }
    else
    {
	warn "record->${field_name} not array";
	warn Dumper($self);
    }

    return $count;
} # field_count

=head2 set_fields_as_vars

    $hash_obj->set_fields_as_vars($package_name);

    $hash_obj->set_fields_as_vars($package_name,
	field_ind=>$field_ind,
	reorder_value_fields=>{Author=>','});

Sets the data of the hash as variables with the same name as the
field name; multi-valued fields have arrays of the field name.

These are set in the given package.

See L<Tie::FieldVals::Row/set_fields_as_vars> for more information.

=cut
sub set_fields_as_vars ($;%) {
    my $self = shift;
    my $pkg_name = shift;
    my %args = (
	field_ind=>0,
	reorder_value_fields=>undef,
	@_
    );

    my $field_ind = $args{field_ind};

    foreach my $row_ref (@{$self->{ROWS}})
    {
	my $row_obj = tied %{$row_ref};
	$row_obj->set_fields_as_vars($pkg_name,
	    field_ind=>$field_ind,
	    reorder_value_fields=>$args{reorder_value_fields});
    }
} # set_fields_as_vars

=head2 match

    $hash_obj->match(Author=>qr/Li.a/,
	    Universe=>'Buffy',
	    Year=>'> 2001')

Checks if this row matches the hash.
The hash is in the form of Field => value pairs, where
the value can be a plain value
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

$hash_obj->match_any($match_str);

Checks any field in this row matches the string.

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

#================================================================
# Tie interface

=head1 TIE-HASH METHODS

=head2 TIEHASH

Create a new instance of the object as tied to a hash.

    tie %person, 'Tie::FieldVals::Row', fields=>\@keys;
    tie %thing, 'Tie::FieldVals::Row', fields=>\@keys2;

    my %person_thing;
    tie %person_thing, 'Tie::FieldVals::Join::Row,
	rows=>[\%person, \%thing];

=cut
sub TIEHASH {
    carp &whowasi if $DEBUG;
    my $class = shift;
    my %args = (
	rows=>undef,
	@_
    );
    my @rows = @{$args{rows}};

    my $self = {};
    $self->{ROWS} = \@rows;
    $self->{FIELDS} = {};
    $self->{ROW_KEYS} = [];
    my $i=0;
    foreach my $row_ref (@{$self->{ROWS}})
    {
	$self->{ROW_KEYS}->[$i] = {};
	foreach my $key (keys %{$row_ref})
	{
	    $self->{FIELDS}->{$key} = 1;
	    $self->{ROW_KEYS}->[$i]->{$key} = 1;
	}
	$i++;
    }

    bless $self, $class;
} # TIEHASH

=head2 FETCH

Get a key=>value from the hash

    $val = $hash{$key}
    $val = $hash{{$key=>0}}; # 0th element of $key field
    $val = $hash{[$key,2]}; # 3rd element of $key field
    $val = $hash{{$key=>undef}}; # whole key field as array ref

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

    for (my $i=0; $i < @{$self->{ROWS}}; $i++)
    {
	if (exists $self->{ROW_KEYS}->[$i]->{$key})
	{
	    return $self->{ROWS}->[$i]->{$match};
	}
    }
    return undef;

} # FETCH

=head2 STORE

Add a key=>value to the hash

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
    my $found = 0;
    for (my $i=0; $i < @{$self->{ROWS}}; $i++)
    {
	if (exists $self->{ROW_KEYS}->[$i]->{$key})
	{
	    $self->{ROWS}->[$i]->{$match} = $val;
	    $found = 1;
	}
    }
    if (!$found)
    {
	croak "invalid key [$key] in hash\n";
    }

} # STORE

=head2 DELETE

Remove a key=>value from the hash

=cut
sub DELETE {
    carp &whowasi if $DEBUG;
    my ($self, $key) = @_;

    my $retval = undef;
    for (my $i=0; $i < @{$self->{ROWS}}; $i++)
    {
	if (exists $self->{ROW_KEYS}->[$i]->{$key})
	{
	    $retval = delete $self->{ROWS}->[$i]->{$key};
	}
    }
    return $retval;
} # DELETE

=head2 CLEAR

Remove all the data from the hash.

=cut
sub CLEAR {
    carp &whowasi if $DEBUG;
    my $self = shift;

    foreach my $row_ref (@{$self->{ROWS}})
    {
	my $row_obj = tied %{$row_ref};
	$row_obj->CLEAR();
    }
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

sub UNTIE {
    carp &whowasi if $DEBUG;
    my $self = shift;

    $self->{ROWS} = [];
    $self->{ROW_KEYS} = [];
    $self->{FIELDS} = {};
}

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

=head2 is_matched

    is_matched($str,$re)

Check if the string matches

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
	elsif ($op eq '<' ) { $retval = ($str <  $val); }
	elsif ($op eq '>' ) { $retval = ($str >  $val); }
	elsif ($op eq '==') { $retval = ($str == $val); }
	elsif ($op eq '!=') { $retval = ($str != $val); }
	elsif ($op eq '<=') { $retval = ($str <= $val); }
	elsif ($op eq '>=') { $retval = ($str >= $val); }
	elsif ($op eq 'lt') { $retval = ($str lt $val); }
	elsif ($op eq 'gt') { $retval = ($str gt $val); }
	elsif ($op eq 'eq') { $retval = ($str eq $val); }
	elsif ($op eq 'ne') { $retval = ($str ne $val); }
	elsif ($op eq 'le') { $retval = ($str le $val); }
	elsif ($op eq 'ge') { $retval = ($str ge $val); }

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
L<Tie::FieldVals::Join>

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

1; # End of Tie::FieldVals::Join::Row
__END__
