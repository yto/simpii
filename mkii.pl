#!/usr/bin/env perl
# -*- coding: utf-8 -*-
use strict;
use warnings;
use utf8;
use Getopt::Long qw(:config no_ignore_case autoabbrev);
use open ':utf8';
binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";

my $n_of_ngram = 3;
my $max_pos = 0;
GetOptions (
    "ngram=s" => \$n_of_ngram,
    "max=s" => \$max_pos,
    );

my %idx;
while (<>) {
    chomp;
    my ($id, $text) = split(/\t/, $_);
    next unless $text;
    my $ngram_r = mk_ngram(regstr($text), $n_of_ngram);
    for my $str (keys %$ngram_r) {
	next if $max_pos and defined $idx{$str} and $max_pos < @{$idx{$str}};
	push @{$idx{$str}}, $id;
    }
}
print "$_\t".join(",", @{$idx{$_}})."\n" for grep {!$max_pos or @{$idx{$_}} <= $max_pos} sort keys %idx;
exit;

# 文字列正規化
sub regstr {
    my ($str) = @_;
    $str =~ tr/Ａ-Ｚａ-ｚ０-９　！”＃＄％＆’（）＊＋，−．／：；＜＝＞？＠［¥］＾＿‘｛｜｝〜/A-Za-z0-9 !"#$%&'()*+,-.\/:;<=>?@[\]^_`{|}~/;
    $str =~ s/[\x{2010}-\x{2015}\x{2212}\x{FF0D}]/-/g; # hyphen
    return $str;
}

# "abc abc",3 => {"abc":2,"bc ":1,"c a":1," ab":1}
sub mk_ngram {
    my ($key, $n) = @_;
    my @chars = split(//, $key);
    my %ngram;
    for (my $i = 0; $i < @chars - ($n - 1); $i++) {
	$ngram{join("", @chars[$i..($i + ($n - 1))])}++;
    }
    return \%ngram;
}

