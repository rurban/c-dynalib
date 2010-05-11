#!/usr/bin/perl
use strict;
# See https://rt.cpan.org/Public/Bug/Display.html?id=57341
use GCC::TranslationUnit;
use Getopt::Long;

my ($cc, $inc, $code, $file, $type);
GetOptions( "cc=s" 		=> \$cc,
	    "I=s" 		=> \$inc,
	    "code=s" 		=> \$code,
	    "file=s",		=> \$file,
	    "t=s" 		=> \$type );
$inc = "-I$inc" if $inc;

if ($type) {
  my %FFIs = map { $_ => 1 } qw( C::DynaLib FFI Win32::API P5NCI Ctypes );
  die "Error: Unknown -t $type. Valid: ".join(", ",keys(%FFIs)) ."\n"
    unless $FFIs{$type};
}

my @post;
my %records;
my $filter;

my $header = shift;
# .h or .hpp or .hh
$header .= ".h" if !$file and !$code and $header and $header !~ /\.h/;
if ($header and $header =~ /\.h(h|pp)$/ and !$cc) {
  # for c++ support with newer g++ see
  # https://rt.cpan.org/Public/Bug/Display.html?id=57349 (v1.01)
  $cc = "g++";
}
$cc = 'gcc' unless $cc; # check Config?
# use File::Temp instead?
my $tmp = $header || "tmp.c"; $tmp =~ s/\.h$/.c/; $tmp .= ".c" unless $tmp =~ /\.c$/;
open F, ">", $tmp;
if ($code) {
  print F "$code\n";
  $filter = $header;
} elsif ($file) {
  print F "#include \"$file\"\n";
  $filter = $header;
} else {
  $header = "stdlib.h" unless $header;
  print F "#include <$header>\n";
  $filter = shift;
}
close F;

# gcc4 or g++4
system "$cc $inc -fdump-translation-unit -c $tmp";
my @tu = glob "$tmp.*.tu" or die;

# XXX resolve non-basic types, only integer, real, pointer, record.
# boolean?
# on records and pointers we might need to create handy accessors per FFI.
sub type_name {
  my $type = shift;
  print $type->qual ? $type->qual." " : "";
  if ($type->name and $type->name->can('name')) {
    return $type->name->name->identifier;
  } elsif (ref $type eq 'GCC::Node::pointer_type') {
    my $node = $type->type;
    if ($node->isa('GCC::Node::record_type')) {
      my $struct = ref($node->name) =~ /type_decl/
	? $node->name->name->identifier : $node->name->identifier;
      # mark struct $name to be dumped later, with decl and fields
      push @post, $node unless $records{$struct};
      # prevent from recursive declarations
      $records{$struct}++;
      return $node->code . " $struct " . $type->thingy . type_name($node);
    }
    return $type->thingy . type_name($node);
  } else {
    ''
  };
}

my $root;
my $tu = pop @tu;
my $node = $root = GCC::TranslationUnit::Parser->parsefile($tu)->root;
END { unlink $tu, $tmp; };
#print "Parse GCC::TranslationUnit function signatures for $header $filter\n";
while ($node) {
  if ($node->isa('GCC::Node::function_decl')
      and ($filter ? $node->name->identifier =~ /$filter/
	           : $node->name->identifier !~ /^_/))
  {
    my $func = $node->name->identifier;
    printf "\n%s\n", $func;
    my $type = $node->type;
    # type => function_type    size: @12      algn: 8        retn: @85  prms: @185
    print  "  return=";
    print type_name($type->retn);
    print "\n";
    if ($type->parms) {
      my $parm = $type->parms;
      print  "  parms=";
      while ($parm) {
	print type_name($parm->value);
      } continue {
	$parm = $parm->chain;
	print ", " if $parm;
      }
      print "\n";
    }
    #printf "  size=%s\n", $type->size->type->name->identifier; bit_size_type
    printf "  align=%s, return-align=%d\n",
      $type->align, $type->retn->align;
  }
  if ($node->isa('GCC::Node::record_type')
      and ($filter ? $node->name->identifier =~ /$filter/
	           : $node->name->identifier !~ /^_/))
  {
    printf "\nstruct %s\n", type_name($node);
    # XXX struct decl and fields
  }
} continue {
  $node = $node->chain;
}

POST:
while ($node = shift @post) {
  #print "\n(", ref $node, ")";
  if ($node->isa('GCC::Node::record_type')) {
    my $struct = sprintf
      ("%s %s",
       $node->code,
       (ref($node->name) =~ /type_decl/)
         ? $node->name->name->identifier
         : $node->name->identifier
      );
    printf "\n%s ", $struct;
    printf " (align=%s)\n",  $node->align;
    printf "  {\n";
    my $node = $node->fields;
    while ($node) {
      # field_decl
      print "    ",type_name($node->type)," ",$node->name->identifier;
      printf " (align=%s)\n", $node->align;
    } continue {
      $node = $node->chain;
    }
    printf "  }\n";
  }
}

__END__

=pod

=head1 NAME

hparse

=head1 DESCRIPTION

Parse function signatures for FFI from gcc4 -fdump-translation-unit

Also parses record types (union, struct) if used as arguments
of the used functions.

Note that the output should be compiler independent. So you CAN use
gcc for creating FFI signatures for shared libraries compiled with
other compilers. Theoretically.

=head1 SYNOPSIS

  hparse.pl [OPTIONS] [header] [function-regex]

  hparse.pl stdio.h '^fprintf$'

  hparse.pl --code "int __cdecl ioctl (int __fd, int __cmd, ...)"

=head1 OPTIONS

  -t  FFI-TYPE  - dump in the given FFI format (todo)

  --cc gcc      - use given gcc
  -I            - use given include path

  --code string - parse string, not any header
  --file file   - parse file, not any header

=head2 FFI-TYPES (todo)

  * C::DynaLib
  * FFI
  * Win32::API
  * P5NCI
  * Ctypes

=head1 EXAMPLES

=head2 hparse.pl stdio.h '^fr'

frexp
  return=double
  parms=double, *int, void
  align=8, return-align=64

frexpf
  return=float
  parms=float, *int, void
  align=8, return-align=32

frexpl
  return=long double
  parms=long double, *int, void
  align=8, return-align=32

free
  return=void
  parms=*void, void
  align=8, return-align=8

freopen
  return=*FILE
  parms=const *char, const *char, *FILE, void
  align=8, return-align=32

fread
  return=size_t
  parms=*void, size_t, size_t, *FILE, void
  align=8, return-align=32

=head2 hparse.pl poll.h 'poll'

poll
  return=int
  parms=struct pollfd *, nfds_t, int, void
  align=8, return-align=32

struct pollfd  (align=32)
  {
    int fd (align=32)
    short int events (align=16)
    short int revents (align=16)
  }

=head1 TODO

Resolve size_t, nfds_t => integer_type

Calling convention _stdcall, _cdecl, _fastcall

Align syntax for the FFI's?

Varargs ... not detected

  ./hparse.pl --code "int __cdecl ioctl (int __fd, int __cmd, ...);" ioctl

  ioctl
    return=int
    parms=int, int
    align=8, return-align=32


=cut
