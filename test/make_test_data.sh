#!/bin/bash
# Rebuild the MDAMB231 HLA test FASTQs from a GRCh38 BAM of the MDA-MB-231 cell line (WGS, REDUX-processed).
# Only reads in the LILAC HLA regions are kept, written as complete read pairs.
# RUN WITH:
# bash test/make_test_data.sh [/path/to/MDAMB231.redux.bam]
# (default: accessory/MDAMB231.redux.bam, a local file not in git, like the samtools image pulled to accessory/)
# Optional subsampling, e.g. keep 50% of read pairs:
# FRACTION=0.5 bash test/make_test_data.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BAM=${1:-${SCRIPT_DIR}/../accessory/MDAMB231.redux.bam}  # indexed BAM (.bai next to it)
if [[ ! -f "${BAM}" ]]; then
    echo "ERROR: BAM not found: ${BAM}. Give the MDA-MB-231 GRCh38 BAM as first argument"
    exit 1
fi
BAM=$(realpath "${BAM}")
cd "${SCRIPT_DIR}"

HLA_BED="${SCRIPT_DIR}/../hmf_data_min/misc/lilac/hla.38.bed"  # LILAC HLA gene regions
PAD=1000                                                        # bp added on each side of the LILAC regions
FRACTION=${FRACTION:-}                                          # fraction of read pairs to keep, empty = all
OUT_PREFIX="MDAMB231_hla"

# Use samtools from PATH if available, otherwise from the container used for reference preparation.
# The image is pulled once to a local SIF file (reused on later runs) instead of being converted on every call
SAMTOOLS_SIF=${SAMTOOLS_SIF:-${SCRIPT_DIR}/../accessory/samtools_1.21.sif}
if command -v samtools >/dev/null 2>&1; then
    SAMTOOLS="samtools"
else
    if [[ ! -f "${SAMTOOLS_SIF}" ]]; then
        singularity pull "${SAMTOOLS_SIF}" docker://staphb/samtools:1.21
    fi
    SAMTOOLS="singularity exec --bind $(dirname "${BAM}") ${SAMTOOLS_SIF} samtools"
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

# Regions: LILAC regions padded by PAD bp
awk -v pad=${PAD} 'BEGIN{OFS="\t"} {s=$2-pad; if (s<0) s=0; print $1, s, $3+pad}' "${HLA_BED}" > "${TMP_DIR}/regions.bed"

# Reproducible subsample (seed 42) on read names, so both mates are kept or dropped together
SUBSAMPLE_ARGS=""
if [[ -n "${FRACTION}" ]]; then
    SUBSAMPLE_ARGS="-s 42${FRACTION#0}"
fi

# Primary, non-duplicate alignments only (-F 0xD00), each read once even where regions overlap (-M),
# grouped by name and written as complete pairs (singletons dropped)
${SAMTOOLS} view -u -M -F 0xD00 ${SUBSAMPLE_ARGS} -L "${TMP_DIR}/regions.bed" "${BAM}" \
    | ${SAMTOOLS} collate -u -O - "${TMP_DIR}/collate" \
    | ${SAMTOOLS} fastq -n \
        -1 "${OUT_PREFIX}_R1.fastq.gz" \
        -2 "${OUT_PREFIX}_R2.fastq.gz" \
        -0 /dev/null -s /dev/null -

echo "Read pairs: $(( $(zcat "${OUT_PREFIX}_R1.fastq.gz" | wc -l) / 4 ))"
ls -lh "${OUT_PREFIX}"_R*.fastq.gz
