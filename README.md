# simpii

simpii は単純な転置インデックス検索システムです。

Simple Inverted Index Search → simpii


## 準備

Perl が必要。
```
sudo yum install -y perl
```


## 使い方

機能の説明、兼、チュートリアル。


### インデックス作成と類似文字列検索

- mkii.pl : インデクサー
- searchii.pl : 検索スクリプト

```
% cat test.txt
1	これはペンです
2	最近はどうですか？
3	ペンギン大好き
4	こんにちは。いかがおすごしですか？
5	ここ最近疲れ気味
6	ペンキ塗りたてで気味が悪いです
% ./mkii.pl test.txt > test.txt.ii 
% cat test.txt.ii
。いか	4
いかが	4
いです	6
うです	2
おすご	4
かがお	4
...
% echo 'これはペンギンですか？' | ./searchii.pl -i test.txt.ii -e test.txt
これはペンギンですか？
[4,0.6364,0.3030]	1	これはペンです
[2,0.5455,0.1818]	4	こんにちは。いかがおすごしですか？
[2,0.4545,0.1667]	2	最近はどうですか？
```
(test.txt のフォーマット: 第1カラムがID、第2カラムがテキストで文字列マッチ対象)

クエリは行。標準入力。
```
% echo 'これはペンギンですか？\n気味が悪い' | ./searchii.pl -i test.txt.ii -e test.txt
これはペンギンですか？
[4,0.6364,0.3030]	1	これはペンです
[2,0.5455,0.1818]	4	こんにちは。いかがおすごしですか？
[2,0.4545,0.1667]	2	最近はどうですか？
気味が悪い
[3,1.0000,1.0000]	6	ペンキ塗りたてで気味が悪いです
```

ターゲットとなるファイル(test.txt)をエントリーファイル、
検索用インデックスファイル(test.txt.ii)を転置インデックスファイルと呼ぶ。
searchii.pl ではそれぞれ "-e" "-i" オプションで指定する。

出力結果の第1カラムはスコアが入る。
現在のフォーマット。カッコ内CSV、要素は下記：
- 転置インデックスの ngram ヒット数
- リランキング時の文字(unigram)の一致度
- リランキング時の全ngram(vgram)の一致度

オプション "--reranking 0" でリランキングなしでの結果表示ができる。
スコアは ngram ヒット数 (hits) のみが表示される。
```
% echo 'これはペンギンですか？' | ./searchii.pl -i test.txt.ii -e test.txt --reranking 0
これはペンギンですか？
[4]	1	これはペンです
[2]	4	こんにちは。いかがおすごしですか？
[2]	3	ペンギン大好き
[2]	2	最近はどうですか？
```

出力結果にスコアやクエリを出すか否かを "--show" オプションで指定できる。
"--show 0": クエリもスコアもなし、"--show 1": 全部あり、"--show 2": クエリだけ。
```
% echo 'これはペンギンですか？' | ./searchii.pl -i test.txt.ii -e test.txt -show 0
1	これはペンです
4	こんにちは。いかがおすごしですか？
2	最近はどうですか？
% echo 'これはペンギンですか？' | ./searchii.pl -i test.txt.ii -e test.txt -show 1
これはペンギンですか？
[4,0.6364,0.3030]	1	これはペンです
[2,0.5455,0.1818]	4	こんにちは。いかがおすごしですか？
[2,0.4545,0.1667]	2	最近はどうですか？
% echo 'これはペンギンですか？' | ./searchii.pl -i test.txt.ii -e test.txt -show 2
これはペンギンですか？
1	これはペンです
4	こんにちは。いかがおすごしですか？
2	最近はどうですか？
```

フィールドの指定。クエリとターゲットの類似文字列マッチさせるカラムをそれぞれ指定できる。
クエリ側は "-1"、ターゲット側は "-2" オプション。
デフォルトは "-1 0 -2 1"。
```
% echo 'query\tQ01\tこれはペンギンですか？' | ./searchii.pl -i test.txt.ii -e test.txt -1 2
query	Q01	これはペンギンですか？
[4,0.6364,0.3030]	1	これはペンです
[2,0.5455,0.1818]	4	こんにちは。いかがおすごしですか？
[2,0.4545,0.1667]	2	最近はどうですか？
```

出力する検索結果数の上限を "--topn" で指定できる。デフォルトは "--topn 10"。
```
% echo 'これはペンギンですか？' | ./searchii.pl -i test.txt.ii -e test.txt --topn 2
これはペンギンですか？
[4,0.6364,0.3030]	1	これはペンです
[2,0.5455,0.1818]	4	こんにちは。いかがおすごしですか？
```

リランキング時のスコアでのソートの優先度を "--sortby" で指定できる。
複数指定可能。先に指定したものが優先される。
例えば、"--sortby hits --sortby ccrate" だと hits が同じ場合は ccrate で上下が決まる。
デフォルトは "--sortby hits --sortby ccrate --sortby vgrate"。
詳細は後述。
```
% echo '最近はペンですか' | ./searchii.pl -i test.txt.ii -e test.txt --sortby vgrate
最近はペンですか
[3,0.6250,0.4167]	1	これはペンです
[2,0.7500,0.3333]	2	最近はどうですか？
% echo '最近はペンですか' | ./searchii.pl -i test.txt.ii -e test.txt --sortby ccrate
最近はペンですか
[2,0.7500,0.3333]	2	最近はどうですか？
[3,0.6250,0.4167]	1	これはペンです
% echo '最近はペンですか' | ./searchii.pl -i test.txt.ii -e test.txt --sortby hits
最近はペンですか
[3,0.6250,0.4167]	1	これはペンです
[2,0.7500,0.3333]	2	最近はどうですか？
% echo '最近はペンですか' | ./searchii.pl -i test.txt.ii -e test.txt --sortby hits -sortby ccrate --sortby vgrate
最近はペンですか
[3,0.6250,0.4167]	1	これはペンです
[2,0.7500,0.3333]	2	最近はどうですか？
```

ccrate 計算時に使う単位を "-N" で指定できる。デフォルトは "-N 1" で「文字」である。"-N 2" で bi-gram となる。

リランキング時のスコア（類似度）の計算方法を "--similarity" で指定できる。
デフォルトは "--similarity qbase"。
詳細は後述。
```
% echo '最近はペンですか' | ./searchii.pl -i test.txt.ii -e test.txt --similarity jaccard
最近はペンですか
[3,0.5000,0.3061]	1	これはペンです
[2,0.5455,0.1739]	2	最近はどうですか？
% echo '最近はペンですか' | ./searchii.pl -i test.txt.ii -e test.txt --similarity simpson
最近はペンですか
[3,0.7143,0.5357]	1	これはペンです
[2,0.7500,0.3333]	2	最近はどうですか？
% echo '最近はペンですか' | ./searchii.pl -i test.txt.ii -e test.txt --similarity dice   
最近はペンですか
[3,0.6667,0.4688]	1	これはペンです
[2,0.7059,0.2963]	2	最近はどうですか？
```

オートカットはある条件を満たさない結果を表示させない機能。
デフォルトは "--autocut 1" でONとなっている。全部表示させたい場合は "--autocut 0" とする。
（現状での「条件」： vgrate が TOP の半分より小さい、など）
```
% echo 'これはペンギンですか？' | ./searchii.pl -i test.txt.ii -e test.txt                
これはペンギンですか？
[4,0.6364,0.3030]	1	これはペンです
[2,0.5455,0.1818]	4	こんにちは。いかがおすごしですか？
[2,0.4545,0.1667]	2	最近はどうですか？
% echo 'これはペンギンですか？' | ./searchii.pl -i test.txt.ii -e test.txt --autocut 0
これはペンギンですか？
[4,0.6364,0.3030]	1	これはペンです
[2,0.5455,0.1818]	4	こんにちは。いかがおすごしですか？
[2,0.4545,0.1667]	2	最近はどうですか？
[2,0.3636,0.1515]	3	ペンギン大好き
```

インデックスは文字 ngram。
"-n" で ngram の N を指定できる。デフォルトは "-n 3"。
```
% ./mkii.pl -n 5 test.txt > test.txt-5.ii
% cat test.txt-5.ii
。いかがお	4
いかがおす	4
うですか?	2
おすごしで	4
かがおすご	4
...
% echo 'これはペンギンですか？' | ./searchii.pl -i test.txt-5.ii -e test.txt
これはペンギンですか？
[1,0.6364,0.3030]	1	これはペンです
```
```
% ./mkii.pl -n 2 test.txt | head
。い	    4
いか	    4
いで	    6
うで	    2
おす	    4
か?	    2,4
かが	    4
がお	    4
が悪	    6
ここ	    5
% ./mkii.pl -n 1 test.txt | head
? 2,4
。	4
い	4,6
う	2
お	4
か	2,4
が	4,6
き	3
こ	1,4,5
ご	4
```


### リランキングのみ

- rerankonly.pl : インデックスなしでリランキングのみを行うスクリプト

```
% cat test-rerankonly.txt
これはペンギンですか？
1	これはペンです
2	最近はどうですか？
3	ペンギン大好き
4	こんにちは。いかがおすごしですか？
5	ここ最近疲れ気味
6	ペンキ塗りたてで気味が悪いです

疲れた
2	最近はどうですか？
4	こんにちは。いかがおすごしですか？
5	ここ最近疲れ気味
6	ペンキ塗りたてで気味が悪いです

いい気味だ
5	ここ最近疲れ気味
6	ペンキ塗りたてで気味が悪いです

% cat test-rerankonly.txt | ./rerankonly.pl -1 0 -2 1 -autocut 0
これはペンギンですか？
[0.6364,0.3030]	1	これはペンです
[0.5455,0.1818]	4	こんにちは。いかがおすごしですか？
[0.4545,0.1667]	2	最近はどうですか？
[0.3636,0.1515]	3	ペンギン大好き
[0.3636,0.0909]	6	ペンキ塗りたてで気味が悪いです
[0.1818,0.0303]	5	ここ最近疲れ気味

疲れた
[0.6667,0.5000]	5	ここ最近疲れ気味
[0.3333,0.1667]	6	ペンキ塗りたてで気味が悪いです
[0.0000,0.0000]	2	最近はどうですか？
[0.0000,0.0000]	4	こんにちは。いかがおすごしですか？

いい気味だ
[0.6000,0.2667]	6	ペンキ塗りたてで気味が悪いです
[0.4000,0.2000]	5	ここ最近疲れ気味

```

空行で区切られたブロック単位でリランキングの処理を行う。
ブロックの先頭行がクエリとなり、他はターゲット（エントリー）。

オプション "-1", "-2", "--topn", "--sortby", "--autocut", "--show", "--similarity", "-N" は searchii.pl と同じ。

オプション "--comment-block-prefix" で処理対象外のブロックの prefix 文字列を指定できる。
```
% cat a.txt
### これは rerankonly.pl のためのテストデータです。
# どうぞよろしく
# お願いします。

いい気味だ
5	ここ最近疲れ気味
6	ペンキ塗りたてで気味が悪いです

% cat a.txt | ./rerankonly.pl -1 0 -2 1 
### これは rerankonly.pl のためのテストデータです。

いい気味だ
[0.6000,0.2667]	6	ペンキ塗りたてで気味が悪いです
[0.4000,0.2000]	5	ここ最近疲れ気味

% cat a.txt | ./rerankonly.pl -1 0 -2 1  --comment-block-prefix "###"
### これは rerankonly.pl のためのテストデータです。
# どうぞよろしく
# お願いします。

いい気味だ
[0.6000,0.2667]	6	ペンキ塗りたてで気味が悪いです
[0.4000,0.2000]	5	ここ最近疲れ気味

```


### 転置インデックスによる検索

クエリを（転置インデックスファイルに合わせた）ngram に分解。

- query: これはペンギンですか？
- ngram: これは,れはペ,はペン,ペンギ,ンギン,ギンで,ンです,ですか,すか？

それぞれの ngram をキーに転置インデックスファイル (text.txt.ii) を検索した結果：

| ngram  | IDs  |
| ------ | ---- |
| これは | 1    |
| れはペ | 1    |
| ですか | 2,4  |
| ...    | ...  |

出現した ID (サンプルでは1〜6の数字) をカウント（その頻度が hits）：

|  ID  |  hits  | hit ngrams                  | text                               |
| ---- | ------ | --------------------------- | ---------------------------------- |
|   1  |    4   | これは,れはペ,はペン,ンです | これはペンです                     |
|   2  |    2   | ですか,すか？               | こんにちは。いかがおすごしですか？ |
|   4  |    2   | ですか,すか？               | 最近はどうですか？                 |

hits が大きいほど query と近い文字列。


### リランキング時のスコア計算

リランキング時の指定項目として、
優先する処理単位 ("--sortby") と類似度計算方法 ("--similarity") の2つがある。

優先する処理単位: ngram (ccrate)  or 全ngram(vgram)。

ccrate はngramを単位に処理を行う。
デフォルトの N-gram のNは1で unigram、つまり文字である（"-N" オプションで指定できる）。
デフォルトの類似度計算方法は、query と target の一致ngram数（文字数）を query のngram数（文字数）で割ったもの (qbase)。

- query: これはペンギンですか？ (11文字)
- target: これはペンですね (8文字)
- 一致文字: こ,れ,は,ぺ,ン,で,す (7文字)
- ccrate: 7/11 = 0.6363....

vgrate は全ngram(vgram)を単位に処理を行う。
デフォルトの類似計算方法は、query と target の全ngram(vgram)の一致ngram数を query のngram数で割ったもの (qbase)。

- query: あれはペン
  - あれはペン,あれはペ,れはペン,あれは,れはペ,はペン,あれ,れは,はペ,ペン,あ,れ,は,ペ,ン (15)
- target: これはペンです
  - これはペンです,これはペンで,れはペンです,...,で,す (28)
- 一致ngram
  - は,はペ,はペン,れ,れは,れはペ,れはペン,ペ,ペン,ン (10)
- vgrate: 10/15 = 0.6666....

類似度計算方法: jaccard係数、dice係数、simpson係数。

- qbase: query と target の一致要素数を query の要素数で割る（デフォルト）
  - ランキング順は一致要素数の多い順となり、転置インデックス検索での hits と同じになる
- jaccard: query と target の一致要素数Aを query と target の要素数の合計からAを引いたもので割る
- dice: query と target の一致要素数 x 2 を query と target の要素数の合計で割る
- simpson: query と target の一致要素数を query と target の要素数のうち小さい方で割る


## nggrep (おまけ)

nggrep は、
ngram の一致数をベースとした類似度による近似文字列マッチの grep 風なよそおい版。
grep というか [agrep](https://ja.wikipedia.org/wiki/Agrep) 風な感じ。

類似度計算方法などは、前述「リランキング時のスコア計算」を参照。

"-N" オプションで、N-gram の N を指定する。"-N 0" だと全ngram(vgram)。デフォルトは "-N 2"。
"--topn" でスコア順に上位何位まで表示するか指定する。デフォルトは "--topn 1"。
"--show" でスコアも出力する。
```
% ./nggrep --show -topn 2 ペンギンです test.txt 
0.6000	 1	これはペンです
0.6000	 3	ペンギン大好き
0.4000	 6	ペンキ塗りたてで気味が悪いです
% ./nggrep -N 3 ペンギンです test.txt
3 ペンギン大好き
% ./nggrep -N 2 ペンギンです test.txt
1			 これはペンです
3			 ペンギン大好き
% ./nggrep -N 1 ペンギンです test.txt
1			 これはペンです
3			 ペンギン大好き
6			 ペンキ塗りたてで気味が悪いです
```

"-n" でマッチした行番号も出力する。
```
% ./nggrep -n -topn 2 ペンギンです test.txt 
1:1	   これはペンです
3:3	   ペンギン大好き
6:6	   ペンキ塗りたてで気味が悪いです
```

"--regstr" で文字列の正規化（英数記号の全角半角変換）を行う。
```
% echo "abxc\nａｂ１００％\nｂｃ１２％" | ./nggrep --regstr --show --topn 3 abc100%  
0.6667 ａｂ１００％
0.3333 ｂｃ１２％
0.1667 abxc
```

カラム(TSV)指定オプション "-2" は、指定しない場合は行全体が対象となる。

オプション "--similarity" は searchii.pl, rerankonly.pl と同じ。

スコアが同じ場合はファイル内での出現順に出力される。

なお、処理速度は遅い。ちょっとした調査用。

