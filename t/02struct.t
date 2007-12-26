use Test;
BEGIN { plan tests => 3 }

use C::DynaLib::Struct;
ok(1);

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
ok("[@got]" eq "[@expected]");

@expected = (-65, 5e9, "string");
$foobar = pack("idp", @expected);
@got = ($pfoobar->foo, (tied $foobar)->bar, $pfoobar->baz);
ok("[@got]" eq "[@expected]");
