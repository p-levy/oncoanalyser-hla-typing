#!/bin/bash
#SBATCH --job-name=LILAC-RNA-ONLY
#SBATCH --partition=short
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --output=R-%x.%j.out

# Class I HLA typing from RNA only: runs LILAC on each chr6 RNA BAM published by RUN.hla_typing_rna_only.slurm,
# with the RNA BAM given as -tumor_bam (oncoanalyser only runs LILAC on DNA and passes RNA as -rna_bam).
# Class II is skipped: PDX tumor cells barely express it, and calls from few RNA reads were wrong in tests.
# Submitted by RUN.hla_typing_rna_only.slurm; by hand: sbatch accessory/lilac_rna_only.slurm <links_dir> <output_dir>
# Writes <output_dir>/<group_id>/lilac/<group_id>.lilac.{tsv,qc.tsv,candidates.coverage.tsv}

set -uo pipefail
LINKS_DIR=$1
OUTPUT=$2
REPO_DIR=/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/oncoanalyser-hla-typing
REF="${REPO_DIR}/chr6_reference/chr6_only.hg38.fasta"
RESOURCES="${REPO_DIR}/hmf_data_min/misc/lilac"

# LILAC 2.0 image, as used by oncoanalyser 3.0.0: LILAC_IMG if set, else the Nextflow singularity caches, else pulled into work/singularity/
IMG_NAME=depot.galaxyproject.org-singularity-hmftools-lilac-2.0--hdfd78af_0.img
if [[ -z "${LILAC_IMG:-}" ]]; then
    for dir in "${NXF_SINGULARITY_CACHEDIR:-}" work/singularity; do
        [[ -n "${dir}" && -f "${dir}/${IMG_NAME}" ]] && LILAC_IMG="${dir}/${IMG_NAME}" && break
    done
fi
if [[ -z "${LILAC_IMG:-}" ]]; then
    mkdir -p work/singularity
    LILAC_IMG="work/singularity/${IMG_NAME}"
    singularity pull --name "${LILAC_IMG}" https://depot.galaxyproject.org/singularity/hmftools-lilac:2.0--hdfd78af_0 || exit 1
fi
echo "LILAC image: ${LILAC_IMG}"

n_ok=0; failed=()
for bam in "${LINKS_DIR}"/*/alignments/*/*.md.bam; do
    [[ -e "${bam}" ]] || continue
    group_id=$(basename "$(dirname "$(dirname "$(dirname "${bam}")")")")
    echo "=== ${group_id}: ${bam}"
    if singularity exec -B /mnt "${LILAC_IMG}" lilac -Xmx12G \
        -sample "${group_id}" \
        -tumor_bam "$(readlink -f "${bam}")" \
        -ref_genome "${REF}" -ref_genome_version V38 -resource_dir "${RESOURCES}" \
        -freq_score_penalty 0.0009 -genes MHC_CLASS_1 -sequencing_type ILLUMINA \
        -threads "${SLURM_CPUS_PER_TASK:-1}" \
        -output_dir "${OUTPUT}/${group_id}/lilac"; then
        n_ok=$((n_ok + 1))
    else
        failed+=("${group_id}")
    fi
done

echo "LILAC RNA-only: ${n_ok} succeeded, ${#failed[@]} failed ${failed[*]:-}"
[[ ${n_ok} -gt 0 && ${#failed[@]} -eq 0 ]]
