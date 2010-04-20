use ExtUtils::MakeMaker;

use strict;
require 5.002;
use Config;

my($archname, @convention, $convention,
   $num_callbacks, %cflags, $object, $devnull,
   $conv_xs, $cbfunc_c, $cdecl_h, $postamble,
   $is_gcc, $is_borland, $is_dynamic, $Verbose);

# $Verbose = 1;
$conv_xs = "conv.xsi";
$cbfunc_c = "cbfunc.c";
$cdecl_h = "cdecl.h";
$object = '$(BASEEXT)$(OBJ_EXT)';

$is_gcc = $Config{cc} =~ /gcc/i && $Config{gccversion} >= 2;
$is_borland = $Config{cc} =~ /\bbcc/i;
$is_dynamic = ($Config{usedl} eq 'define');
use subs qw(write_conv write_cbfunc write_cdecl_h is_big_endian check_ieee_fp);

$postamble = "
clean::
	\$(RM_F) $conv_xs $cbfunc_c *.core *.stackdump

$conv_xs: $0 \$(CONFIGDEP)

$cbfunc_c: $0 \$(CONFIGDEP)

DynaLib.c: $conv_xs
";


$is_dynamic or warn <<STATIC;

*** NOTE
*** According to $INC{"Config.pm"},
*** this perl does not know how to use dynamic loading.  The test
*** program for this module will fail, and you will not be able to
*** invoke functions in dynamic libraries.  If you need this feature,
*** you have to rebuild perl.  Choose "y" when Configure asks, "Do
*** you wish to use dynamic loading?".

STATIC


@convention = ();
%cflags = ();
for (@ARGV) {
    /^DECL=(.*)$/ and push @convention, split(",", $1);
    /^CALLBACKS=(\d+)$/ and $num_callbacks = $1;
    /^(-D.*)(?:\=(.*))?$/ and $cflags{$1} = $2;
    /^Verbose$/i and $Verbose = 1;
}

# Appease MakeMaker:
@ARGV = grep { !/^(DECL=|CALLBACKS=(\d+)$|-D.)/ } @ARGV;

$archname = $Config{archname};
# TODO: support for the ia64 fastcall derivate (first four in regs, rest in args)
# -fstack-protector adds 32 bytes. $CDECL_ADJUST = -32
unless (@convention) {
    for (
	 #[ '^i?[x3-6]86', sub {'cdecl'} ],
	 [ '^sun4-', sub {'sparc'} ],
	 [ 'sparc', sub {'sparc'} ],
	 [ '(alpha|axp)', sub {
			unless ($is_gcc) {
			  $postamble .= "\nalpha-cc\$(OBJ_EXT): alpha-cc.s\n"
			    . "\t\$(CC) -c alpha-cc.s -o \$\@\n"
			    . "\n#alpha-cc.s: alpha-cc.c\n"
			    . "#\tgcc -O2 -S alpha-cc.c -o \$\@\n";
			  $object .= " alpha-cc.o";
			}
			'alpha'} ],
	 #[ 'win32', sub {'cdecl'} ],
	 # [ '^cygwin-thread-multi-64int', sub {my $CDECL_ADJUST = -32; 'cdecl'} ],
	 [ '', sub { () } ],
	 )
    { @convention = &{$_->[1]}, last if $archname =~ /$_->[0]/i }
}

# Disable cc optimization on non-gcc compilers
my $optimize = $Config{optimize};
if ($^O eq 'MSWin32' and $Config{cc} =~ /^cl/i) {
    $optimize = '/Od';
} elsif ($Config{optimize} =~ /[\-\/]O\w/)  {
    $optimize =~ s/O\w/O0/;
}
if ($Config{cc} eq 'gcc' and $Config{ccflags} =~ /-DDEBUGGING/) {
    $optimize .= " -g";
}

WriteMakefile(
    'NAME'	=> 'C::DynaLib',
    'VERSION_FROM' => 'lib/C/DynaLib.pm',
    'DEFINE'	=> '',
    'OBJECT'	=> $object,

    # Don't let MakeMaker set up a dependency loop.
    # cdecl.h depends on testcall.o, not the other way around!
    'H'         => [],
    'C'         => ['DynaLib.c'],
    'INC'	=> '-I.',
    'OPTIMIZE'	=> $optimize,

    'PREREQ_PM' => {
        'Convert::Binary::C' => 0.70,
        #'GCC::TranslationUnit' => 0,
        'Test'       => 0,
        'Test::Simple' => 0,
        'Test::More' => 0,
    },
    ($] >= 5.005 ?
     ('AUTHOR' => 'John Tobey <John.Tobey@gmail.com>, Reini Urban <rurban@cpan.org>',
      'ABSTRACT_FROM' => 'lib/C/DynaLib.pm') : ()),
);


sub is_big_endian
{
    my $byteorder = $Config{byteorder}
      || unpack( "a*", pack "L", 0x34333231 );
    die "Native byte order ($byteorder) not supported!\n"
      if   $byteorder ne '1234'     and $byteorder ne '4321'
	and $byteorder ne '12345678' and $byteorder ne '87654321';
    $byteorder eq '4321' or $byteorder eq '87654321';
}

sub check_ieee_fp
{
  my @test = (
    {
      value  => '-1.0',
      double => pack( 'C*', 0xBF, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ),
      single => pack( 'C*', 0xBF, 0x80, 0x00, 0x00 ),
    },
    {
      value  => '0.0',
      double => pack( 'C*', 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ),
      single => pack( 'C*', 0x00, 0x00, 0x00, 0x00 ),
    },
    {
      value  => '0.4',
      double => pack( 'C*', 0x3F, 0xD9, 0x99, 0x99, 0x99, 0x99, 0x99, 0x9A ),
      single => pack( 'C*', 0x3E, 0xCC, 0xCC, 0xCD ),
    },
    {
      value  => '1.0',
      double => pack( 'C*', 0x3F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ),
      single => pack( 'C*', 0x3F, 0x80, 0x00, 0x00 ),
    },
    {
      value  => '3.1415926535',
      double => pack( 'C*', 0x40, 0x09, 0x21, 0xFB, 0x54, 0x41, 0x17, 0x44 ),
      single => pack( 'C*', 0x40, 0x49, 0x0F, 0xDB ),
    },
    {
      value  => '1.220703125e-4',
      double => pack( 'C*', 0x3F, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ),
      single => pack( 'C*', 0x39, 0x00, 0x00, 0x00 ),
    },
  );

  my @fail;

  for my $t ( @test ) {
    my $s = pack 'f', $t->{value};
    my $d = pack 'd', $t->{value};
    unless( &is_big_endian ) { for( $s, $d ) { $_ = reverse $_ } }

    $s eq $t->{single} or push @fail,
        { value => $t->{value}, check => 'single', expected => $t->{single}, got => $s };

    $d eq $t->{double} or push @fail,
        { value => $t->{value}, check => 'double', expected => $t->{double}, got => $d };
  }

  return @fail;
}

sub pretest {
    my $self = shift;
    my @candidate;
    my $cleanup = sub {
	unlink ("testtest.c", "testtest.txt", "testtest$self->{EXE_EXT}",
		"testtest$self->{OBJ_EXT}");
    };
    my $cant = sub {
	&$cleanup;
	print ("I don't know how run the test program,\n",
	       "so I'll try to find a default configuration.\n")
	    if $Verbose;
	return undef;
    };
    my $try = sub {
	open HELLO, "testtest.txt" or return undef;
	my $hello = <HELLO>;
	close HELLO;
	if ($hello =~ /hello, world/) {
	    &$cleanup;
	    return 1;
	}
	return 0;
    };

    &$cleanup;
    unless (open PROG, ">testtest.c") {
	print ("Can't write testtest.c\n");
	return &$cant;
    }
    print PROG <<'PROG';
#define main notmain
#include <EXTERN.h>
#include <perl.h>
#undef main
#undef fprintf
#undef fopen
#undef fclose
#include <stdio.h>
int main()
{
    FILE *fp = fopen("testtest.txt", "w");
    if (fp == NULL) {
	return 1;
    }
    fprintf(fp, "hello, world!\n");
    fclose(fp);
    return 0;
}
PROG
    close PROG;

    my $ccflags = $Config{ccflags};
    @candidate = ();
    $devnull = $^O eq 'MSWin32' ? "> NUL" : ">/dev/null 2>&1";
    push @candidate, "$Config{cc} $Config{ccflags} -DNARF -I$self->{PERL_INC} testtest.c -o testtest$self->{EXE_EXT} $devnull"
	unless $Verbose;
    push @candidate, "$Config{cc} $Config{ccflags} -DNARF -I$self->{PERL_INC} testtest.c -otesttest$self->{EXE_EXT} $devnull"
	unless $Verbose;
    push @candidate, "$Config{cc} $Config{ccflags} -DNARF -I$self->{PERL_INC} testtest.c -o testtest$self->{EXE_EXT}";
    push @candidate, "$Config{cc} $Config{ccflags} -DNARF -I$self->{PERL_INC} testtest.c -otesttest$self->{EXE_EXT}";

    while ($self->{how_to_compile} = shift (@candidate)) {
	unlink "testtest$self->{EXE_EXT}";
	print "$self->{how_to_compile}\n" if $Verbose;
	system ($self->{how_to_compile});
	last if $? == 0 && -x "testtest$self->{EXE_EXT}";
    }
    return &$cant unless $self->{how_to_compile};

    @candidate = ();
    push @candidate, "./testtest$self->{EXE_EXT} $devnull"
	unless $Verbose;
    push @candidate, "testtest$self->{EXE_EXT} $devnull"
	unless $Verbose;
    push @candidate, "testtest$self->{EXE_EXT}";
    push @candidate, "./testtest$self->{EXE_EXT}";
    push @candidate, "run testtest$self->{EXE_EXT}";

    unlink ("testtest.txt");
    while ($self->{how_to_run} = shift (@candidate)) {
	print "$self->{how_to_run}\n" if $Verbose;
	system ($self->{how_to_run});
	$? == 0 && &$try and return 1;
    }
    return &$cant;
}

sub guess_cdecl_h {
    my $self = shift;
    open CONFIG, ">$cdecl_h" or die "can't write $cdecl_h";

    my $do_reverse = 0;
    print "Testing stack layout...\n" if $Verbose;
    $self->{how_to_compile} =~ s/testtest/testreverse/g;
    $self->{how_to_run} =~ s/testtest/testreverse/g;
    my $defines;
    for $defines ("-DINCLUDE_ALLOCA", "", "-DINCLUDE_MALLOC") {
	my $cmd = $self->{how_to_compile};
	$cmd =~ s/-DNARF/$defines/g;
	unlink ("testreverse$self->{EXE_EXT}", $cdecl_h);
	print "$cmd\n" if $Verbose;
	system ($cmd);
	if ($? == 0 && -x "testreverse$self->{EXE_EXT}") {
	    $cmd = $self->{how_to_run};
	    print "$cmd\n" if $Verbose;
	    system ($cmd);
	    if ($? == 0) {
	      $do_reverse = 0;
	    } else {
	      $do_reverse = 1;
	    }
	    print "CDECL_REVERSE = $do_reverse\n" if $Verbose;
	}
    }
    my $define_if_not = sub {
	my ($macro, $def) = @_;
	return "#ifndef $macro\n#define $macro $def\n#endif\n\n";
    };
    print CONFIG <<CONFIG;
/*
 * $cdecl_h generated by $0.  Do not edit this file, edit $0.
 */
CONFIG
    print CONFIG "#include <alloca.h>\n"
	if $self->{CC} =~ /\bcc$/;
    print CONFIG "#include <malloc.h>\n"
	if $is_borland;
    print CONFIG (&$define_if_not("CDECL_ONE_BY_ONE",
		  (($archname =~ /win32/i && ! $is_borland)
		   || $is_gcc) ? 1 : 0));
    print CONFIG (&$define_if_not("CDECL_ADJUST",
		  ($is_borland ? -12 : 0)));
    print CONFIG (&$define_if_not("CDECL_REVERSE", $do_reverse));

    close CONFIG;
}

sub make_postamble {
    my $self = shift;

    $postamble .= "\nDynaLib\$(OBJ_EXT): DynaLib.c $cbfunc_c"
      . " @{[ map { \"$_.c\" } @convention ]}\n";

    ! @convention || grep { $_ eq "cdecl" } @convention
	or return $postamble;

    print "Writing $cdecl_h\n";
    if (write_cdecl_h($self)) {
	@convention = ('cdecl')
	    unless @convention;
    } elsif (@convention) {
	print "Can't figure out this system.  I'll have to guess.\n"
	    if $Verbose;
	guess_cdecl_h($self);
    } else {
	print <<WARN;
***
*** WARNING
***
*** I can't figure out the correct way to pass arguments to a C function
*** on this system.  This may be due to porting issues, a perl installation
*** problem, or any number of things.  Maybe `perl Makefile.PL Verbose'
*** will shed some light.
***
*** I'll use the `hack30' calling convention, which may work some or most
*** of the time for integers alike. Or it may crash your programs. A better 
*** solution would be to add support for your system's calling convention.
***
*** See DynaLib.pm for a discussion of hack30.
***
WARN
	@convention = ('hack30');
	return $postamble;
    }

    $postamble .= "
clean::
	\$(RM_F) testreverse\$(EXE_EXT) testreverse\$(OBJ_EXT) testcall\$(EXE_EXT) testcall\$(OBJ_EXT) $cdecl_h

DynaLib\$(OBJ_EXT): $cdecl_h

$cdecl_h: $0 \$(CONFIGDEP) testcall\$(EXE_EXT)
	$self->{how_to_run}

testcall\$(EXE_EXT) : testcall.c
	\$(CC) `\$(PERL) -MExtUtils::Embed -e ccopts` \$(OPTIMIZE) testcall.c -o\$\@

testreverse\$(EXE_EXT) : testreverse.c
	\$(CC) `\$(PERL) -MExtUtils::Embed -e ccopts` \$(OPTIMIZE) testreverse.c -o\$\@
";
}

sub MY::postamble {
    my $self = shift;
    my $postamble = make_postamble($self);

    print "Using calling convention(s): @convention\n"
	if $Verbose;
    for (@convention) { 
      $cflags{"-DDYNALIB_DECL=\\\"$_\\\""} = undef;
      $cflags{"-DDYNALIB_USE_$_"} = undef;
    }

    print "Default calling convention: $convention[0]\n"
	if $Verbose;
    $cflags{"-DDYNALIB_DEFAULT_CONV"} = "\\\"$convention[0]\\\"";

    $num_callbacks = 4 unless defined($num_callbacks);
    print "Maximum number of callbacks: $num_callbacks\n"
	if $Verbose;
    $cflags{"-DDYNALIB_NUM_CALLBACKS"} = $num_callbacks;

    my $defines = "\nDEFINE =";
    for (sort keys %cflags) {
	$defines .= " $_";
	$defines .= "=$cflags{$_}" if defined $cflags{$_};
    }
    $postamble .= $defines;
    print "Additional definitions: $defines\n"
      if $Verbose and scalar(keys %cflags)>1;
    write_conv();
    write_cbfunc();
    parse_perl_types();

    return $postamble;
}

sub write_cdecl_h {
    my $self = shift;

    print "Testing how to compile and run a program...\n"
	if $Verbose;
    pretest($self) or return undef;

    print "Testing how to pass args to a function...\n"
	if $Verbose;
    $self->{how_to_compile} =~ s/testtest/testcall/g;
    $self->{how_to_run} =~ s/testtest/testcall/g;
    my $defines;
    for $defines ("-DINCLUDE_ALLOCA", "", "-DINCLUDE_MALLOC") {
	my $cmd = $self->{how_to_compile};
	$cmd =~ s/-DNARF/$defines/g;
	unlink ("testcall$self->{EXE_EXT}", $cdecl_h);
	print "$cmd\n" if $Verbose;
	system ($cmd);
	if ($? == 0 && -x "testcall$self->{EXE_EXT}") {
	    $cmd = $self->{how_to_run};
	    print "$cmd\n" if $Verbose;
	    system ($cmd);
	    if ($? == 0 && -e $cdecl_h) {
		append_convert_defines_cdecl($cdecl_h);
		print "Succeeded.\n" if $Verbose;
		return 1;
	    }
	}
    }
    return undef;
}

sub append_convert_defines_cdecl {
    my $cdecl_h = shift;
    open CDECL, ">>", $cdecl_h
	or die "Can't write file \"$cdecl_h\": $!\n";
    print CDECL<<CDECL_H;

typedef unsigned char uchar;
typedef char *        char_p;
typedef unsigned int  uint;
/*
typedef unsigned Quad_t  uQuad_t;
typedef long long  longlong;
*/

enum {
  TR_int,
  TR_uint,
  TR_I32,
  TR_I16,
  TR_char,
  TR_U32,
  TR_U16,
  TR_uchar,
  TR_Quad_t,
  TR_uQuad_t,
  TR_float,
  TR_double,
  TR_char_p,
  TR_longlong
};

typedef union {
  int           v_int;
  uint          v_uint;
  I32           v_I32;
  I16           v_I16;
  char          v_char;
  U32           v_U32;
  U16           v_U16;
  uchar         v_uchar;
/*
  Quad_t        v_Quad_t;
  uQuad_t       v_uQuad_t;
*/
  float         v_float;
  double        v_double;
  char_p        v_char_p;
/*
  longlong      v_longlong;
*/
} ret_stru;

CDECL_H
    close CDECL;
}

sub write_conv {

    # Write conv.xsi, to be included in DynaLib.xs

    open XS, ">$conv_xs"
	or die "Can't write file \"$conv_xs\": $!\n";
    print "Writing $conv_xs\n";

    print XS <<XS;
#
# $conv_xs generated by $0.  Don't edit this file, edit $0.
#
XS

#
# conv.xsi XS definition for the "glue" function that calls C.
#
for $convention (@convention) {
    print XS <<XS;

void
${convention}_call_packed(symref, ret_type, ...)
	void *		symref
	char *		ret_type
	PROTOTYPE: \$\$\@
	PPCODE:
	{
	  SV *sv;
#ifdef HAS_QUAD
	  Quad_t aquad;
	  unsigned Quad_t auquad;
#endif

	  if (*ret_type != '\\0') {
	    sv = sv_newmortal();
	  }
	  switch (*ret_type) {
	  case '\\0' :
	    (void) ${convention}_CALL(symref, int);
	    XSRETURN_EMPTY;
	  case 'i' :
	    sv_setiv(sv, (IV) ${convention}_CALL(symref, int));
	    break;
	  case 'l' :
	    sv_setiv(sv, (IV) ${convention}_CALL(symref, I32));
	    break;
	  case 's' :
	    sv_setiv(sv, (IV) ${convention}_CALL(symref, I16));
	    break;
	  case 'c' :
	    sv_setiv(sv, (IV) ${convention}_CALL(symref, char));
	    break;
	  case 'I' :
	    sv_setuv(sv, (UV) ${convention}_CALL(symref, uint));
	    break;
	  case 'L' :
	    sv_setuv(sv, (UV) ${convention}_CALL(symref, U32));
	    break;
	  case 'S' :
	    sv_setuv(sv, (UV) ${convention}_CALL(symref, U16));
	    break;
	  case 'C' :
	    sv_setuv(sv, (UV) ${convention}_CALL(symref, uchar));
	    break;
#ifdef HAS_QUAD
	  case 'q' :
	    aquad = ${convention}_CALL(symref, Quad_t);
	    if (aquad >= IV_MIN && aquad <= IV_MAX)
	      sv_setiv(sv, (IV)aquad);
	    else
	      sv_setnv(sv, (double)aquad);
	    break;
	  case 'Q' :
	    aquad = ${convention}_CALL(symref, uQuad_t);
	    if (aquad <= UV_MAX)
	      sv_setuv(sv, (UV)auquad);
	    else
	      sv_setnv(sv, (double)auquad);
	    break;
#endif
	  case 'f' :
            sv_setnv(sv, (double) ${convention}_CALL(symref, float));
	    break;
	  case 'd' :
	    sv_setnv(sv, ${convention}_CALL(symref, double));
	    break;
	  case 'p' :
	    sv_setpv(sv, (char *) ${convention}_CALL(symref, char_p));
	    break;
	  case 'P' :
	    sv_setpvn(sv, (unsigned char *) ${convention}_CALL(symref, char_p),
			  atoi(&ret_type[1]));
	    break;
	  default :
	    croak("Unsupported function return type: '%c'", *ret_type);
	  }
	  XPUSHs(sv);
	  XSRETURN(1);
	}
XS
}
close XS;
}

sub write_cbfunc {
    my ($i);

    # Write cbfunc.c, to be included in DynaLib.xs

    open FUNCS, ">$cbfunc_c"
	or die "Can't write file \"$cbfunc_c\": $!\n";
    print "Writing $cbfunc_c\n";

    print FUNCS <<FUNCS;
/*
 * $cbfunc_c generated by $0.  Don't edit this file, edit $0.
 */
FUNCS
    #
    # The callback functions.
    #
    for $i (0 .. $num_callbacks - 1) {
	print FUNCS <<FUNCS;

static long
#ifdef I_STDARG
_cb_func$i(void * first, ...)
#else
_cb_func$i(first, va_alist)
void * first;
va_dcl
#endif
{
  va_list ap;
  long result;

#ifdef I_STDARG
  va_start(ap,first);
#else
  va_start(ap);
#endif
  result = cb_call_sub($i, first, ap);
  va_end(ap);
  return result;
}
FUNCS
    }

    #
    # Array of callback entry pointers.
    #
    print FUNCS "\nstatic const cb_callback cb_arr[DYNALIB_NUM_CALLBACKS] = {\n";
    for $i (0 .. $num_callbacks - 1) {
	print FUNCS "\t_cb_func$i,\n";
    }
    print FUNCS "};\n";
}

sub parse_perl_types
{
  unless (eval "use Convert::Binary::C;") {
    print "Warning: Convert::Binary::C not installed. PerlTypes not generated.\n";
    return;
  }
  Convert::Binary::C->import;
  use Data::Dumper;
  my $byteorder = is_big_endian();
  my $c = new Convert::Binary::C('ByteOrder' => $byteorder ? 'BigEndian' : 'LittleEndian');
  $c->Include(["$Config{archlib}/CORE", '/usr/include', $Config{incpath},
	       $Config{locincpth}, @{$c->Include}]);
  eval { $c->parse("#include <EXTERN.h>\n#include <perl.h>"); };
  my $cfg = $c->configure;
  my $dump = Data::Dumper->Dump([$cfg], ['PerlTypes']);
  my $fname = "lib/C/DynaLib/PerlTypes.pm";
  open XS, "> $fname"
    or die "Can't write file \"$fname\": $!\n";
  print "Adding Convert::Binary::C configuration to $fname\n";
  print XS <<XS;
# PerlTypes.pm generated by Makefile.PL.  Don't edit this file, edit Makefile.PL.
# From Convert::Binary::C \$c->parse("#include <EXTERN.h>\n#include <perl.h>")->configure

package C::DynaLib::PerlTypes;

$dump;

1;
__END__
XS
  # eval C::DynaLib::PERLTYPES => %C::DynaLib::Struct::PerlTypes;
  close XS;
}
