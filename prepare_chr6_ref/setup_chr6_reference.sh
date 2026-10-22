#!/bin/bash

# Script to create chromosome 6-only reference genome for nf-core/oncoanalyser
# This script extracts chromosome 6 from a full reference genome and creates the necessary indexes
# Uses Docker containers for all tools since they're not installed on the cluster

set -euo pipefail

# Configuration
FULL_REF_FASTA="${1:-/mnt/bioinfnas/immuno/Jonatan/References/hmftools_ref/ref_genome/v2.0.0/38/GRCh38_masked_exclusions_alts_hlas.fasta}"  # Update this path
CHR6_REF_DIR="${2:-chr6_reference}"
GENOME_BUILD="${3:-hg38}"  # hg38 or hg19

# Docker images
SAMTOOLS_IMAGE="staphb/samtools:1.21"
BWA_IMAGE="biocontainers/bwa:v0.7.17_cv1"
BWAMEM2_IMAGE="quay.io/biocontainers/bwa-mem2:2.3--he70b90d_0"
PICARD_IMAGE="broadinstitute/picard:3.4.0"
GATK_IMAGE="broadinstitute/gatk:4.6.1.0"

# Create output directory
mkdir -p "${CHR6_REF_DIR}"
cd "${CHR6_REF_DIR}"

# Get absolute paths for Docker mounting
FULL_REF_FASTA_ABS=$(realpath "${FULL_REF_FASTA}")
WORK_DIR=$(pwd)

echo "Creating chromosome 6-only reference genome using Docker containers..."
echo "Input reference: ${FULL_REF_FASTA_ABS}"
echo "Output directory: ${WORK_DIR}"
echo "Genome build: ${GENOME_BUILD}"

# Step 1: Extract chromosome 6 from reference FASTA
CHR6_FASTA="chr6_only.${GENOME_BUILD}.fasta"

# Different chromosome naming conventions
if [[ "${GENOME_BUILD}" == "hg38" ]]; then
    CHR_NAME="chr6"  # UCSC naming
    # CHR_NAME="6"   # Uncomment if using Ensembl naming (1,2,3... instead of chr1,chr2,chr3...)
else
    CHR_NAME="6"     # GRCh37 typically uses numeric naming
fi

echo "Extracting chromosome ${CHR_NAME} using samtools in Docker..."
docker run --rm \
    -v "${WORK_DIR}:${WORK_DIR}" \
    -v "$(dirname ${FULL_REF_FASTA_ABS}):$(dirname ${FULL_REF_FASTA_ABS})" \
    -w "${WORK_DIR}" \
    ${SAMTOOLS_IMAGE} \
    samtools faidx "${FULL_REF_FASTA_ABS}" "${CHR_NAME}" > "${CHR6_FASTA}"

# Step 2: Create FASTA index
echo "Creating FASTA index using samtools in Docker..."
docker run --rm \
    -v "${WORK_DIR}:${WORK_DIR}" \
    -w "${WORK_DIR}" \
    ${SAMTOOLS_IMAGE} \
    samtools faidx "${CHR6_FASTA}"

# Step 3: Create sequence dictionary
echo "Creating sequence dictionary using Picard in Docker..."
docker run --rm \
    -v "${WORK_DIR}:${WORK_DIR}" \
    -w "${WORK_DIR}" \
    ${PICARD_IMAGE} \
    java -jar /usr/picard/picard.jar CreateSequenceDictionary \
    REFERENCE="${CHR6_FASTA}" \
    OUTPUT="${CHR6_FASTA%.fasta}.dict"

# Step 4: Create BWA-MEM2 index
echo "Creating BWA-MEM2 index using Docker..."
mkdir -p bwamem2_index
docker run --rm \
    -v "${WORK_DIR}:${WORK_DIR}" \
    -w "${WORK_DIR}" \
    ${BWAMEM2_IMAGE} \
    bwa-mem2 index -p "bwamem2_index/chr6_only.${GENOME_BUILD}" "${CHR6_FASTA}"

# Step 5: Create BWA index for GRIDSS (if needed)
echo "Creating BWA index for GRIDSS using Docker..."
mkdir -p bwa_index
docker run --rm \
    -v "${WORK_DIR}:${WORK_DIR}" \
    -w "${WORK_DIR}" \
    ${BWA_IMAGE} \
    bwa index -p "bwa_index/chr6_only.${GENOME_BUILD}" "${CHR6_FASTA}"

# Step 6: Create GATK BWA index image
echo "Creating GATK BWA index image using Docker..."
docker run --rm \
    -v "${WORK_DIR}:${WORK_DIR}" \
    -w "${WORK_DIR}" \
    ${GATK_IMAGE} \
    gatk BwaMemIndexImageCreator \
    --input "${CHR6_FASTA}" \
    --output "${CHR6_FASTA}.img"

echo "Chromosome 6 reference genome setup complete!"
echo "Reference files created in: $(pwd)"
echo ""
echo "Files created:"
echo "  - ${CHR6_FASTA} (chromosome 6 FASTA)"
echo "  - ${CHR6_FASTA}.fai (FASTA index)"
echo "  - ${CHR6_FASTA%.fasta}.dict (sequence dictionary)"
echo "  - ${CHR6_FASTA}.img (BWA index image)"
echo "  - bwamem2_index/ (BWA-MEM2 index directory)"
echo "  - bwa_index/ (BWA index directory)"
echo ""
echo "Next steps:"
echo "1. Create a custom genome configuration file"
echo "2. Update your oncoanalyser command to use the custom genome"