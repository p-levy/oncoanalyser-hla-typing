#!/bin/bash
#SBATCH --mem=8gb # Job memory request
#SBATCH -c 1 # max nr threads
#SBATCH --time=2-00:00:00           # Time limit hrs:min:sec
#SBATCH --output=R-%x.%j.out   # Standard output and error log
#SBATCH --partition=long
#SBATCH --mail-type=FAIL,END

# Class I HLA typing of RNA-only samples (no DNA): chr6-only STAR alignment with nf-core/oncoanalyser, then LILAC on the RNA BAM
# oncoanalyser runs LILAC only with DNA, so LILAC is run by accessory/lilac_rna_only.slurm (submitted below, waits for it).
# Samples with DNA go through RUN.hla_typing.slurm instead (RNA there only adds the Rna* counts).
# RUN WITH:
# sbatch -J CHR6-RNA-ONLY --mail-user=plevy@vhio.net RUN.hla_typing_rna_only.slurm input_rna_only.csv output_chr6_rnaonly

# ONLY CHANGE IF NEEDED
INPUT=${1:-input_rna_only.csv}
OUTPUT=${2:-output_chr6_rnaonly}
CONFIG_FILE=${3:-/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/oncoanalyser-hla-typing/chr6_genome.config}
OPT_ARGS=${4:-"--processes_manual alignment"}

REPO_DIR=$(dirname "${CONFIG_FILE}")
CHR6_REF_DIR="${REPO_DIR}/chr6_reference"
HMF_DATA_DIR="${REPO_DIR}/hmf_data_min"

if [[ ! -f "${CHR6_REF_DIR}/star_index/SA" ]]; then
    echo "ERROR: chr6 STAR index missing: ${CHR6_REF_DIR}/star_index"
    echo "Please build it first, from the repo root: sbatch prepare_chr6_ref/build_chr6_star_index.slurm"
    exit 1
fi
if grep -q ',dna,' "${INPUT}"; then
    echo "ERROR: ${INPUT} has DNA rows. Samples with DNA go through RUN.hla_typing.slurm; this script is for RNA-only groups"
    exit 1
fi

# Alignments are published as symlinks into LINKS_DIR (BAMs stay in work/), only LILAC results are copied to OUTPUT
LINKS_DIR="${OUTPUT}_links"
IO_ARGS="--input ${INPUT} --outdir ${LINKS_DIR} --publish_dir_mode symlink"

echo "Running nf-core/oncoanalyser RNA alignment with chromosome 6-only reference..."
echo "Input: ${INPUT}"
echo "Output: ${OUTPUT}"
echo "Config: ${CONFIG_FILE}"
echo "Options: ${OPT_ARGS}"

mkdir -p cache
mkdir -p tmp

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
    ${IO_ARGS} \
	-resume \
    ${OPT_ARGS}

NXF_EXIT=$?
if [[ ${NXF_EXIT} -ne 0 ]]; then
    echo "ERROR: nf-core/oncoanalyser failed (exit ${NXF_EXIT}), see .nextflow.log"
    exit ${NXF_EXIT}
fi

# LILAC on each RNA BAM, in its own job (4 CPUs) so this 1-CPU job doesn't hold them while STAR runs
sbatch --wait "${REPO_DIR}/accessory/lilac_rna_only.slurm" "${LINKS_DIR}" "${OUTPUT}"
LILAC_EXIT=$?
if [[ ${LILAC_EXIT} -ne 0 ]]; then
    echo "ERROR: LILAC failed for some samples (exit ${LILAC_EXIT}), see R-LILAC-RNA-ONLY.*.out. ${LINKS_DIR} is kept"
    exit ${LILAC_EXIT}
fi

set -e
cp -rL "${LINKS_DIR}/pipeline_info" "${OUTPUT}/"
rm -r "${LINKS_DIR}"
echo "LILAC class I results (from RNA only) written to ${OUTPUT}/<group_id>/lilac/"
