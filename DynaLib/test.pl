# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..3\n"; }
END {print "not ok 1\n" unless $loaded;}
use C::DynaLib::Struct;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

$num = 2;
sub assert {
    my ($assertion, $got, $expected) = @_;
    if ($assertion && $got eq $expected) {
	print "ok $num\n";
    } elsif ($got ne $expected) {
	print "not ok $num; expected \"$expected\", got \"$got\"\n";
    } else {
	print "not ok $num\n";
    }
    ++ $num;
}

#
# struct FooBar {
#   int foo;
#   double bar;
#   char *baz;
# };
#
Define C::DynaLib::Struct('FooBar', "i", ['foo'],
    "dp", [ qw(bar baz) ]);

$pfoobar = tie ($foobar, 'FooBar', 1, 2);
$pfoobar->baz("Hello");
$pfoobar->foo(3);
@expected = (3, 2, "Hello");
@got = unpack("idp", $foobar);
assert(1, "[@got]", "[@expected]");

@expected = (-65, 5e9, "string");
$foobar = pack("idp", @expected);
@got = ($pfoobar->foo, (tied $foobar)->bar, $pfoobar->baz);
assert(1, "[@got]", "[@expected]");
