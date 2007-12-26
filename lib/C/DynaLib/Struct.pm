package C::DynaLib::Struct;
require 5.002;

=head1 NAME

C::DynaLib::Struct - Tool for handling the C `struct' data type

=head1 SYNOPSIS

  use C::DynaLib::Struct;

  Define C::DynaLib::Struct(
	$struct_tag,
	$template0, \@field_names0,
	[$template1, \@field_names1,]
	... );

  $rstruct = tie( $struct, $struct_tag [, @initializer_list] );
  $value = $rstruct->my_field();
  $rstruct->my_field( $new_value );

  $pointer_to_struct = pack( 'p', $struct );
  $struct = $new_struct;  # assigns all fields at once

  # after passing pointer-to-struct to a C function:
  $rstruct->Unpack();
  $returned_value = $rstruct->my_field();

=head1 DESCRIPTION

When mixing Perl and C, the conversion of data types can be rather
tedious and error-prone.  This module provides an abstraction from
Perl's C<pack> and C<unpack> operators for using structures whose
member data types and positions do not change.

Here are some examples of C code that deals with a C<struct>.  On the
right are some possible Perl equivalents.

    C				Perl
    -				----
    typedef struct {		use C::DynaLib::Struct;
	int	m_int;		Define C::DynaLib::Struct(
	double	m_double;	    'Foo',
	char *	m_string;	    'i' => ['m_int'],
    } Foo;			    'd' => ['m_double'],
				    'p' => ['m_string'] );
				# or, equivalently,
				Define C::DynaLib::Struct('Foo',
				    'idp', [qw(m_int m_double m_string)]);

    Foo foo;
    Foo *pfoo = &foo;		$rfoo = tie ($foo, 'Foo');

    i = pfoo->m_int;		$i = $rfoo->m_int;

    d = foo.m_double;		$d = (tied $foo)->m_double;

    pfoo->m_string = "hi";	$rfoo->m_string("hi");

    Foo bar;			tie ($bar, 'Foo');
    bar = foo;			$bar = $foo;

    void do_foo(Foo *arg);	use C::DynaLib;
				$lib = new C::DynaLib("-lfoo");
				$do_foo = $lib->DeclareSub("do_foo","","P");
				# or you could write an XSUB.

    do_foo(&foo);		&$do_foo($foo);

    returned_i = foo.m_int;	$rfoo->Unpack();
				$returned_i = $rfoo->m_int;

=head1 FUNCTIONS

=head2 Define ( $new_class )

=head1 BUGS

Data member access is through autoloaded methods, so actual existing
methods are not allowed as structure member names.  Currently, the
illegal names are AUTOLOAD, TIESCALAR, FETCH, STORE, and Unpack.

The names of Structs themselves must be allowable package names.
Using an existing package name will cause problems.

C<struct>s mean different things to different C compilers on different
machines.  Use caution when assigning C<pack> codes to C data types.

=head1 SEE ALSO

perlfunc(1) (for C<pack>), perlref(1), perltie(1).

=cut


use strict qw (vars subs);
use vars qw($VERSION);
$VERSION = '0.56';

package C::DynaLib::Struct::Imp;

use Carp;
use vars qw (@ISA $AUTOLOAD);

# Keep subs to a minimum, since they pollute the struct member namespace.
use subs qw (AUTOLOAD TIESCALAR FETCH STORE Unpack);

#
# Class variable: $template
#     holds the template used to pack and unpack struct members
# Class variable: %fieldno
#     maps field (member) names to their indexes in @{$self->[1]}
#
# Either or both of the following two may be defined at a given time.
# One can be obtained from the other by means of pack/unpack.
#
# Instance variable: $self->[0]
#     holds the packed struct value
# Instance variable: @{$self->[1]}
#     list of unpacked struct member values
#

sub TIESCALAR {
    my ($class, @member) = @_;
    defined (${"${class}::template"})
	or croak "Class \"$class\" has not been defined as a Struct";
    bless [ undef, \@member ], $class;
}

sub AUTOLOAD {
    my $self = shift;
    my $class = ref ($self);
    (my $member = $AUTOLOAD) =~ s/.*:://;
    my $template = ${"${class}::template"};
    defined ($template)
	or croak "Class \"$class\" has not been defined as a Struct";
    my $index = ${"${class}::fieldno"}{$member};
    unless (defined ($index)) {
	carp "Struct \"$class\" has no member \"$member\""
	    unless $member eq 'DESTROY';
	return undef;
    }
    $self->[1] ||= [ unpack ($template, $self->[0]) ];
    if (@_ == 0) {
	return $self->[1]->[$index];
    } elsif (@_ == 1) {
	undef $self->[0];
	return $self->[1]->[$index] = $_[0];
    } else {
	croak "Usage: \$structref->$member( [\$new_value] )";
    }
}

sub FETCH {
    return $_[0]->[0] if defined ($_[0]->[0]);
    return $_[0]->[0] = pack (${ref ($_[0]) . "::template"}, @{$_[0]->[1]});
}

sub STORE {
    undef $_[0]->[1];
    $_[0]->[0] = $_[1];
}

sub Unpack {
    $_[0]->[1] = [ unpack (${ref ($_[0]) . "::template"}, $_[0]->[0]) ]
	if defined ($_[0]->[0]);
    return @{$_[0]->[1]} if wantarray;
}

package C::DynaLib::Struct;

use Carp;
use subs qw (Define);

sub Define {
    my ($class, $new_class) = splice(@_, 0, 2);
    if (defined (${"${new_class}::template"})) {
	carp "Redefinition of Struct $new_class";
    }
    *{"${new_class}::TIESCALAR"} = \&C::DynaLib::Struct::Imp::TIESCALAR;
    *{"${new_class}::AUTOLOAD"} = \&C::DynaLib::Struct::Imp::AUTOLOAD;
    @{"${new_class}::ISA"} = qw (C::DynaLib::Struct::Imp);
    my ($template, %fieldno) = ("");
    my ($index, $template_fragment, $fields) = (0);
    while (1) {
	($template_fragment, $fields) = splice(@_, 0, 2);
	last unless defined ($template_fragment);
	ref ($fields) eq 'ARRAY'
	    or die 'Usage: Define C::DynaLib::Struct( $struct_name, $template, \@field_names )';
	$template .= $template_fragment;
	my $i;
	for $i (0 .. $#$fields) {
	    defined (&{"C::DynaLib::Struct::Imp::$fields->[$i]"})
		and croak "Illegal Struct member name: \"$fields->[$i]\"";
	    $fieldno{$fields->[$i]} = $index;
	    ++ $index;
	}
    }
    *{"${new_class}::fieldno"} = \%fieldno;
    *{"${new_class}::template"} = \$template;
}

1;
__END__
