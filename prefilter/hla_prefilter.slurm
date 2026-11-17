#!/bin/bash
#SBATCH --job-name=HLA-PREFILTER
#SBATCH --partition=short
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=02:00:00
#SBATCH --output=R-%x.%A_%a.out

# Keeps only the read pairs with an HLA k-mer (either mate) from one FASTQ pair: line SLURM_ARRAY_TASK_ID of
# <fastq_dir>/tasks.tsv (from prefilter_input.py). Writes <prefix>_R1/R2.fq.gz and <prefix>.counts.tsv to <fastq_dir>.
# Submitted by the RUN scripts as a job array, by hand:
# sbatch --array=1-<n>%5 hla_prefilter.slurm <fastq_dir> <repo>/prefilter/hla_bait.fa.gz
set -euo pipefail

FASTQ_DIR=$1
BAIT=$2
# BBMap 39.18 (bbduk + pigz), the image nf-core/bbsplit uses
BBMAP_IMG=${BBMAP_IMG:-/mnt/bioinfnas/immuno/plevy/proj/pdx/singularity_images/community-cr-prod.seqera.io-docker-registry-v2-blobs-sha256-5a-5aae5977ff9de3e01ff962dc495bfa23f4304c676446b5fdf2de5c7edfa2dc4e-data.img}
K=27

read -r R1 R2 PREFIX < <(sed -n "${SLURM_ARRAY_TASK_ID}p" "${FASTQ_DIR}/tasks.tsv")
OUT="${FASTQ_DIR}/${PREFIX}"
if [[ -s "${OUT}.counts.tsv" ]]; then
    echo "${PREFIX} already filtered, skipping"
    exit 0
fi
echo "${PREFIX}: ${R1} ${R2}"

# outm/outm2: pairs where either mate shares a K-mer with the bait (both mates kept); non-matching reads are discarded.
# Written to .tmp names first, so an interrupted task is redone (counts.tsv marks a finished one)
singularity exec -B /mnt "${BBMAP_IMG}" bbduk.sh \
    in="${R1}" in2="${R2}" ref="${BAIT}" k=${K} \
    outm="${OUT}_R1.tmp.fq.gz" outm2="${OUT}_R2.tmp.fq.gz" \
    threads=${SLURM_CPUS_PER_TASK} -Xmx6g zl=4 2>&1 | tee "${OUT}.bbduk.log"

mv "${OUT}_R1.tmp.fq.gz" "${OUT}_R1.fq.gz"
mv "${OUT}_R2.tmp.fq.gz" "${OUT}_R2.fq.gz"
# bbduk counts reads (2 per pair): "Input: N reads" and "Contaminants: M reads" (= matched, written to outm)
reads_in=$(awk '/^Input:/{print $2}' "${OUT}.bbduk.log")
reads_kept=$(awk '/^Contaminants:/{print $2}' "${OUT}.bbduk.log")
printf "prefix\tpairs_in\tpairs_kept\tpercent_kept\n%s\t%d\t%d\t%.4f\n" "${PREFIX}" $((reads_in / 2)) $((reads_kept / 2)) \
    "$(awk -v a=${reads_kept} -v b=${reads_in} 'BEGIN{print 100 * a / b}')" > "${OUT}.counts.tsv"
cat "${OUT}.counts.tsv"
