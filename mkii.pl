#!/usr/bin/env perl
# -*- coding: utf-8 -*-
use strict;
use warnings;
use utf8;
use Getopt::Long;
use open ':utf8';
binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";

my $n_of_ngram = 3;
GetOptions ("ngram=s" => \$n_of_ngram);

my %idx;
while (<>) {
    chomp;
    my ($id, $text) = split(/\t/, $_);
    next unless $text;
    my $ngram_r = mk_ngram(regstr($text), $n_of_ngram);
    push @{$idx{$_}}, $id for keys %$ngram_r;
}
print "$_\t".join(",", @{$idx{$_}})."\n" for sort keys %idx;
exit;

# 文字列正規化
sub regstr {
    my ($str) = @_;
    $str =~ tr/Ａ-Ｚａ-ｚ０-９　！”＃＄％＆’（）＊＋，−．／：；＜＝＞？＠［¥］＾＿‘｛｜｝〜/A-Za-z0-9 !"#$%&'()*+,-.\/:;<=>?@[\]^_`{|}~/;
    return $str;
}

# "abc de" => "abc","bc ","c d"," de"
sub mk_ngram {
    my ($key, $n) = @_;
    my @chars = split(//, $key);
    my %ngram;
    for (my $i = 0; $i < @chars - ($n - 1); $i++) {
	$ngram{join("", @chars[$i..($i + ($n - 1))])}++;
    }
    return \%ngram;
}

