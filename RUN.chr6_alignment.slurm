#!/bin/bash
#SBATCH --mem=8gb # Job memory request
#SBATCH -c 1 # max nr threads
#SBATCH --time=2-00:00:00           # Time limit hrs:min:sec
#SBATCH --output=R-%x.%j.out   # Standard output and error log
#SBATCH --partition=highmem
#SBATCH --mail-type=FAIL,END

# Modified script for chromosome 6-only alignment using nf-core/oncoanalyser
# RUN WITH:
# sbatch -J CHR6-ALIGN --mail-user=plevy@vhio.net RUN.chr6_alignment.slurm input.csv output_chr6

# ONLY CHANGE IF NEEDED
INPUT=${1:-input.csv}
OUTPUT=${2:-output_chr6}
CONFIG_FILE=${3:-/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/oncoanalyser-lilac-only/chr6_genome.config}
OPT_ARGS=${4:-"--processes_manual alignment,redux,lilac"} # Only run alignment by default

# Check if chromosome 6 reference exists
CHR6_REF_DIR="/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/oncoanalyser-lilac-only/chr6_reference"
CHR6_FASTA="${CHR6_REF_DIR}/chr6_only.hg38.fasta"
# Minimal HMF resources (REDUX + LILAC only), shipped with the repo
HMF_DATA_DIR="/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/oncoanalyser-lilac-only/hmf_data_min"

if [[ ! -f "${CHR6_FASTA}" ]]; then
    echo "ERROR: Chromosome 6 reference not found at ${CHR6_FASTA}"
    echo "Please run setup_chr6_reference.sh first to create the chromosome 6-only reference genome"
    echo "Usage: ./setup_chr6_reference.sh /path/to/full/reference.fasta chr6_reference hg38"
    exit 1
fi

# Check if minimal HMF resources exist
if [[ ! -d "${HMF_DATA_DIR}/misc/lilac" ]]; then
    echo "ERROR: Minimal HMF resources not found at ${HMF_DATA_DIR}"
    echo "Please set HMF_DATA_DIR to the hmf_data_min folder of this repository"
    exit 1
fi

# Check if config file exists
if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: Configuration file not found: ${CONFIG_FILE}"
    echo "Please ensure chr6_genome.config exists and contains the correct paths"
    exit 1
fi

echo "Running nf-core/oncoanalyser with chromosome 6-only reference..."
echo "Input: ${INPUT}"
echo "Output: ${OUTPUT}"
echo "Config: ${CONFIG_FILE}"
echo "Options: ${OPT_ARGS}"

# Create cache and tmp directories if they don't exist
mkdir -p cache
mkdir -p tmp

# Run nf-core/oncoanalyser with custom chromosome 6 genome
nextflow run nf-core/oncoanalyser \
    -revision 3.0.0 \
    -profile singularity \
    -c ${CONFIG_FILE} \
    --ref_data_hmf_data_path ${HMF_DATA_DIR} \
    --mode wgts \
    --genome chr6_hg38 \
	--genome_version 38 \
    --force_genome \
	--genome_type no_alt \
    --input ${INPUT} \
    --outdir ${OUTPUT} \
	-resume \
    ${OPT_ARGS}

# Exit with Nextflow's status so Slurm reports failed runs as FAILED
NXF_EXIT=$?
if [[ ${NXF_EXIT} -ne 0 ]]; then
    echo "ERROR: nf-core/oncoanalyser failed (exit ${NXF_EXIT}), see .nextflow.log"
    exit ${NXF_EXIT}
fi

# Note: The output BAM files will only contain reads that align to chromosome 6
# Reads that don't align to chromosome 6 will be discarded during alignment

