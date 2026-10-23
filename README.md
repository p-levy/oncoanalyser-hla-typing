# Chromosome 6-Only Alignment and HLA typing with nf-core/oncoanalyser

This setup allows you to run nf-core/oncoanalyser alignment restricted to chromosome 6 only, and LILAC for HLA typing. 

*Chr6 ref preparation tools are run using **Docker** containers*.

## Overview

The approach creates a custom reference genome containing only chromosome 6, then uses nf-core/oncoanalyser (alignment, redux and lilac modules only) with this reduced reference. This ensures that:
1. Only reads that align to chromosome 6 are included in the final BAM files
2. Reads from other chromosomes are discarded during alignment
3. The resulting BAMs are much smaller and focused on the HLA region
4. HLA typing is obtained faster. 

## Setup Instructions

### 1. Create chr6-only reference or download from provided link
#### 1.1 Download ready-made chr6 reference
>\>\>\> [click here to download `chr6_reference` from VHIO SharePoint](https://vhio365-my.sharepoint.com/:u:/g/personal/plevy_vhio_net/IQB7s4qxoU21QIAl98scjCpTAVTLmtRjtXpyXocaCtcGg5g?e=Fv9swA) <<<

Extract the archive (creates `chr6_reference/`):
```bash
tar -xzf chr6_reference.tar.gz
```

```
chr6_reference/
├── bwamem2_index
│   ├── chr6_only.hg38.fasta.0123
│   ├── chr6_only.hg38.fasta.amb
│   ├── chr6_only.hg38.fasta.ann
│   ├── chr6_only.hg38.fasta.bwt.2bit.64
│   └── chr6_only.hg38.fasta.pac
├── chr6_only.hg38.dict
├── chr6_only.hg38.fasta
├── chr6_only.hg38.fasta.fai
└── chr6_only.hg38.fasta.img
```

Created from below script using **GRCh38_masked_exclusions_alts_hlas.fasta** genome reference.

#### 1.2 Create from custom whole-genome reference
⚠️ Only if needed (e.g. You can't download from the above link or prefer to use another reference genome version).


Run the full setup script with your reference genome path:
```bash
./setup_chr6_reference.sh /path/to/your/reference.fasta chr6_reference hg38
```
For current version of oncoanalyser, reference should be called **GRCh38_masked_exclusions_alts_hlas.fasta**.  

This will create (using Docker containers):
- `chr6_reference/chr6_only.hg38.fasta` - Chromosome 6 sequence
- Required indexes (BWA-MEM2, FASTA index, dictionary, etc.)



### 2. Update Configuration

Edit `chr6_genome.config`: update chr6_reference file paths. 

```groovy
params {
    genomes {
        'chr6_hg38' {
            fasta         = "/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/alignments/chr6_reference/chr6_only.hg38.fasta"
            fai           = "/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/alignments/chr6_reference/chr6_only.hg38.fasta.fai"
            dict          = "/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/alignments/chr6_reference/chr6_only.hg38.dict"
            img           = "/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/alignments/chr6_reference/chr6_only.hg38.fasta.img"
            bwamem2_index = "/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/alignments/chr6_reference/bwamem2_index/"
        }
    }
}
```

### 3. Pull Singularity images (optional)

By default Nextflow downloads the images on the first run, into `work/singularity/` of each run. To reuse them across runs and projects, or to prepare them on a node with internet access, pull the 4 images used by oncoanalyser 3.0.0 for alignment, REDUX and LILAC into a shared cache directory:

```bash
CACHE_DIR=/path/to/singularity_cache
mkdir -p ${CACHE_DIR}
for img in \
    fastp:0.23.4--hadf994f_2 \
    mulled-v2-4dde50190ae599f2bb2027cb2c8763ea00fb5084:596c0d6a494faa218562f2be03af2714d454da4f-0 \
    hmftools-redux:2.0.5--hdfd78af_0 \
    hmftools-lilac:2.0--hdfd78af_0
do
    singularity pull --name "depot.galaxyproject.org-singularity-${img//:/-}.img" \
        --dir ${CACHE_DIR} "https://depot.galaxyproject.org/singularity/${img}"
done
```
The file names follow the Nextflow naming convention (`depot.galaxyproject.org-singularity-<image>-<tag>.img`), so Nextflow finds them instead of downloading again. The images are FASTP and BWA-MEM2 (alignment), REDUX and LILAC.

Then point the `singularity` block of `chr6_genome.config` to that directory:
```groovy
singularity {
    ...
    cacheDir = '/path/to/singularity_cache'
}
```
You can also set `export NXF_SINGULARITY_CACHEDIR=/path/to/singularity_cache` before `sbatch` instead. `cacheDir` in the config takes precedence if both are set.

### 4. Run HLA typing (alignment, REDUX and LILAC)

In `RUN.hla_typing.slurm`, update these 3 paths to the absolute location of your clone:
```bash
CONFIG_FILE=${3:-/path/to/oncoanalyser-hla-typing/chr6_genome.config}
CHR6_REF_DIR="/path/to/oncoanalyser-hla-typing/chr6_reference"
HMF_DATA_DIR="/path/to/oncoanalyser-hla-typing/hmf_data_min"
```

> **No need for the full HMF resource bundle (~10 GB).** Alignment, REDUX and LILAC only use 3 HMF resources (~20 MB), shipped in `hmf_data_min/`. `chr6_genome.config` overrides `hmf_data_paths` so oncoanalyser does not look for the other files. This override matches oncoanalyser **3.0.0**; check it if you change `-revision`. If you add other steps (e.g. PURPLE/SAGE to get allele copy number and somatic mutations in LILAC), use the full bundle and remove the override.

Prepare `input.csv` (oncoanalyser samplesheet), one row per sample/FASTQ pair, e.g.:
```csv
group_id,subject_id,sample_id,sample_type,sequence_type,filetype,info,filepath
cohort,patient,patient_T,tumor,dna,fastq,library_id:patient_id;lane:1,/path/to/patient_T_1.fastq.gz;/path/to/patient_T_2.fastq.gz
```
- `filetype`: `fastq`, so reads are aligned to the chr6-only reference.
- `filepath`: R1 and R2 FASTQs separated by `;`.
- `info`: `library_id` and `lane` are required for FASTQ input. Add one row per lane if a sample has several.
- `sample_type`: `tumor` runs LILAC in tumor-only mode. To run in tumor/normal mode, add a second row with `sample_type` `normal` and the same `group_id`.

Submit the job to align only to chromosome 6:
```bash
sbatch -J CHR6-ALIGN --mail-user=your.email@vhio.net RUN.hla_typing.slurm input.csv output_chr6
```

### Test run

A `test` profile checks the whole setup on a small dataset: about 54,000 read pairs from the HLA region of the **MDA-MB-231** breast cancer cell line. The test FASTQs are in `test/` and come with the clone, so no `input.csv` is needed: test mode uses `test/samplesheet.csv`. Its FASTQ paths are relative to `test/`, so **launch the test from the `test/` folder**. The chr6 reference (step 1) and `hmf_data_min/` are still required.

```bash
cd test
sbatch -J CHR6-TEST --mail-user=your.email@vhio.net ../RUN.hla_typing.slurm test
```
This runs with `-profile singularity,test` and writes results to `test/output_test/` (resources capped at 8 CPUs, 16 GB, 2 h). Nextflow's run files (`work/`, `.nextflow/`) also stay in `test/` and are ignored by git.

> Test runs takes about 3 min.

Expected HLA types in `test/output_test/MDAMB231/lilac/MDAMB231.lilac.tsv`:

| Gene | Alleles |
|---|---|
| HLA-A | A\*02:01, A\*02:17 |
| HLA-B | B\*40:02, B\*41:01 |
| HLA-C | C\*02:02, C\*17:01 |
| HLA-DPA1 | DPA1\*01:03, DPA1\*02:01 |
| HLA-DPB1 | DPB1\*02:01, DPB1\*17:01 |
| HLA-DQA1 | DQA1\*02:01, DQA1\*05:05 |
| HLA-DQB1 | DQB1\*02:02, DQB1\*03:01 |


## Docker Images Used

The workflow to prepare chr6 references uses these Docker images:
- `staphb/samtools:1.21` - For FASTA indexing and BAM analysis
- `biocontainers/bwa:v0.7.17_cv1` - For BWA indexing
- `quay.io/biocontainers/bwa-mem2:2.3--he70b90d_0` - For BWA-MEM2 indexing  
- `broadinstitute/picard:3.4.0` - For sequence dictionary creation
- `broadinstitute/gatk:4.6.1.0` - For BWA index image creation

## Understanding the Results

### What happens during alignment:
1. BWA-MEM2 attempts to align all reads to the chromosome 6-only reference
2. Reads that cannot align to chromosome 6 are discarded
3. Only reads with good alignments to chromosome 6 are kept
4. The output BAM files contain only chromosome 6 alignments

### Output BAM characteristics:
- Much smaller file sizes (only chr6 reads)
- All reads have chromosome 6 coordinates
- Suitable for HLA typing and chromosome 6-specific analysis
- Compatible with downstream HLA analysis tools

### LILAC outputs

Written to `output_chr6/<group_id>/lilac/`:

| File | Content |
|---|---|
| `<tumor_id>.lilac.tsv` | **Main result**: one row per called allele. The `Genes` column groups them: `MHC_CLASS_1` (2 each for A, B, C, e.g. `A*02:05`), and `HLA_DPA1`, `HLA_DPB1`, `HLA_DQA1`, `HLA_DQB1` for class II (LILAC ≥ 2.0) |
| `<tumor_id>.lilac.qc.tsv` | QC summary, one row per gene group |
| `<tumor_id>.lilac.candidates.coverage.tsv` | Fragment coverage of the top-scoring candidate allele sets |

Key columns in `lilac.tsv`:
- `Allele`: HLA allele at 2-field resolution.
- `RefTotal`/`RefUnique`/`RefShared`/`RefWild`: supporting fragments in the reference (normal) sample; `Tumor*` and `Rna*` are the same for tumor and RNA.
- `TumorCopyNumber`, `Somatic*`: allele copy number and somatic mutations. **These need PURPLE and SAGE outputs, which this chr6-only run does not produce, so expect 0 here.**

Key columns in `lilac.qc.tsv`:
- `Status`: `PASS` or a warning (e.g. `WARN_UNMATCHED_HAPLOTYPE`, `WARN_LOW_COVERAGE`). Check this before trusting the call.
- `ScoreMargin` / `NextSolutionAlleles`: how far ahead the best solution is and which alleles differ in the runner-up. A low margin means the call is ambiguous.
- `A/B/C_LowCoverageBases`, `TotalFragments`, `FittedFragments`, `UnmatchedFragments`: coverage and fit quality.

See the [LILAC documentation](https://github.com/hartwigmedical/hmftools/tree/master/lilac) for the full column descriptions.

## Credits and Citations

This setup is a thin wrapper around [nf-core/oncoanalyser](https://github.com/nf-core/oncoanalyser), written and maintained by Stephen Watts ([@scwatts](https://github.com/scwatts)) at the University of Melbourne Centre for Cancer Research, with assistance from Hartwig Medical Foundation Australia, as part of the nf-core community. The analysis tools (REDUX, LILAC) are from the [Hartwig Medical Foundation hmftools](https://github.com/hartwigmedical/hmftools) suite. All credit for the pipeline and its tools goes to their authors.

If you use this setup, please cite the pipeline as nf-core/oncoanalyser asks:

- **nf-core/oncoanalyser** Zenodo record, citing the version you ran (3.0.0 in `RUN.hla_typing.slurm`): [10.5281/zenodo.15189386](https://doi.org/10.5281/zenodo.15189386)
- **nf-core framework**:
  > Ewels PA, Peltzer A, Fillinger S, Patel H, Alneberg J, Wilm A, Garcia MU, Di Tommaso P, Nahnsen S. The nf-core framework for community-curated bioinformatics pipelines. _Nat Biotechnol._ 2020 Mar;38(3):276-278. doi: [10.1038/s41587-020-0439-x](https://doi.org/10.1038/s41587-020-0439-x).

Also cite the tools used by this workflow. The full list is in the pipeline's [CITATIONS.md](https://github.com/nf-core/oncoanalyser/blob/master/CITATIONS.md):
- **Nextflow**: Di Tommaso P, et al. Nextflow enables reproducible computational workflows. _Nat Biotechnol._ 2017;35(4):316-319. doi: [10.1038/nbt.3820](https://doi.org/10.1038/nbt.3820).
- **bwa-mem2**: Vasimuddin Md, Misra S, Li H, Aluru S. Efficient Architecture-Aware Acceleration of BWA-MEM for Multicore Systems. _IPDPS_ 2019:314-324. doi: [10.1109/IPDPS.2019.00041](https://doi.org/10.1109/IPDPS.2019.00041).
- **LILAC**: Martínez-Jiménez F, et al. Genetic immune escape landscape in primary and metastatic cancer. _Nat Genet._ 2023;55(5):820-831. doi: [10.1038/s41588-023-01367-1](https://doi.org/10.1038/s41588-023-01367-1).
- **REDUX**: [hmftools/redux](https://github.com/hartwigmedical/hmftools/tree/master/redux) (Hartwig Medical Foundation).

The resource files in `hmf_data_min/` are copied unchanged from the Hartwig Medical Foundation oncoanalyser reference bundle (`hmf_pipeline_resources.38_v3.0.0--8`).


