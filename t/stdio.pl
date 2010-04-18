#/usr/bin/perl
use GCC::TranslationUnit;

open F, ">", "stdio.c";
print F "#include <stdio.h>\n";
close F;
system "gcc -fdump-translation-unit -c stdio.c";
@tu = glob "stdio.c.*.tu" or die;

$node = GCC::TranslationUnit::Parser->parsefile(pop @tu)->root;
# list every function/variable name
while ($node) {
  if($node->isa('GCC::Node::function_decl') or
     $node->isa('GCC::Node::var_decl')) {
    printf "%s declared in %s\n",
      $node->name->identifier, $node->source;
  }
} continue {
  $node = $node->chain;
}
