#!/bin/bash
# Copyright 2019  Johns Hopkins University (Author: Daniel Povey)
#           2019  Yiming Wang
# Apache 2.0

cmd=run.pl
decode_mbr=true
word_ins_penalty=0.0,0.5,1.0
min_lmwt=7
max_lmwt=17

echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

if [ $# -ne 3 ]; then
  echo "Usage: $0 <data> <lang-or-graph> <decode-dir>"
  exit 1
fi

data=$1
lang=$2
dir=$3

model=$dir/../final.mdl # assume model one level up from decoding dir.

for f in $lang/words.txt $lang/phones/word_boundary.int $model $dir/lat.1.gz; do
  [ ! -f $f ] && echo "$0: expecting file $f to exist" && exit 1;
done

name=`basename $data`

mkdir -p $dir/scoring/log

for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
  (
  $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/get_ctm.LMWT.${wip}.log \
    mkdir -p $dir/score_LMWT_${wip}/ '&&' \
    ACWT=\`perl -e \"print 1.0/LMWT\;\"\` '&&' \
    lattice-add-penalty --word-ins-penalty=$wip "ark:gunzip -c $dir/lat.*.gz|" ark:- \| \
    lattice-align-words $lang/phones/word_boundary.int $model ark:- ark:- \| \
    lattice-to-ctm-conf --decode-mbr=$decode_mbr --acoustic-scale=\$ACWT  ark:- - \| \
    utils/int2sym.pl -f 5 $lang/words.txt \
    '>' $dir/score_LMWT_${wip}/$name.ctm || exit 1;
  ) &
done
wait

exit 0
