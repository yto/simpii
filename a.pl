my $h1_r = {"a"=>2,"b"=>3,"c"=>1,"x"=>1};
my $h2_r = {"a"=>1,"b"=>2,"x"=>2};
my $ans_r = common_items($h1_r, $h2_r);
print join(",", @$ans_r)."\n";
exit;
