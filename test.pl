# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $^W = 1; $| = 1; print "1..10\n"; }
END {print "not ok 1\n" unless $loaded;}
use C::DynaLib ();
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

use Carp;
eval {
    $SIG{SEGV} = sub { use Carp; confess "Illegal memory operation" };
    $SIG{ILL} = $SIG{SEGV};
};
use vars qw ($tmp1 $tmp2);

# Don't let old Exporters ruin our fun.
sub DeclareSub { &C::DynaLib::DeclareSub }
sub PTR_TYPE { &C::DynaLib::PTR_TYPE }

$test_num = 2;
sub assert {
    my ($assertion, $got, $expected) = (@_, '', '');
    if ($assertion && $got eq $expected) {
	print "ok $test_num\n";
    } elsif ($got ne $expected) {
	print "not ok $test_num; expected \"$expected\", got \"$got\"\n";
    } else {
	print "not ok $test_num\n";
    }
    ++ $test_num;
}

use Config;
$libc_arg = $Config{libc} || "-lc";
$libc = new C::DynaLib($libc_arg);

if (! $libc) {
  if ($^O =~ /cygwin32/ || $^O eq "MSWin32") {
    $libc = new C::DynaLib("MSVCRT40.DLL")
      || new C::DynaLib("\\WINDOWS\\SYSTEM\\MSVCRT40.DLL");
  } elsif ($^O eq 'linux') {
    $libc = new C::DynaLib("libc.so.6");
  }
}
if (! $libc) {
    assert(0);
    die "Can't load -lc: ", DynaLoader::dl_error(), "\nGiving up.\n";
}

$libm_arg = DynaLoader::dl_findfile("-lm");
if (! $libm_arg) {
    $libm = $libc;
} elsif ($libm_arg !~ /libm\.a$/) {
    $libm = new C::DynaLib("-lm");
}
$libm and $pow = $libm->DeclareSub ({ "name" => "pow",
				      "return" => "double",
				      "args" => ["d", "d"],
				    });

if (! $pow) {
    warn "$0: Can't find dynamic -lm!  Skipping the math lib tests.\n";
    assert(1);
} else {
    $sqrt2 = &$pow(2, 0.5);
    assert(1, $sqrt2, 2**0.5);
}

$strlen = $libc->DeclareSub ({ "name" => "strlen",
				"return" => "i",
				"args" => ["p"],
			    });

# Can't do this in perl <= 5.00401 because it results in a
# pack("p", constant)...
#
# $len = &$strlen("oof rab zab");

$len = &$strlen($tmp = "oof rab zab");
assert(1, $len, 11);

sub my_sprintf {
    my ($fmt, @args) = @_;
    my (@arg_types) = ("P", "p");
    my ($width) = (length($fmt) + 1);

    # note this is a *simplified* (non-crash-proof) printf parser!
    while ($fmt =~ m/(?:%[-#0 +']*\d*(?:\.\d*)?h?(.).*?)[^%]*/g) {
			  my $spec = $1;
			  next if $spec eq "%";
			  if (index("dic", $spec) > -1) {
			      push @arg_types, "i";
			      $width += 20;
			  } elsif (index("ouxXp", $spec) > -1) {
			      push @arg_types, "I";
			      $width += 20;
			  } elsif (index("eEfgG", $spec) > -1) {
			      push @arg_types, "d";
			      $width += 30;
			  } elsif ("s" eq $spec) {
			      push @arg_types, "p";
			      $width += length($args[$#arg_types]);
			  } else {
			      die "Unknown printf specifier: $spec\n";
			  }
	       }
		      my $buffer = "\0" x $width;
		      &{$libc->DeclareSub("sprintf", "", @arg_types)}
			($buffer, $fmt, @args);
		      $buffer =~ s/\0.*//;
		      return $buffer;
		  }

{} if 0;  # poor old Emacs :(

$fmt = "%x %10sfoo %d %10.7g %f %d %d %d";
@args = (253, "bar", -789, 2.32578, 3.14, 5, 6, 7);

$expected = sprintf($fmt, @args);
$got = my_sprintf($fmt, @args);

assert(1, $got, $expected);

$ptr_len = length(pack("p", $tmp = "foo"));

# Try passing a pointer to DeclareSub.
$fopen_ptr = DynaLoader::dl_find_symbol($libc->LibRef(), "fopen")
    or die DynaLoader::dl_error();
$fopen = DeclareSub ({ "ptr" => $fopen_ptr,
		       "return" => PTR_TYPE,
		       "args" => ["p", "p"] });

open TEST, ">tmp.tmp"
    or die "Can't write file tmp.tmp: $!\n";
print TEST "a string";
close TEST;

# Can't do &$fopen("tmp.tmp", "r") in perls before 5.00402.
$fp = &$fopen($tmp1 = "tmp.tmp", $tmp2 = "r");
if (! $fp) {
    assert(0);
} else {
    # Hope "I" will work for type size_t!
    $fread = $libc->DeclareSub("fread", "i",
				"P", "I", "I", PTR_TYPE);
    $buffer = "\0" x 4;
    $result = &$fread($buffer, 1, length($buffer), $fp);
    assert($result == 4, $buffer, "a st");
}
unlink "tmp.tmp";

if (@$C::DynaLib::Callback::Config) {
    sub compare_lengths {
	# Not a model of efficiency, only a test of functionality!!
	my ($ppa, $ppb) = @_;
	my $pa = unpack("P$ptr_len", pack(PTR_TYPE, $ppa));
	my $pb = unpack("P$ptr_len", pack(PTR_TYPE, $ppb));
	my $A = unpack("p", $pa);
	my $B = unpack("p", $pb);
	length($A) <=> length($B);
    }
    @list = qw(A bunch of elements with unique lengths);
    $array = pack("p*", @list);

    #
    # This appears to work with either \&compare_lengths or
    # "::compare_lengths", but not "compare_lengths".
    #
    $callback = new C::DynaLib::Callback(\&compare_lengths, "i",
						PTR_TYPE,
						PTR_TYPE);

    $qsort = $libc->DeclareSub("qsort", "",
			       "P", "I", "I", PTR_TYPE);
    &$qsort($array, scalar(@list), length($array) / @list, $callback->Ptr());

    @expected = sort { length($a) <=> length($b) } @list;
    @got = unpack("p*", $array);
    assert(1, "[@got]", "[@expected]");

    # Hey!  We've got callbacks.  We've got a way to call them.
    # Who needs libraries?
    undef $callback;
    $callback = new C::DynaLib::Callback(sub {
	$_[0] + 10*$_[1] + 100*$_[2];
    }, "i", "i", "p", "i");
    $sub = DeclareSub($callback->Ptr(), "i", "i", "p", "i");

    $got = &$sub(1, $tmp = 7, 3.14);
    $expected = 371;
    assert(1, $got, $expected);

    undef $callback;
    $callback = new C::DynaLib::Callback(sub { shift }, "I", "i");
    $sub = DeclareSub($callback->Ptr(), "I", "i");
    $got = &$sub(-1);

    # Can't do this because it's broken in too many Perl versions:
    # $expected = unpack("I", pack("i", -1));
    $expected = 0;
    for ($i = 1; $i > 0; $i <<= 1) {
      $expected += $i;
    }
    $expected -= $i;
    assert(1, $got, $expected);

    $int_size = length(pack("i",0));
    undef $callback;
    $callback = new C::DynaLib::Callback(sub {
	  $global = shift;
	  $global .= pack("i", shift);
	  return unpack(PTR_TYPE, pack("P", $global));
	},
	PTR_TYPE, "P".(2 * $int_size), "i");
    $sub = DeclareSub($callback->Ptr(), "P".(3 * $int_size),
	PTR_TYPE, "i");
    $array = pack("ii", 1729, 31415);
    $pointer = unpack(PTR_TYPE, pack("P", $array));
    $struct = &$sub($pointer, 253);
    @got = unpack("iii", $struct);
    assert(1, "[@got]", "[1729 31415 253]");

} else {
    warn("Skipping callback tests on this platform\n");
    assert(1);
    assert(1);
    assert(1);
    assert(1);
}

$buf = "willo";
C::DynaLib::Poke(unpack(PTR_TYPE,
			       pack("p", $buf)), "he");
assert(1, $buf, "hello");

# Can't unload libraries (portably, yet) because DynaLoader does not
# support this.
