#!/bin/bash

utt_prefixes=
max_jobs_run=30
nj=30
cmd=queue.pl

echo "$0 $@"  # Print the command line for logging

. ./path.sh
. utils/parse_options.sh

if [ $# -ne 3 ]; then
  echo "Usage: $0 <out-data> <src-ali-dir> <out-ali-dir>"
  exit 1
fi

data=$1
src_dir=$2
dir=$3

rm -rf $dir 2>/dev/null
cp -r $src_dir $dir

num_jobs=$(cat $src_dir/num_jobs)

rm -f $dir/ali_tmp.*.{ark,scp} $dir/ali.*.gz $dir/fsts.*.gz 2>/dev/null

# Copy the lattices temporarily
$cmd --max-jobs-run $max_jobs_run JOB=1:$num_jobs $dir/log/copy_alignments.JOB.log \
  copy-int-vector "ark:gunzip -c $src_dir/ali.JOB.gz |" \
  ark,scp:$dir/ali_tmp.JOB.ark,$dir/ali_tmp.JOB.scp || exit 1

# Make copies of utterances for perturbed data
for p in $utt_prefixes; do
  cat $dir/ali_tmp.*.scp | local/add_prefix_to_scp.py --prefix $p
done >$dir/ali_out.scp.tmp
cat $dir/ali_tmp.*.scp $dir/ali_out.scp.tmp | sort -k1,1 >$dir/ali_out.scp
rm -f $dir/ali_out.scp.tmp 2>/dev/null

utils/split_data.sh ${data} $nj

# Copy and dump the lattices for perturbed data
$cmd --max-jobs-run $max_jobs_run JOB=1:$num_jobs $dir/log/copy_out_alignments.JOB.log \
  copy-int-vector \
  "scp:utils/filter_scp.pl ${data}/split$nj/JOB/utt2spk $dir/ali_out.scp |" \
  "ark:| gzip -c > $dir/ali.JOB.gz" || exit 1

rm $dir/ali_tmp.* $dir/ali_out.scp

echo $nj > $dir/num_jobs
