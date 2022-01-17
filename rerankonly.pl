#!/usr/bin/env perl
# -*- coding: utf-8 -*-
use strict;
use warnings;
use List::Util qw(sum max);
use Getopt::Long;
use utf8;
use open ':utf8';
binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";
$| = 1;

my $field_1 = 0; # keys
my $field_2 = 1; # ents
my $top_n = 10;
my @sort_by = (); # hits or ccrate or vgrate
my $auto_cut = 1; # 1(ON) or 0(OFF)
my $show_mode = 1; # 0(OFF) or 1(with query+score) or 2(with query)
my $comment_block_prefix = "";
GetOptions (
    "1=s" => \$field_1,
    "2=s" => \$field_2,
    "topn=s" => \$top_n,
    "sortby=s" => \@sort_by,
    "autocut=s" => \$auto_cut,
    "show=s" => \$show_mode,
    "comment-block-prefix=s" => \$comment_block_prefix,
    );

@sort_by = qw(ccrate vgrate) if not @sort_by; # default order of sort

$/ = "\n\n";

while (<>) {
    s/\n+$/\n/;
    s/^\n+//;

    if ($comment_block_prefix and /^\Q$comment_block_prefix/) {
	print $_."\n";
	next;
    }

    my ($query_line, @lines) = split(/\n/, $_);
    print $query_line."\n" if $show_mode;

    my $key = regstr((split(/\t/, $query_line))[$field_1] || "");

    # get results
    my $lines_r = do {
	my $l_r = [];
	foreach my $line (@lines) {
	    my $str = regstr((split(/\t/, $line))[$field_2] || "");
	    chomp $str;
	    push @$l_r, {str => $str, line => $line."\n"};
	}
	$l_r;
    };

    if (@$lines_r) {
	my $res_r = re_ranking($key, $lines_r, $auto_cut);
	print "".($show_mode == 1 ? "[$_->{ccrate},$_->{vgrate}]\t" : "").$_->{line} for @$res_r;
    }
    print "\n";
}

exit;

# reranking: calc score, filter, sort
sub re_ranking {
    my ($key, $lines_r, $auto_cut) = @_;

    # calc
    my $rr = calc_score_ccrate($key, $lines_r);
    $rr = calc_score_vgrate($key, $lines_r);
    
    # filter
    my $max_ccrate = max(map {$_->{ccrate}} @$rr);
    my $max_vgrate = max(map {$_->{vgrate}} @$rr);
    if ($auto_cut) {
	@$rr = grep {!($max_ccrate == 1 and $_->{ccrate} < 1)
			 and $_->{vgrate} > 0
			 and ($max_vgrate/$_->{vgrate} < 2)} @$rr;
    }

    # sort
    return [sort {
	foreach my $k (@sort_by) {
	    my $v = ($b->{$k} <=> $a->{$k});
	    return $v if $v;
	}
     } @$rr];
};

# 文字列正規化
sub regstr {
    my ($str) = @_;
    $str =~ tr/Ａ-Ｚａ-ｚ０-９　！”＃＄％＆’（）＊＋，−．／：；＜＝＞？＠［¥］＾＿‘｛｜｝〜/A-Za-z0-9 !"#$%&'()*+,-.\/:;<=>?@[\]^_`{|}~/;
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

# "aab" => {"aac":1,"aa":1,"ab":1,"a":2,"b":1}
sub mk_all_ngram {
    my ($key) = @_;
    my @chars = split(//, $key);
    my %vgram;
    for (my $i = 0; $i < @chars; $i++) {
	for (my $j = $i; $j < @chars; $j++) {
	    $vgram{join("", @chars[$i..$j])}++;
	}
    }
    return \%vgram;
}

# {"aac":1,"aa":1,"ab":1,"a":2,"b":1} => ("aaa","aa","ab","a","a","b")
sub counthash_to_list {
    my ($h_r) = @_;
    return [map {($_) x $h_r->{$_}} keys %$h_r];
}

# (a a b c x) vs (a b d x x) => (a b x)
sub common_items {
    my ($a_r, $b_r) = @_;
    my @la = sort @$a_r;
    my @lb = sort @$b_r;
    my @common_items;
    for (my ($ia, $ib) = (0, 0); $ia < @la and $ib < @lb; $ia++, $ib++) {
	if ($la[$ia] eq $lb[$ib]) {
	    push @common_items, $la[$ia];
	} elsif (($la[$ia] cmp $lb[$ib]) > 0) {
	    $ia--;
	} else {
	    $ib--;
	}
    }
    return \@common_items;
}

# 文字列照合でスコア計算
# cc: common chars rate: 一致した文字数 / キーの文字数
sub calc_score_ccrate {
    my ($key, $ents_r) = @_;
    my $key_chars_r = counthash_to_list(mk_ngram($key, 1));
    foreach my $e (@$ents_r) {
	my $ent_chars_r = counthash_to_list(mk_ngram($e->{str}, 1));
	my @matched_ngrams = @{common_items($key_chars_r, $ent_chars_r)};
	$e->{ccrate} = sprintf("%.4f", @matched_ngrams / (@$key_chars_r||1));
    }
    return $ents_r;
} 

# 文字列照合でスコア計算
# vg: variable gram rate: 一致した全 ngram / キーの全 ngram
sub calc_score_vgrate {
    my ($key, $ents_r) = @_;
    my $key_vgram_r = counthash_to_list(mk_all_ngram($key));
    foreach my $e (@$ents_r) {
	my $ent_vgram_r = counthash_to_list(mk_all_ngram($e->{str}));
	my @matched_vgrams = @{common_items($key_vgram_r, $ent_vgram_r)};
	$e->{vgrate} = sprintf("%.4f", @matched_vgrams / (@$key_vgram_r||1));
    }
    return $ents_r;
} 
