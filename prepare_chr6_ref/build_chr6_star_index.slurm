#!/bin/bash
#SBATCH --job-name=CHR6-STAR-INDEX
#SBATCH --partition=short
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=R-%x.%j.out   # Standard output and error log

# Build the chr6-only STAR index needed to align RNA samples (oncoanalyser runs STAR 2.7.3a)
# Splice junctions are taken from the HMF GRCh38 STAR index (gencode v38, the one oncoanalyser uses by default),
# keeping only chr6. A GTF can be given instead (filtered to chr6).
# RUN WITH (from the repo root):
# sbatch prepare_chr6_ref/build_chr6_star_index.slurm
# sbatch prepare_chr6_ref/build_chr6_star_index.slurm /path/to/gencode.annotation.gtf

set -euo pipefail

# ONLY CHANGE IF NEEDED
JUNCTIONS=${1:-/mnt/bioinfnas/immuno/Jonatan/References/hmftools_ref/ref_genome/v2.0.0/38/star_index-gencode_38-2.7.3a} # HMF STAR index dir or GTF
CHR6_REF_DIR=${2:-/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/oncoanalyser-hla-typing/chr6_reference}
SINGULARITY_CACHE=${3:-/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/singularity_images}

CHR_NAME="chr6"
SJDB_OVERHANG=200 # Same as the HMF STAR index
CHR6_FASTA="${CHR6_REF_DIR}/chr6_only.hg38.fasta"
STAR_INDEX_DIR="${CHR6_REF_DIR}/star_index"
BUILD_DIR="${CHR6_REF_DIR}/star_index_build_${SLURM_JOB_ID}"
# Same STAR version and image name as oncoanalyser's STAR_ALIGN, so Nextflow reuses the image
STAR_IMG="${SINGULARITY_CACHE}/depot.galaxyproject.org-singularity-star-2.7.3a--0.img"

if [[ ! -f "${CHR6_FASTA}" ]]; then
    echo "ERROR: Chromosome 6 reference not found at ${CHR6_FASTA}"
    exit 1
fi

if [[ -f "${STAR_INDEX_DIR}/SA" ]]; then
    echo "ERROR: STAR index already exists in ${STAR_INDEX_DIR}"
    echo "Remove or rename it first to rebuild"
    exit 1
fi

if [[ ! -f "${STAR_IMG}" ]]; then
    echo "STAR image not found, pulling it to ${STAR_IMG}"
    mkdir -p "${SINGULARITY_CACHE}"
    singularity pull --name "$(basename "${STAR_IMG}")" --dir "${SINGULARITY_CACHE}" \
        https://depot.galaxyproject.org/singularity/star:2.7.3a--0
fi

mkdir -p "${STAR_INDEX_DIR}" "${BUILD_DIR}"

# Keep only chr6 junctions (from an existing STAR index) or chr6 transcripts (from a GTF)
if [[ -d "${JUNCTIONS}" ]]; then
    awk -v chr="${CHR_NAME}" '$1==chr' "${JUNCTIONS}/sjdbList.out.tab" > "${BUILD_DIR}/sjdbList.${CHR_NAME}.tab"
    SJDB_ARGS="--sjdbFileChrStartEnd ${BUILD_DIR}/sjdbList.${CHR_NAME}.tab"
    N_INPUT=$(wc -l < "${BUILD_DIR}/sjdbList.${CHR_NAME}.tab")
    echo "Junctions: ${N_INPUT} ${CHR_NAME} junctions from ${JUNCTIONS}/sjdbList.out.tab"
elif [[ "${JUNCTIONS}" == *.gtf ]]; then
    awk -F'\t' -v chr="${CHR_NAME}" '$1==chr' "${JUNCTIONS}" > "${BUILD_DIR}/annotation.${CHR_NAME}.gtf"
    SJDB_ARGS="--sjdbGTFfile ${BUILD_DIR}/annotation.${CHR_NAME}.gtf"
    echo "Junctions: ${CHR_NAME} transcripts from ${JUNCTIONS}"
else
    echo "ERROR: ${JUNCTIONS} is neither a STAR index directory nor a .gtf file"
    exit 1
fi

# --genomeSAindexNbases 12: min(14, log2(171 Mb)/2 - 1), as recommended by STAR for a single chromosome
echo "Building STAR index in ${STAR_INDEX_DIR}..."
singularity exec --bind "${CHR6_REF_DIR}" "${STAR_IMG}" \
    STAR \
        --runMode genomeGenerate \
        --runThreadN ${SLURM_CPUS_PER_TASK} \
        --genomeDir "${STAR_INDEX_DIR}" \
        --genomeFastaFiles "${CHR6_FASTA}" \
        --genomeSAindexNbases 12 \
        --sjdbOverhang ${SJDB_OVERHANG} \
        ${SJDB_ARGS} \
        --limitGenomeGenerateRAM $(( (SLURM_MEM_PER_NODE - 1024) * 1024 * 1024 )) \
        --outTmpDir "${BUILD_DIR}/_STARtmp" \
        --outFileNamePrefix "${STAR_INDEX_DIR}/"

for f in Genome SA SAindex chrName.txt sjdbList.out.tab; do
    if [[ ! -s "${STAR_INDEX_DIR}/${f}" ]]; then
        echo "ERROR: ${STAR_INDEX_DIR}/${f} missing, check ${STAR_INDEX_DIR}/Log.out"
        exit 1
    fi
done

rm -r "${BUILD_DIR}"

echo "STAR index complete: ${STAR_INDEX_DIR}"
echo "Contigs: $(tr '\n' ' ' < "${STAR_INDEX_DIR}/chrName.txt")"
echo "Junctions inserted: $(wc -l < "${STAR_INDEX_DIR}/sjdbList.out.tab")"
