#!/bin/bash

FASTQ1=$1
FASTQ2=${FASTQ1/R1_001/R2_001}
SAMPLE=$(basename $FASTQ1 .fastq.gz)
DIR=$(pwd)


cat <<EOF
#BSUB -L /bin/bash
#BSUB -W 50:00
#BSUB -n 4
#BSUB -R "span[ptile=4]"
#BSUB -M 64000
#BSUB -e $DIR/logs/%J.err
#BSUB -o $DIR/logs/%J.out
#BSUB -J $SAMPLE


cd $DIR
module load python/2.7.15
export https_proxy=http://croz9k:password@bmiproxyp.chmcres.cchmc.org:80

gdc-client download -m gdc_manifest.2025-07-21.144705.txt --config my-dtt-config.dtt -t gdc-user-token.2025-07-21T18_48_55.358Z.txt

EOF
#gdc-client-0.sh | bsub
