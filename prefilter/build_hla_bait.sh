#!/bin/bash
# Builds prefilter/hla_bait.fa.gz, the k-mer bait used by hla_prefilter.slurm to keep only HLA reads:
#   - the LILAC HLA gene regions (hmf_data_min/misc/lilac/hla.38.bed) padded by PAD bp, from the chr6 reference
#   - every LILAC allele nucleotide sequence (hla_ref_nucleotide_sequences.csv), so reads of alleles far from the
#     reference and RNA reads across exon junctions also match
# Light (< 1 min), but reads the 170 Mb chr6 FASTA. RUN WITH (from the repo root):
# srun -p short -c 1 --mem=2G -t 00:10:00 bash prefilter/build_hla_bait.sh
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CHR6_FASTA=${CHR6_FASTA:-/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/oncoanalyser-hla-typing/chr6_reference/chr6_only.hg38.fasta}
LILAC_DIR="${REPO_DIR}/hmf_data_min/misc/lilac"
OUT="${REPO_DIR}/prefilter/hla_bait.fa.gz"
PAD=1000    # bp added on each side of the LILAC regions (as in accessory/make_test_data.sh)
MIN_LEN=27  # bait pieces shorter than the bbduk k-mer length can't match anything

# samtools from PATH, otherwise from the samtools image
SAMTOOLS_IMG=${SAMTOOLS_IMG:-/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/singularity_images/depot.galaxyproject.org-singularity-samtools-1.21--h50ea8bc_0.img}
if command -v samtools >/dev/null 2>&1; then
    SAMTOOLS="samtools"
else
    SAMTOOLS="singularity exec -B /mnt ${SAMTOOLS_IMG} samtools"
fi

{
    # 1. Padded LILAC regions (BED is 0-based, samtools regions 1-based)
    awk -v pad=${PAD} '{s = $2 + 1 - pad; if (s < 1) s = 1; print $1 ":" s "-" ($3 + pad)}' "${LILAC_DIR}/hla.38.bed" \
        | xargs ${SAMTOOLS} faidx "${CHR6_FASTA}"
    # 2. Allele sequences: '.' (deletion) and '|' (insertion marks) are alignment characters, removed;
    #    '*' (unknown sequence) splits the allele into pieces, pieces < MIN_LEN are dropped
    awk -F, -v min=${MIN_LEN} 'NR > 1 {
        seq = $2; gsub(/[.|]/, "", seq)
        n = split(seq, parts, /[^ACGT]+/)
        for (i = 1; i <= n; i++) if (length(parts[i]) >= min) print ">" $1 "_" i "\n" parts[i]
    }' "${LILAC_DIR}/hla_ref_nucleotide_sequences.csv"
} | gzip -c > "${OUT}"

echo "Bait written to ${OUT}: $(zcat "${OUT}" | grep -c '>') sequences, $(zcat "${OUT}" | grep -v '>' | tr -d '\n' | wc -c) bp"
