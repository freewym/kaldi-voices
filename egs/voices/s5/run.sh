#!/bin/bash


# Set this to somewhere where you want to put your data, or where
# someone else has already put it.  You'll want to change this
# if you're not on the CLSP grid.
data=/export/corpora/SRI/VOiCES_2019_challenge

# base url for downloads.
lm_url=www.openslr.org/resources/11
stage=1

. ./cmd.sh
. ./path.sh
. parse_options.sh

# you might not want to do this for interactive shells.
set -e


if [ $stage -le 1 ]; then
  # format the data as Kaldi data directories
  local/data_prep.sh $data data
fi

if [ $stage -le 2 ]; then
  # download the LM resources
  local/download_lm.sh $lm_url data/local/lm
fi

if [ $stage -le 3 ]; then
  # when the "--stage 3" option is used below we skip the G2P steps, and use the
  # lexicon we have already downloaded from openslr.org/11/
  local/prepare_dict.sh --stage 3 --nj 30 --cmd "$train_cmd" \
   data/local/lm data/local/lm data/local/dict_nosp
  utils/validate_dict_dir.pl data/local/dict_nosp

  utils/prepare_lang.sh data/local/dict_nosp \
   "<UNK>" data/local/lang_tmp_nosp data/lang_nosp
  utils/validate_lang.pl data/lang_nosp
fi

if [ $stage -le 4 ]; then
  local/train_lms_srilm.sh --oov-symbol "<UNK>" --words-file data/lang_nosp/words.txt \
    data data/lm
  utils/format_lm.sh data/lang_nosp data/lm/lm.gz \
    data/local/dict_nosp/lexiconp.txt data/lang_nosp_test
fi

if [ $stage -le 5 ]; then
  for dset in train dev eval; do
    dir=data/$dset
    utils/fix_data_dir.sh $dir
    steps/make_mfcc.sh --cmd "$train_cmd" --nj 16 $dir
    steps/compute_cmvn_stats.sh $dir
    utils/fix_data_dir.sh $dir
    opts=""
    [ "$dset" == "eval" ] && opts="$opts --no-text"
    utils/validate_data_dir.sh $opts $dir
  done
fi

if [ $stage -le 6 ]; then
  # Make some small data subsets for early system-build stages.  Note, there are 29k
  # utterances in the train_clean_100 directory which has 100 hours of data.
  # For the monophone stages we select the shortest utterances, which should make it
  # easier to align the data from a flat start.

  utils/subset_data_dir.sh --shortest data/train 2000 data/train_2kshort
  utils/subset_data_dir.sh data/train 5000 data/train_5k
  utils/subset_data_dir.sh data/train 10000 data/train_10k
fi

if [ $stage -le 7 ]; then
  # train a monophone system
  steps/train_mono.sh --boost-silence 1.25 --nj 20 --cmd "$train_cmd" \
    data/train_2kshort data/lang_nosp exp/mono

  # decode using the monophone model
  (
    utils/mkgraph.sh data/lang_nosp_test exp/mono exp/mono/graph_nosp
    for test in dev; do
      steps/decode.sh --nj 30 --cmd "$decode_cmd" exp/mono/graph_nosp \
        data/$test exp/mono/decode_nosp_$test
    done
  )&
fi

if [ $stage -le 8 ]; then
  steps/align_si.sh --boost-silence 1.25 --nj 10 --cmd "$train_cmd" \
    data/train_5k data/lang_nosp exp/mono exp/mono_ali_5k

  # train a first delta + delta-delta triphone system on a subset of 5000 utterances
  steps/train_deltas.sh --boost-silence 1.25 --cmd "$train_cmd" \
    2000 10000 data/train_5k data/lang_nosp exp/mono_ali_5k exp/tri1

  # decode using the tri1 model
  (
    utils/mkgraph.sh data/lang_nosp_test exp/tri1 exp/tri1/graph_nosp
    for test in dev; do
      steps/decode.sh --nj 30 --cmd "$decode_cmd" exp/tri1/graph_nosp \
        data/$test exp/tri1/decode_nosp_$test
    done
  )&
fi

if [ $stage -le 9 ]; then
  steps/align_si.sh --nj 10 --cmd "$train_cmd" \
    data/train_10k data/lang_nosp exp/tri1 exp/tri1_ali_10k

  # train an LDA+MLLT system.
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
    --splice-opts "--left-context=3 --right-context=3" 2500 15000 \
    data/train_10k data/lang_nosp exp/tri1_ali_10k exp/tri2

  # decode using the LDA+MLLT model
  (
    utils/mkgraph.sh data/lang_nosp_test exp/tri2 exp/tri2/graph_nosp
    for test in dev; do
      steps/decode.sh --nj 30 --cmd "$decode_cmd" exp/tri2/graph_nosp \
        data/$test exp/tri2/decode_nosp_$test
    done
  )&
fi

if [ $stage -le 10 ]; then
  # Align a 10k utts subset using the tri2 model
  steps/align_si.sh --nj 10 --cmd "$train_cmd" --use-graphs true \
    data/train_10k data/lang_nosp exp/tri2 exp/tri2_ali_10k

  # Train tri3, which is LDA+MLLT+SAT
  steps/train_sat.sh --cmd "$train_cmd" 2500 15000 \
    data/train_10k data/lang_nosp exp/tri2_ali_10k exp/tri3

  # decode using the tri3 model
  (
    utils/mkgraph.sh data/lang_nosp_test exp/tri3 exp/tri3/graph_nosp
    for test in dev; do
      steps/decode_fmllr.sh --nj 30 --cmd "$decode_cmd" \
        exp/tri3/graph_nosp data/$test exp/tri3/decode_nosp_$test
    done
  )&
fi

if [ $stage -le 11 ]; then
  # align the entire train subset using the tri3 model
  steps/align_fmllr.sh --nj 20 --cmd "$train_cmd" \
    data/train data/lang_nosp exp/tri3 exp/tri3_ali

  # train another LDA+MLLT+SAT system on the entire set
  steps/train_sat.sh  --cmd "$train_cmd" 4200 40000 \
    data/train data/lang_nosp exp/tri3_ali exp/tri4

  # decode using the tri4 model
  (
    utils/mkgraph.sh data/lang_nosp_test exp/tri4 exp/tri4/graph_nosp
    for test in dev; do
      steps/decode_fmllr.sh --nj 30 --cmd "$decode_cmd" \
        exp/tri4/graph_nosp data/$test exp/tri4/decode_nosp_$test
    done
  )&
fi

if [ $stage -le 12 ]; then
  # Now we compute the pronunciation and silence probabilities from training data,
  # and re-create the lang directory.
  steps/get_prons.sh --cmd "$train_cmd" data/train data/lang_nosp exp/tri4
  utils/dict_dir_add_pronprobs.sh --max-normalize true \
    data/local/dict_nosp \
    exp/tri4/pron_counts_nowb.txt exp/tri4/sil_counts_nowb.txt \
    exp/tri4/pron_bigram_counts_nowb.txt data/local/dict

  utils/prepare_lang.sh data/local/dict "<UNK>" data/local/lang_tmp data/lang
  utils/format_lm.sh data/lang data/lm/lm.gz \
    data/local/dict/lexiconp.txt data/lang_test

  # decode using the tri4 model with pronunciation and silence probabilities
  (
    utils/mkgraph.sh data/lang_test exp/tri4 exp/tri4/graph
    for test in dev; do
      steps/decode_fmllr.sh --nj 30 --cmd "$decode_cmd" \
        exp/tri4/graph data/$test exp/tri4/decode_$test
    done
  )&
fi

if [ $stage -le 13 ]; then
  # align train using the tri4 model
  steps/align_fmllr.sh --nj 30 --cmd "$train_cmd" \
    data/train data/lang exp/tri4 exp/tri4_ali
fi
wait

if [ $stage -le 14 ]; then
  # data augmentation
  if [ ! -d "RIRS_NOISES" ]; then
    # Download the package that includes the real RIRs, simulated RIRs, isotropic noises and point-source noises
    wget --no-check-certificate http://www.openslr.org/resources/28/rirs_noises.zip
    unzip rirs_noises.zip
  fi

  # Prepare mx6 corpus for augmenting data with babble speech
  local/make_mx6.sh /export/corpora/LDC/LDC2013S03/mx6_speech data
  steps/make_mfcc.sh --nj 16 --cmd "$train_cmd" --write-utt2num-frames true data/mx6_mic
  utils/fix_data_dir.sh data/mx6_mic
  awk -v frame_shift=0.01 '{print $1, $2*frame_shift;}' data/mx6_mic/utt2num_frames > data/mx6_mic/reco2dur
  
  # Prepare the MUSAN corpus, which consists of music, speech, and noise
  # suitable for augmentation.
  local/make_musan.sh /export/corpora/JHU/musan data

  # Get the duration of the MUSAN recordings.  This will be used by the
  # script augment_data_dir_for_asr.py.
  for name in noise music; do
    utils/data/get_reco2dur.sh data/musan_${name}
  done

  # Augment with musan_noise
  steps/data/augment_data_dir_for_asr.py --utt-prefix "noise" --fg-interval 1 --fg-snrs "15:10:5:0" --fg-noise-dir "data/musan_noise" data/train data/train_noise
  cat data/train/utt2dur | awk '{print "noise_"$0}' >data/train_noise/utt2dur
  #utils/data/get_utt2dur.sh data/train_noise
  # Augment with musan_music
  steps/data/augment_data_dir_for_asr.py --utt-prefix "music" --bg-snrs "15:10:8:5" --num-bg-noises "1" --bg-noise-dir "data/musan_music" data/train data/train_music
  cat data/train/utt2dur | awk '{print "music_"$0}' >data/train_music/utt2dur
  #utils/data/get_utt2dur.sh data/train_music
  # Augment with mx6_speech
  steps/data/augment_data_dir_for_asr.py --utt-prefix "babble" --bg-snrs "20:17:15:13" --num-bg-noises "3:4:5:6:7" --bg-noise-dir "data/mx6_mic" data/train data/train_babble
  cat data/train/utt2dur | awk '{print "babble_"$0}' >data/train_babble/utt2dur
  #utils/data/get_utt2dur.sh data/train_babble

  # Make a version with reverberated speech
  rvb_opts=()
  rvb_opts+=(--rir-set-parameters "0.5, RIRS_NOISES/simulated_rirs/smallroom/rir_list")
  rvb_opts+=(--rir-set-parameters "0.5, RIRS_NOISES/simulated_rirs/mediumroom/rir_list")
  # Make a reverberated version of the train set.  Note that we don't add any
  # additive noise here.
  seed=0
  for name in noise music babble; do
    steps/data/reverberate_data_dir.py \
      "${rvb_opts[@]}" \
      --speech-rvb-probability 1 \
      --prefix "rev" \
      --pointsource-noise-addition-probability 0 \
      --isotropic-noise-addition-probability 0 \
      --num-replications 1 \
      --source-sampling-rate 16000 \
      --random-seed $seed \
      data/train_$name data/train_${name}_reverb
    cat data/train_$name/utt2dur | awk '{print "rev1_"$0}' >data/train_${name}_reverb/utt2dur
    seed=$((seed + 1))
  done
fi

if [ $stage -le 15 ]; then
  # Now make MFCC features
  for name in noise music babble; do
    steps/make_mfcc.sh --nj 16 --cmd "$train_cmd" \
      data/train_${name}_reverb || exit 1;
    steps/compute_cmvn_stats.sh data/train_${name}_reverb
    utils/fix_data_dir.sh data/train_${name}_reverb
    utils/validate_data_dir.sh data/train_${name}_reverb
  done
fi
exit 0

#if [ $stage -le 14 ]; then
#  # train and test nnet3 tdnn models on the entire data with data-cleaning.
#  local/chain/run_tdnn.sh # set "--stage 11" if you have already run local/nnet3/run_tdnn.sh
#fi

# Wait for decodings in the background
wait
exit 0;
