package Tie::FieldVals;
use strict;
use warnings;

=head1 NAME

Tie::FieldVals - an array tie for a file of enhanced Field:Value data

=head1 VERSION

This describes version B<0.10> of Tie::FieldVals.

=cut

our $VERSION = '0.10';

=head1 SYNOPSIS

    use Tie::FieldVals;
    use Tie::FieldVals::Row;

    # tie the array
    my @records;
    my $recs_obj = tie @records, 'Tie::FieldVals', datafile=>$datafile;

    # object methods
    my @field_names = $recs_obj->field_names();

=head1 DESCRIPTION

This is a Tie object to map the records in an enhanced Field:Value data
file into an array.  Each file has multiple records, each record has its
values defined by a Field:Value pair, with the enhancements that (a) the
Value part can extend over more than one line (because the Field names
are predefined) and (b) Fields can have multiple values by repeating
the Field:Value part for a given field.

Because of its use of the Tie::File module, access to each record is
reasonably fast.

The advantage of this setup is that one can have useful data files which
are plain text, human readable, human editable, and at the same time able
to be accessed faster than using XML (I know, I wrote a version of my
reporting software using XML data, and even the fastest XML parsers weren't
as fast as this setup, once there were a reasonable number of records).
This also has advantages over a simpler setup where values are given one
per line with no indication of what value belongs to what field; the
problems with that is that it is harder to fix corrupted data by hand, and
it is harder to add new fields, and one can't have multi-line data.

It is likewise better than a CSV (Comma-Separated Values) file, because
again, with a CSV file, the data is positional and therefore harder to fix
and harder to change, and again one can't have multi-line data.

This module is both better and worse than file-oriented databases like
L<DB_File> and its variants and extensions (such as L<MLDBM>).  This module
does not require that each record have a unique key, and the fact that a
DBM file is binary makes it not only less correctable, but also less
portable.  On the downside, this module isn't as fast.

Naturally, if one's data needs are more complex, it is probably better to
use a fully-fledged database; this is oriented towards those who don't wish
to have the overhead of setting up and maintaining a relational database
server, and wish to use something more straightforward.

This comes bundled with other support modules, such as the
Tie::FieldVals::Row module.  The Tie::FieldVals::Select module is for
selecting and sorting a sub-set from a Tie::FieldVals array, and the
Tie::FieldVals::Join is a very simple method of joining two files on a
common field.

This distribution includes the fv2xml script, which converts a
Tie::FieldVals data file into an XML file, and xml2fv which
converts an XML file into a Tie::FieldVals data file.

=head1 FILE FORMAT

The data file is in the form of Field:Value pairs, with each
record separated by a line with '=' on it. The first record
is an "empty" record, which just contains the field names;
this lets us know what the legal fields are.
A line which doesn't start with a recognised field is
considered to be part of the value of the most recent Field.

=head2 Example 1

    Name:
    Entry:
    =
    Name:fanzine
    Entry:Fanzines are amateur magazines produced by fans.
    =
    Name:fan fiction (fanfic)
    Entry:Original fiction written by fans of a particular
    TV Show/Movie set in the universe depicted by that work.
    =

The first record just contains Name: and Entry: fields to show that those
are the legal fields for this file.  The third record gives an example
of a value that goes over more than one line.

=head2 Example 2

    Author:
    AuthorEmail:
    AuthorURL:
    AuthorURLName:
    =
    Author:Adele
    AuthorEmail:adele@example.com
    AuthorEmail:adele@example.tas.edu
    AuthorURL:
    AuthorURLName:
    =
    Author:Danzer,Brenda
    AuthorEmail:
    AuthorURL:http://www.example.com/~danzer
    AuthorURLName:Danzer Dancing
    AuthorURL:http://www.brendance.com/
    AuthorURLName:BrenDance
    =

This one gives examples of multi-valued fields.

=head2 Gotchas

Field names cannot have spaces in them, indeed, they must
consist of plain alphanumeric characters or underscores.
They are case-sensitive.

The record separator (=) must be on a line by itself, and the last record
in the file must also have a record-separator after it.

=cut

use 5.006;
use strict;
use Carp;
use Tie::Array;
use Tie::File;
use Tie::FieldVals::Row;
use Fcntl qw(:DEFAULT);
use Data::Dumper;

our @ISA = qw(Tie::Array);

# to make taint happy
$ENV{PATH} = "/bin:/usr/bin:/usr/local/bin";
$ENV{CDPATH} = '';
$ENV{BASH_ENV} = '';

# for debugging
my $DEBUG = 0;

=head1 OBJECT METHODS

=head2 field_names

Get the field names of this data.

my @field_names = $recs_obj->field_names();

=cut
sub field_names {
    carp &whowasi if $DEBUG;
    my $self = shift;

    @{$self->{field_names}};
}

=head1 TIE-ARRAY METHODS

=head2 TIEARRAY

Create a new instance of the object as tied to an array.

    tie @people, 'Tie::FieldVals', datafile=>$datafile;

    tie @people, 'Tie::FieldVals', datafile=>$datafile,
	mode=>O_RDONLY, cache_size=>1000, memory=>0;

    tie @people, 'Tie::FieldVals', datafile=>$datafile,
	mode=>O_RDWR, cache_all=>1;

Arguments:

=over

=item datafile

The file with the data in it. (required)

=item mode

The mode to open the file with. O_RDONLY means that the file is read-only.
(default: O_RDWR (read-write))

=item cache_all

If true, cache all the records in the file.  This will speed things up,
but consume more memory. (default: false)

=item cache_size

The size of the cache (if we aren't caching all the records).
(default: 100)  As ever, there is a trade-off between space and time.

=item memory

The upper limit on the memory consumed by L<Tie::File>.
(default: 10,000,000)

Note that there are two caches: the cache of unparsed records maintained
by Tie::File, and the cache of parsed records maintained by Tie::FieldVals.
The B<memory> option affects the Tie::File cache, and the B<cache_*>
options affect the Tie::FieldVals cache.

=back

=cut
sub TIEARRAY {
    carp &whowasi if $DEBUG;
    my $class = shift;
    my %args = (
	datafile=>'',
	mode=>(O_RDONLY),
	cache_size=>100,
	cache_all=>0,
	memory=>10_000_000,
	@_
    );

    my $self = {};

    my @records;
    $self->{FILE_OBJ} = tie @records, 'Tie::File', "$args{datafile}",
	recsep =>"\n=\n", mode=>$args{mode}, memory=>$args{memory}
	or die "Tie::FieldVals - Could not open", $args{datafile}, ".";
    $self->{FILE_RECS} = \@records;
    $self->{OPTIONS} = \%args;

    get_field_names($self);
    $self->{REC_CACHE} = {};
    my $count = @records;
    if ($args{cache_all}) # set the cache to the size of the file
    {
	$self->{OPTIONS}->{cache_size} = $count;
    }

    bless $self, $class;
} # TIEARRAY

=head2 FETCH

Get a row from the array.

    $val = $array[$ind];

Returns a reference to a Tie::FieldVals::Row hash, or undef.

=cut
sub FETCH {
    carp &whowasi if $DEBUG;
    my ($self, $ind) = @_;

    if (defined $self->{REC_CACHE}->{$ind})
    {
	return $self->{REC_CACHE}->{$ind};
    }
    else # not cached, add to cache
    {
	# remove one from cache if cache full
	my @cached = keys %{$self->{REC_CACHE}};
	if (@cached >= $self->{OPTIONS}->{cache_size})
	{
	    delete $self->{REC_CACHE}->{shift @cached};
	}
	%{$self->{REC_CACHE}->{$ind}} = ();
	my $row_obj = tie %{$self->{REC_CACHE}->{$ind}},
	    'Tie::FieldVals::Row', fields=>$self->{field_names};
	# remember, the 0 record is the empty fields record
	my $rec_str = $self->{FILE_RECS}->[$ind + 1];
	if (defined $rec_str)
	{
	    $row_obj->set_from_string($rec_str);
	    return $self->{REC_CACHE}->{$ind};
	}
	else
	{
	    delete $self->{REC_CACHE}->{$ind};
	    return undef;
	}
    }
    return undef;
} # FETCH

=head2 STORE

Add a value to the array.  Value must be a Tie::FieldVals::Row hash.

    $array[$ind] = $val;

If $ind is bigger than the array, then just push, don't extend.

=cut
sub STORE {
    carp &whowasi if $DEBUG;
    my ($self, $ind, $val) = @_;

    # only store a hash and if writing
    if (ref $val eq 'HASH'
	&& $self->{OPTIONS}->{mode} & O_RDWR)
    {
	if ($ind > $self->FETCHSIZE())
	{
	    $ind = $self->FETCHSIZE();
	    $self->{REC_CACHE}->{$ind} = $val;
	    my $row_obj = tied %{$val};
	    my $rec_str = $row_obj->get_as_string();
	    $self->{FILE_OBJ}->PUSH($rec_str);
	}
	else
	{
	    $self->{REC_CACHE}->{$ind} = $val;
	    my $row_obj = tied %{$val};
	    my $rec_str = $row_obj->get_as_string();
	    # remember record 0 is the empty fields record
	    $self->{FILE_OBJ}->STORE($ind + 1, $rec_str);
	}
    }
} # STORE

=head2 FETCHSIZE

Get the size of the array.

=cut
sub FETCHSIZE {
    carp &whowasi if $DEBUG;
    my $self = shift;

    # remember record 0 is the empty fields record
    return ($self->{FILE_OBJ}->FETCHSIZE() - 1);
} # FETCHSIZE

=head2 STORESIZE

Set the size of the array, if the file is writeable.

=cut
sub STORESIZE {
    carp &whowasi if $DEBUG;
    my $self = shift;
    my $count = shift;

    if ($self->{OPTIONS}->{mode} & O_RDWR)
    {
	# remember record 0 is the empty fields record
	$self->{FILE_OBJ}->STORESIZE($count + 1);
    }
} # STORESIZE

=head2 EXISTS

    exists $array[$ind];

=cut
sub EXISTS {
    carp &whowasi if $DEBUG;
    my $self = shift;
    my $ind = shift;

    # remember record 0 is the empty fields record
    return $self->{FILE_OBJ}->EXISTS($ind + 1);
} # EXISTS

=head2 DELETE

    delete $array[$ind];

Delete the value at $ind if the file is writeable.

=cut
sub DELETE {
    carp &whowasi if $DEBUG;
    my $self = shift;
    my $ind = shift;

    if ($self->{OPTIONS}->{mode} & O_RDWR)
    {
	if (exists $self->{REC_CACHE}->{$ind})
	{
	    delete $self->{REC_CACHE}->{$ind};
	}
	# remember record 0 is the empty fields record
	$self->{FILE_OBJ}->DELETE($ind + 1);
    }
} # DELETE

=head2 CLEAR

    @array = ();

Clear the array if the file is writeable.

=cut
sub CLEAR {
    carp &whowasi if $DEBUG;
    my $self = shift;
    my $ind = shift;

    if ($self->{OPTIONS}->{mode} & O_RDWR)
    {
	$self->{REC_CACHE} = {};
	# remember record 0 is the empty fields record
	my $rec_str = $self->{FILE_RECS}->[0];
	$self->{FILE_OBJ}->CLEAR();
	$self->{FILE_RECS}->[0] = $rec_str;
    }
} # CLEAR

=head2 UNTIE

    untie @array;

Untie the array.

=cut
sub UNTIE {
    carp &whowasi if $DEBUG;
    my $self = shift;
    my $ind = shift;

    $self->{REC_CACHE} = {};
    untie @{$self->{FILE_RECS}};
} # UNTIE

=head1 PRIVATE METHODS

This documentation is for developer reference only.

=head2 debug

Set debugging on.

=cut
sub debug { $DEBUG = @_ ? shift : 1 }

=head2 whowasi

For debugging: say who called this 

=cut
sub whowasi { (caller(1))[3] . '()' }

=head2 get_field_names($self, $datafile)

Read the field-name information from the file,
and set $self to have that info

=cut
sub get_field_names ($$) {
    my $self = shift;
    my $datafile = shift;
    my @field_names;

    # the field info is in the first record
    my %row = ();
    my $row_obj = tie %row,
    'Tie::FieldVals::Row', fields=>['dummy'];
    my $rec_str = $self->{FILE_RECS}->[0];
    if (defined $rec_str)
    {
	$row_obj->set_from_string($rec_str,
	    override_keys=>1);
	@{$self->{field_names}} = @{$row_obj->field_names()};
    }

    @{$self->{field_names}};

} # get_field_names

=head2 get_xml_field_names($self, $datafile)

Read the field-name information from the file,
and set $self to have that info

=cut
sub get_xml_field_names ($$) {
    my $self = shift;
    my $datafile = shift;
    my @field_names;

    {
	local $/ = '</fields>';
	# Open the file
	open(DEEP, $datafile) || die "Can't open ", $datafile, ": $!\n";

	# read in the fields info first
	my $fields_str = <DEEP>;
	parse_fields($self, $fields_str);
	close(DEEP);
    }

    @{$self->{field_names}};

} # get_xml_field_names

=head2 parse_fields

parse the fields part of the data

=cut
sub parse_fields ($$) {
    my $self = shift;
    my $fields_str = shift;

    # fields_str should contain <gra_data><fields>...</fields>
    # or just the fields
    if ($fields_str =~ m#<fields>(.*)</fields>#s)
    {
	$fields_str = $1;
    }
    # now fields_str should just contain the fields
    # eg <Author/>...<Review htmlize="yes"/>
    while ($fields_str =~ m#<([a-zA-Z][^>]*)/>#sg)
    {
	my $full_field = $1;
	if ($full_field =~ m#([a-zA-Z][-_a-zA-Z0-9]*)\s([^>]*)#sg)
	{
	    my $field = $1;
	    my $attr_str = $2;
	    push @{$self->{field_names}}, $field;
	    $self->{fields}->{$field} = 1;
	}
	elsif ($full_field =~ m/^([a-zA-Z][-_a-zA-Z0-9]*)$/sg)
	{
	    my $field = $1;
	    push @{$self->{field_names}}, $field;
	    $self->{fields}->{$field} = 1;
	}
    }
}

=head1 REQUIRES

    Test::More

    Carp
    Tie::Array
    Tie::File
    Fcntl
    Data::Dumper

    Getopt::Long
    Pod::Usage
    Getopt::ArgvFile

=head1 INSTALLATION

To install this module, run the following commands:

    perl Build.PL
    ./Build
    ./Build test
    ./Build install

Or, if you're on a platform (like DOS or Windows) that doesn't like the
"./" notation, you can do this:

   perl Build.PL
   perl Build
   perl Build test
   perl Build install

In order to install somewhere other than the default, such as
in a directory under your home directory, like "/home/fred/perl"
go

   perl Build.PL --install_base /home/fred/perl

as the first step instead.

This will install the files underneath /home/fred/perl.

You will then need to make sure that you alter the PERL5LIB variable to
find the modules, and the PATH variable to find the script.

Therefore you will need to change:
your path, to include /home/fred/perl/script (where the script will be)

	PATH=/home/fred/perl/script:${PATH}

the PERL5LIB variable to add /home/fred/perl/lib

	PERL5LIB=/home/fred/perl/lib:${PERL5LIB}


=head1 SEE ALSO

perl(1).
L<Tie::FieldVals::Row>
L<Tie::FieldVals::Select>
L<Tie::FieldVals::Join>
L<Tie::FieldVals::Join::Row>

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

1; # End of Tie::FieldVals
# vim: ts=8 sts=4 sw=4
__END__
