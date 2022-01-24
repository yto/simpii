#!/usr/bin/env perl
# -*- coding: utf-8 -*-
use strict;
use warnings;
use Search::Dict;
use List::Util qw(max min);
use Getopt::Long;
use utf8;
use open ':utf8';
binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";
$| = 1;

my $idx_fn = "";
my $ent_fn = "";
my $field_1 = 0; # keys
my $field_2 = 1; # ents
my $top_n = 10;
my @sort_by = (); # hits or ccrate or vgrate
my $auto_cut = 1; # 1(ON) or 0(OFF)
my $reranking = 1; # 1(ON) or 0(OFF)
my $show_mode = 1; # 0(OFF) or 1(with query+score) or 2(with query)
my $similarity = "qbase"; # qbase(default) jaccard dice simpson
GetOptions (
    "index=s" => \$idx_fn,
    "entries=s" => \$ent_fn,
    "1=s" => \$field_1,
    "2=s" => \$field_2,
    "topn=s" => \$top_n,
    "sortby=s" => \@sort_by,
    "autocut=s" => \$auto_cut,
    "show=s" => \$show_mode,
    "reranking=s" => \$reranking,
    "similarity=s" => \$similarity,
    );

open(my $fh_idx, "<", $idx_fn) or die "can't open [$idx_fn]";
open(my $fh_ent, "<", $ent_fn) or die "can't open [$ent_fn]";

my $n_of_ngram = do {(my $l = <$fh_idx>) =~ s/^([^\t]+)\t.*$/$1/s; length($l);}; #  ngramのnを調べる
my $ii_top_n = $top_n * 5; # 転置インデックス検索で取得する数 (結果表示する数のN倍)
@sort_by = qw(hits ccrate vgrate) if not @sort_by; # default order of sort

while (<>) {
    print $_ if $show_mode;
    chomp;

    my $key = regstr((split(/\t/, $_))[$field_1] || "");

    # get results
    my $lines_r = do {
	my $ngram_r = mk_ngram($key, $n_of_ngram);
	my $id_hit_r = look_and_get_ids([keys %$ngram_r], $fh_idx);
	my @cand_ids = sort {$id_hit_r->{$b} <=> $id_hit_r->{$a}} keys %$id_hit_r;
	@cand_ids = @cand_ids[0..($ii_top_n-1)] if $ii_top_n < @cand_ids;
	my $l_r = get_contents(\@cand_ids, $fh_ent);
	foreach my $l (@$l_r) {
	    $l->{hits} = $id_hit_r->{$l->{id}}; # ngram index のヒット数
	    $l->{str} = regstr((split(/\t/, $l->{line}))[$field_2] || "");
	    chomp $l->{str};
	}
	$l_r;
    };

    if (not $reranking) {
	print "".($show_mode == 1 ? "[$_->{hits}]\t" : "").$_->{line} for grep {$_} @{$lines_r}[0..($top_n-1)];
    } else {
	my $res_r = re_ranking($key, $lines_r, $auto_cut);
	print "".($show_mode == 1 ? "[$_->{hits},$_->{ccrate},$_->{vgrate}]\t" : "").$_->{line} for grep {$_} @{$res_r}[0..($top_n-1)];
    }
}

close($fh_idx);
close($fh_ent);

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

# search invertd index. 複数キーでの検索結果のマージ
# FORMAT: ^のため[\t]6ZKYBA,6ZKYN3,799VBT[\n]$
sub look_and_get_ids {
    my ($keys_r, $fh) = @_;
    my %id_count;
    foreach my $ngram (@$keys_r) {
	look $fh, $ngram;
	my $line = readline($fh);
	next unless $line =~ /^\Q$ngram\E\t/; # no hit 対策
	chomp $line;
	$id_count{$_} += 1 for split(",", (split(/\t/, $line))[1]);
    }
    return \%id_count;
}

# FORMAT: ^[ID]....$
sub get_contents {
    my ($ids_r, $fh) = @_;
    return [grep {$_->{line} =~ /^\Q$_->{id}\E/} map {look $fh, $_; my $line = readline($fh); {id => $_, line => $line}} @$ids_r];
}

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

# 類似度計算
sub calc_similarity {
    my ($A_r, $B_r) = @_;
    my @AB = @{common_items($A_r, $B_r)};
    return 0 if @AB == 0;
    return @AB / @$A_r if $similarity =~ /^qbase/;
    return @AB / (@$A_r + @$B_r - @AB) if $similarity =~ /^jaccard/;
    return @AB * 2 / (@$A_r + @$B_r) if $similarity =~ /^dice/;
    return @AB / min(@$A_r+0, @$B_r+0) if $similarity =~ /^simpson/;
}

# 文字列照合でスコア計算
# cc: common chars rate: 一致した文字数 / キーの文字数
sub calc_score_ccrate {
    my ($key, $ents_r) = @_;
    my $key_chars_r = counthash_to_list(mk_ngram($key, 1));
    foreach my $e (@$ents_r) {
	my $ent_chars_r = counthash_to_list(mk_ngram($e->{str}, 1));
	$e->{ccrate} = sprintf("%.4f", calc_similarity($key_chars_r, $ent_chars_r));

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
	$e->{vgrate} = sprintf("%.4f", calc_similarity($key_vgram_r, $ent_vgram_r));
    }
    return $ents_r;
} 
