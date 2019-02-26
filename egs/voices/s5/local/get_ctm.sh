#!/bin/bash

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
lang_or_graph=$2
decode_dir=$3

for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
  for LMWT in $(seq $min_lmwt $max_lmwt); do
    steps/get_ctm_fast.sh --cmd "$decode_cmd" --frame-shift 0.03 \
      $data $lang_or_graph $decode_dir $decode_dir/score_${LMWT}_$wip
  done
done



