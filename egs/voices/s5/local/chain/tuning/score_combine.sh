#!/bin/bash

# Copyright 2019  Johns Hopkins University (author: Daniel Povey)
#           2019  Yiming Wang


set -e -o pipefail

dir=exp/chain/tdnn1e2_1e4
treedir=/home/dsnyder/tree_sp
test_sets="dev eval"

# End configuration section.
echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh


for data in $test_sets; do
  (
  opts=""
  [ "$data" == "eval" ] && opts="$opts --skip-scoring true"
  local/score_combine.sh --cmd "$decode_cmd" $opts /home/dsnyder/${data}_hires $treedir/graph \
    /export/b02/hxu/kaldi-voices/egs/voices/s5/exp/chain/tdnn1e2/decode_${data}_rnnlm_1f_back_0.3_4_0.3 /export/b02/hxu/kaldi-voices/egs/voices/s5/exp/chain/tdnn1e4/decode_${data}_rnnlm_1f_back_0.3_4_0.3 $dir/decode_${data}_rnnlm || exit 1

  [ "$data" == "dev" ] && grep Sum $dir/decode_${data}_rnnlm/score_*/${data}_hires.ctm.filt.sys | utils/best_wer.sh; 2>/dev/null || true
  ) &
done
wait

exit 0

