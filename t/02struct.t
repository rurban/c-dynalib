# -*- perl -*-
use Test::More tests => 4;

use C::DynaLib::Struct;
ok(1);

Define C::DynaLib::Struct('FooBar', "i", ['foo'],
    "dp", [ qw(bar baz) ]);

$pfoobar = tie ($foobar, 'FooBar', 1, 2);
$pfoobar->baz("Hello");
$pfoobar->foo(3);
@expected = (3, 2, "Hello");
@got = unpack("idp", $foobar);
ok("[@got]" eq "[@expected]");

@expected = (-65, 5e9, "string");
$foobar = pack("idp", @expected);
@got = ($pfoobar->foo, (tied $foobar)->bar, $pfoobar->baz);
ok("[@got]" eq "[@expected]");

SKIP: {
  skip "no Convert::Binary::C", 1 unless $Convert::Binary::C::VERSION;

  C::DynaLib::Struct::Parse(<<CCODE);
struct FooBar {
    int foo;
    double bar;
    char *baz;
};
CCODE

  $pfoobar = tie ($foobar, 'FooBar', 1, 2);
  $pfoobar->baz("Hello");
  $pfoobar->foo(3);
  @expected = (3, 2, "Hello");
  @got = unpack("idp", $foobar);
  ok("[@got]" eq "[@expected]");
}
