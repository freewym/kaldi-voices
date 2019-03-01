#!/bin/bash

# Copyright 2019  Yiming Wang
#           2019  Johns Hopkins University (author: Daniel Povey)
# Apache 2.0

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <src-dir> <dst-dir>"
  echo "e.g.: $0  /export/corpora/SRI/VOiCES_2019_challenge data"
  exit 1
fi

export LC_ALL=C

src=$1
dst=$2

[ ! -d $src ] && echo "$0: no such directory $src" && exit 1;

mkdir -p $dst/train || exit 1;
wav_scp=$dst/train/wav.scp; [[ -f "$wav_scp" ]] && rm $wav_scp
trans=$dst/train/text; [[ -f "$trans" ]] && rm $trans
utt2spk=$dst/train/utt2spk; [[ -f "$utt2spk" ]] && rm $utt2spk

train_dir=$src/Training_Data/Automatic_Speech_Recognition/ASR_train
train_wav_list=$train_dir/modified-train-clean-80.wav.list
[ ! -f $train_wav_list ] && echo "$0: no such file $train_wav_list" && exit 1;
cat $train_wav_list | awk '{print $0, $0}' | \
  awk -v "dir=$train_dir" '{n=split($1,a,"/"); printf "%s sox -r 16k -b 16 %s -t wav - |\n", a[n], dir"/"$2}' | \
  awk '{sub(/\.wav/, "", $1);print}' | sort -k1,1 >$wav_scp
cat $wav_scp | awk '{split($1,a,"-");print $1,a[1]"-"a[2]}' >$utt2spk
cat $train_dir/modified-train-clean-80.trans.txt | sort -k1,1 >$trans

mkdir -p $dst/dev || exit 1;
wav_scp=$dst/dev/wav.scp; [[ -f "$wav_scp" ]] && rm $wav_scp
trans=$dst/dev/text; [[ -f "$trans" ]] && rm $trans
utt2spk=$dst/dev/utt2spk; [[ -f "$utt2spk" ]] && rm $utt2spk

dev_dir=$src/Development_Data/Automatic_Speech_Recognition/ASR_dev.v2
find -L $dev_dir/ -mindepth 5 -maxdepth 5 -iname '*.wav' | \
  awk '{print $0, $0}' | \
  awk '{n=split($1,a,"/"); printf "%s sox -r 16k -b 16 %s -t wav - |\n", a[n], $2}' |\
  awk '{sub(/\.wav/, "", $1);print}' | sort -k1,1 >$wav_scp
cat $wav_scp | awk '{print $1,$1}' >$utt2spk
cat $dev_dir/dev.subset-challenge.refs | sort -k1,1 >$trans

mkdir -p $dst/eval || exit 1;
wav_scp=$dst/eval/wav.scp; [[ -f "$wav_scp" ]] && rm $wav_scp
utt2spk=$dst/eval/utt2spk; [[ -f "$utt2spk" ]] && rm $utt2spk

eval_dir=$src/Evaluation_Data/Automatic_Speech_Recognition/ASR_eval
find -L $eval_dir/ -mindepth 1 -maxdepth 1 -iname '*.wav' | \
  awk '{print $0, $0}' | \
  awk '{n=split($1,a,"/"); printf "%s sox -r 16k -b 16 %s -t wav - |\n", a[n], $2}' |\
  awk '{sub(/\.wav/, "", $1);print}' | sort -k1,1 >$wav_scp
cat $wav_scp | awk '{print $1,$1}' >$utt2spk

for dset in train dev eval; do
  utt2spk=$dst/$dset/utt2spk
  spk2utt=$dst/$dset/spk2utt
  utils/utt2spk_to_spk2utt.pl <$utt2spk >$spk2utt || exit 1

  if [ "$dset" != "eval" ]; then
    ntrans=$(wc -l <$dst/$dset/text)
    nutt2spk=$(wc -l <$dst/$dset/utt2spk)
    ! [ "$ntrans" -eq "$nutt2spk" ] && \
      echo "Inconsistent #transcripts($ntrans) and #utt2spk($nutt2spk) in $dst/$dset" && exit 1;
  fi

  utt2dur=$dst/$dset/utt2dur; [[ -f "$utt2dur" ]] && rm $utt2dur
  utils/data/get_utt2dur.sh $dst/$dset 1>&2 || exit 1

  [ "$dset" == "dev" ] && paste -d' ' <(cat $dst/$dset/utt2dur | awk '{print $1" 1 "$1" 0.00 "$2}') <(cut -d' ' -f2- $dst/$dset/text) >$dst/$dset/stm
  [ "$dset" == "dev" ] && cp /export/a16/dsnyder/english.glm $dst/$dset/glm

  opts=""
  [ "$dset" == "eval" ] && opts="$opts --no-text"
  utils/validate_data_dir.sh --no-feats $opts $dst/$dset || exit 1;

  echo "$0: successfully prepared data in $dst/$dset"
done

exit 0
