#!/usr/bin/env perl
# -*- coding: utf-8 -*-
use strict;
use warnings;
use Search::Dict;
use List::Util qw(sum max);
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
my @sort_by = (); # hits or ccrate or vgscore
my $auto_cut = 1; # 1(ON) or 0(OFF)
GetOptions (
    "index=s" => \$idx_fn,
    "entries=s" => \$ent_fn,
    "1=s" => \$field_1,
    "2=s" => \$field_2,
    "topn=s" => \$top_n,
    "sortby=s" => \@sort_by,
    "autocut=s" => \$auto_cut,
    );

open(my $fh_idx, "<", $idx_fn) or die "can't open [$idx_fn]";
open(my $fh_ent, "<", $ent_fn) or die "can't open [$ent_fn]";

my $n_of_ngram = do {(my $l = <$fh_idx>) =~ s/^([^\t]+)\t.*$/$1/s; length($l);};
@sort_by = qw(hits ccrate vgscore) if not @sort_by; # default order of sort

while (<>) {
    print $_;
    chomp;

    my $key = regstr((split(/\t/, $_))[$field_1] || "");

    # get results
    my $lines_r = do {
	my $ngram_r = mk_ngram($key, $n_of_ngram);
	my $id_hit_r = look_and_get_ids([keys %$ngram_r], $fh_idx);
	my @cand_ids = sort {$id_hit_r->{$b} <=> $id_hit_r->{$a}} keys %$id_hit_r;
	@cand_ids = @cand_ids[0..($top_n-1)] if $top_n < @cand_ids;
	my $l_r = get_contents(\@cand_ids, $fh_ent);
	foreach my $l (@$l_r) {
	    $l->{hits} = $id_hit_r->{$l->{id}}; # ngram index のヒット数
	    $l->{str} = regstr((split(/\t/, $l->{line}))[$field_2] || "");
	}
	$l_r;
    };

    # score, filter, sort
    my $res_r = do {

	# calc
	my $rr = calc_score($key, $lines_r);
	
	# filter
	my $max_ccrate = max(map {$_->{ccrate}} @$rr);
	my $max_vgscore = max(map {$_->{vgscore}} @$rr);
	if ($auto_cut) {
	    @$rr = grep {!($max_ccrate == 1 and $_->{ccrate} < 1) and ($max_vgscore/$_->{vgscore} < 2)} @$rr;
	}

	# sort
	[sort {
	    foreach my $k (@sort_by, "hits") {
		my $v = ($b->{$k} <=> $a->{$k});
		return $v if $v;
	    }
	 } @$rr];
    };

    # output
    print "[$_->{hits},$_->{ccrate},$_->{vgscore}]\t$_->{line}" for @$res_r;
}

close($fh_idx);
close($fh_ent);

exit;

# search invertd index. 複数キーでの検索結果のマージ
# FORMAT: ^のため[\t]B006ZKYBAO,B006ZKYN3Y,B00799VBTY[\n]$
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

# "abc" => "abc","ab","bc","a","b","c"
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

# (a a b c x) vs (a b d x x) => (a b x)
sub common_chars {
    my ($a_r, $b_r) = @_;
    my @la = sort @$a_r;
    my @lb = sort @$b_r;
    my @common_chars;
    for (my ($ia, $ib) = (0, 0); $ia < @la and $ib < @lb; $ia++, $ib++) {
	if ($la[$ia] eq $lb[$ib]) {
	    push @common_chars, $la[$ia];
	} elsif (($la[$ia] cmp $lb[$ib]) > 0) {
	    $ia--;
	} else {
	    $ib--;
	}
    }
    return \@common_chars;
}

# 文字列照合でスコア計算
# cc: common chars rate: 一致した文字数をもとにした Dice係数。
# vg: variable gram: 最長一致でkeyのvgramとマッチさせる。マッチしたvgramのlength**2/2を加算。
sub calc_score {
    my ($key, $ents_r) = @_;
    my @key_chars = split(//, $key);
    my $vgram_pat = join("|", map {qq(\Q$_\E)} sort {length($b) <=> length($a)} keys %{mk_all_ngram(regstr($key))});
    foreach my $e (@$ents_r) {
	my @ent_chars = split(//, $e->{str});
	$e->{ccrate} = sprintf("%.4f", (@{common_chars(\@key_chars, \@ent_chars)} * 2) / (@key_chars + @ent_chars));
	my @matched_ngrams = ($e->{str} =~ /($vgram_pat)/g);
	$e->{vgscore} = sum(map {my $l = length($_); $l**2/2} @matched_ngrams) || 0;
    }
    return $ents_r;
} 

