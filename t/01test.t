use Test::Simple tests => 11;
use C::DynaLib ();
# optional dependency
eval "use sigtrap;";
ok(1);

sub goof {
  require Carp;
  Carp::confess "Illegal memory operation";
}

eval {
  $SIG{SEGV} = \&goof;
  $SIG{ILL} = \&goof;
};
use vars qw ($tmp1 $tmp2);

# Don't let old Exporters ruin our fun.
sub DeclareSub { &C::DynaLib::DeclareSub }
sub PTR_TYPE { &C::DynaLib::PTR_TYPE }

use Config;
$libc = new C::DynaLib($Config{'libc'} || "-lc");

if (! $libc) {
  # cygwin has no shared libc.so. Same for libm.so
  if ($^O eq 'cygwin') {
    $libc = new C::DynaLib("cygwin1.dll");
  } elsif ($^O =~ /(MSWin32)/) {
    $libc = new C::DynaLib("MSVCRT.DLL")
      || new C::DynaLib("MSVCRT80")
      || new C::DynaLib("MSVCRT71")
      || new C::DynaLib("MSVCRT70")
      || new C::DynaLib("MSVCRT60")
      || new C::DynaLib("MSVCRT40")
      || new C::DynaLib("MSVCRT20");
  } elsif ($^O =~ /linux/i) {
    # Some glibc versions install "libc.so" as a linker script,
    # unintelligible to dlopen().
    $libc = new C::DynaLib("libc.so.6");
  }
}
if (! $libc) {
  ok(0, "libc: $libc"); #2
  die "Can't load -lc: ", DynaLoader::dl_error(), "\nGiving up.\n";
}

$libm_arg = DynaLoader::dl_findfile("-lm");
if (! $libm_arg) {
  $libm = $libc;
} elsif ($libm_arg !~ /libm\.a$/) {
  $libm = new C::DynaLib("-lm");
} elsif ($^O eq 'cygwin') {
  $libm = $libc;
}

$libm and $pow = $libm->DeclareSub ({ "name" => "pow",
				      "return" => "d",
				      "args" => ["d", "d"]});
if (!$pow) {
  skip(1, "Can't find dynamic -lm!  Skipping the math lib tests.");
} elsif ($C::DynaLib::decl eq 'hack30') {
 TODO: {
  local $TODO = "hack30 can not handle double";
  $sqrt2 = 2**0.5;
  ok(&$pow(2, 0.5) == $sqrt2, "pow(2, 0.5) from -lm"); #2
 }
} else {
  $sqrt2 = 2**0.5;
  ok(&$pow(2, 0.5) == $sqrt2, "pow(2, 0.5) from -lm"); #2
}
$strlen = $libc->DeclareSub ({ "name" => "strlen",
			       "return" => "i",
			       "args" => ["p"],
			     });

# Can't do this in perl <= 5.00401 because it results in a
# pack("p", constant):
#
# $len = &$strlen("oof rab zab");

$len = &$strlen($tmp = "oof rab zab");
ok($len == 11, "len == 11"); #3

sub my_sprintf {
  my ($fmt, @args) = @_;
  my (@arg_types) = ("P", "p");
  my ($width) = (length($fmt) + 1);

  # note this is a *simplified* (non-crash-proof) printf parser!
  while ($fmt =~ m/(?:%[-\#0 +\']*\d*(?:\.\d*)?h?(.).*?)[^%]*/g) {
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

$fmt = "%x %10sfoo %d %10.7g %f %d %d %d";
@args = (253, "bar", -789, 2.32578, 3.14, 5, 6, 7);

$expected = sprintf($fmt, @args);
$got = my_sprintf($fmt, @args);

ok($got eq $expected, "expected: $expected"); #4

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
  ok(0, q(Can't do &$fopen("tmp.tmp", "r") in perls before 5.00402.)); #5
} else {
  # Hope "I" will work for type size_t!
  $fread = $libc->DeclareSub("fread", "i",
			     "P", "I", "I", PTR_TYPE);
  $buffer = "\0" x 4;
  $result = &$fread($buffer, 1, length($buffer), $fp);
  ok($result == 4); #5
  ok($buffer eq "a st"); #6
}
unlink "tmp.tmp";

if (@$C::DynaLib::Callback::Config) {
  sub compare_lengths {
    length(unpack("p", $_[0])) <=> length(unpack("p", $_[1]));
  }
  @list = qw(A bunch of elements with unique lengths);
  $array = pack("p*", @list);

  $callback = new C::DynaLib::Callback("compare_lengths", "i",
				       "P$ptr_len", "P$ptr_len");

  $qsort = $libc->DeclareSub("qsort", "",
			     "P", "I", "I", PTR_TYPE);
  &$qsort($array, scalar(@list), length($array) / @list, $callback->Ptr());

  @expected = sort { length($a) <=> length($b) } @list;
  @got = unpack("p*", $array);
  ok("[@got]" eq "[@expected]"); #7

  # Hey!  We've got callbacks.  We've got a way to call them.
  # Who needs libraries?
  undef $callback;
  $callback = new C::DynaLib::Callback
    (sub {
       $_[0] + 10*$_[1] + 100*$_[2];
     }, "i", "i", "p", "i");
  $sub = DeclareSub($callback->Ptr(), "i", "i", "p", "i");

  $got = &$sub(1, $tmp = 7, 3.14);
  $expected = 371;
  ok($got == $expected); #8

  undef $callback;
  $callback = new C::DynaLib::Callback(sub { shift }, "I", "i");
  $sub = DeclareSub($callback->Ptr(), "I", "i");
  $got = &$sub(-1);

  # Can't do this generally because it's broken in too many Perl versions:
  if (0 and $^O eq 'cygwin') { # TODO: needed for an earlier version
    $expected = unpack("I", pack("i", -1));
  } else {
    $expected = 0;
    for ($i = 1; $i > 0; $i <<= 1) {
      $expected += $i;
    }
    $expected -= $i;
  }
  ok($got == $expected, "Callback Ii $got == $expected"); #9

  $int_size = length(pack("i",0));
  undef $callback;
  $callback = new C::DynaLib::Callback
    (sub {
       $global = shift;
       $global .= pack("i", shift);
       return unpack(PTR_TYPE, pack("P", $global));
     }, PTR_TYPE, "P".(2 * $int_size), "i");

  $sub = DeclareSub($callback->Ptr(), "P".(3 * $int_size), PTR_TYPE, "i");
  $array = pack("ii", 1729, 31415);
  $pointer = unpack(PTR_TYPE, pack("P", $array));
  $struct = &$sub($pointer, 253);
  @got = unpack("iii", $struct);
  ok("[@got]" eq "[1729 31415 253]"); #10

} else {
  print ("# Skipping callback tests on this platform\n");
}

$buf = "willo";
C::DynaLib::Poke(unpack(PTR_TYPE, pack("p", $buf)), "he");
ok($buf eq "hello"); #11
