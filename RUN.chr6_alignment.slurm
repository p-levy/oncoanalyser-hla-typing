#!/bin/bash
#SBATCH --mem=8gb # Job memory request
#SBATCH -c 1 # max nr threads
#SBATCH --time=2-00:00:00           # Time limit hrs:min:sec
#SBATCH --output=R-%x.%j.out   # Standard output and error log
#SBATCH --error=R-%x.%j.err
#SBATCH --partition=highmem
#SBATCH --mail-type=FAIL,END

# Modified script for chromosome 6-only alignment using nf-core/oncoanalyser
# RUN WITH:
# sbatch -J CHR6-ALIGN --mail-user=plevy@vhio.net RUN.chr6_alignment.slurm input.csv output_chr6

# DO NOT CHANGE THESE LINES
INPUT=${1:-input.csv}
OUTPUT=${2:-output_chr6}
CONFIG_FILE=${3:-/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/alignments/chr6_genome.config}
OPT_ARGS=${4:-"--processes_manual --processes_include alignment,redux,lilac"} # Only run alignment by default

# Check if chromosome 6 reference exists
CHR6_REF_DIR="/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/alignments/chr6_reference"
CHR6_FASTA="${CHR6_REF_DIR}/chr6_only.hg38.fasta"

if [[ ! -f "${CHR6_FASTA}" ]]; then
    echo "ERROR: Chromosome 6 reference not found at ${CHR6_FASTA}"
    echo "Please run setup_chr6_reference.sh first to create the chromosome 6-only reference genome"
    echo "Usage: ./setup_chr6_reference.sh /path/to/full/reference.fasta chr6_reference hg38"
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
    --mode wgts \
	-params-file /mnt/bioinfnas/immuno/plevy/proj/hmftools/hmf38.yaml \
    --genome chr6_hg38 \
	--genome_version 38 \
    --force_genome \
	--genome_type no_alt \
    --input ${INPUT} \
    --outdir ${OUTPUT} \
	-resume \
    ${OPT_ARGS}

# Note: The output BAM files will only contain reads that align to chromosome 6
# Reads that don't align to chromosome 6 will be discarded during alignment

echo "Chromosome 6-only alignment complete!"
echo "Output BAM files contain only reads aligned to chromosome 6"

