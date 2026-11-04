# Chromosome 6-only DNA mapping and HLA typing with nf-core/oncoanalyser

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
├── chr6_only.hg38.fasta.img
└── star_index                  # only for RNA samples, see 1.3
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

#### 1.3 Build the chr6 STAR index (only for RNA samples)
RNA FASTQs are aligned with STAR 2.7.3a, which needs its own index (`chr6_reference/star_index/`, ~1.5 GB). Build it once, from the repo root:
```bash
sbatch prepare_chr6_ref/build_chr6_star_index.slurm
```
The splice junctions are the chr6 lines of `sjdbList.out.tab` from the HMF GRCh38 STAR index (`star_index-gencode_38-2.7.3a`, gencode v38, `--sjdbOverhang 200`), the index oncoanalyser uses by default. You can pass a GTF instead as the first argument (`sbatch prepare_chr6_ref/build_chr6_star_index.slurm /path/to/annotation.gtf`); it is filtered to chr6. The job takes a few minutes (4 CPUs, 16 GB) and uses the STAR singularity image from the shared cache directory (step 3), pulling it if missing.

> **Why STAR needs extra options with a chr6-only index.** Most RNA reads come from other chromosomes. With only chr6 indexed, they anchor on chr6 repeats (which have too many copies to be used as anchors in the full genome), and STAR then searches thousands of alignment windows per read before giving up: ~1.5 M read pairs/h on 8 CPUs, i.e. more than a day per sample. `chr6_genome.config` caps this search on `STAR_ALIGN` (`--winAnchorMultimapNmax 5 --seedMultimapNmax 1000 --alignWindowsPerReadNmax 1000`), which gives ~29 M pairs/h.
>
> Benchmark on 200k read pairs of a PDX RNA sample, with the full-genome HMF STAR index as truth:
> - Capping the search finds the same MHC and HLA-gene reads as the uncapped chr6 run.
> - Both chr6 runs find 99% of the MHC reads and 32 of the 36 HLA-gene read pairs that the full genome places there.
> - Both chr6 runs also place reads in the MHC that the full genome maps elsewhere (human paralogs). In the HLA genes this was 4 pairs, against 36 true ones.
> - Adding chrM and rDNA contigs to the index did not change the speed.

DNA-only runs don't need this index. `RUN.hla_typing.slurm` stops with an error if the samplesheet has RNA FASTQs and the index is missing.



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
            star_index    = "/mnt/bioinfnas/immuno/plevy/proj/hlatyping/lilac/alignments/chr6_reference/star_index/"
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
    hmftools-lilac:2.0--hdfd78af_0 \
    star:2.7.3a--0 \
    samtools:1.21--h50ea8bc_0 \
    gatk4:4.6.1.0--py310hdfd78af_0
do
    singularity pull --name "depot.galaxyproject.org-singularity-${img//:/-}.img" \
        --dir ${CACHE_DIR} "https://depot.galaxyproject.org/singularity/${img}"
done
```
The file names follow the Nextflow naming convention (`depot.galaxyproject.org-singularity-<image>-<tag>.img`), so Nextflow finds them instead of downloading again. The images are FASTP and BWA-MEM2 (DNA alignment), REDUX and LILAC, and STAR, samtools and GATK (RNA alignment: STAR, sort, MarkDuplicates; only needed with RNA samples).

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

Prepare `input.csv` (oncoanalyser samplesheet), one row per sample/FASTQ pair. A single samplesheet can hold many patients: Nextflow processes them all in one run, in parallel on the cluster. For example, 3 patients:
```csv
group_id,subject_id,sample_id,sample_type,sequence_type,filetype,info,filepath
PAT01,PAT01,PAT01_T,tumor,dna,fastq,library_id:PAT01_T;lane:1,/path/to/PAT01_T_1.fastq.gz;/path/to/PAT01_T_2.fastq.gz
PAT02,PAT02,PAT02_T,tumor,dna,fastq,library_id:PAT02_T;lane:1,/path/to/PAT02_T_L1_1.fastq.gz;/path/to/PAT02_T_L1_2.fastq.gz
PAT02,PAT02,PAT02_T,tumor,dna,fastq,library_id:PAT02_T;lane:2,/path/to/PAT02_T_L2_1.fastq.gz;/path/to/PAT02_T_L2_2.fastq.gz
PAT03,PAT03,PAT03_T,tumor,dna,fastq,library_id:PAT03_T;lane:1,/path/to/PAT03_T_1.fastq.gz;/path/to/PAT03_T_2.fastq.gz
PAT03,PAT03,PAT03_N,normal,dna,fastq,library_id:PAT03_N;lane:1,/path/to/PAT03_N_1.fastq.gz;/path/to/PAT03_N_2.fastq.gz
PAT03,PAT03,PAT03_RNA,tumor,rna,fastq,library_id:PAT03_RNA;lane:1,/path/to/PAT03_RNA_1.fastq.gz;/path/to/PAT03_RNA_2.fastq.gz
```
PAT01 is a single tumor sample, PAT02 has 2 sequencing lanes, and PAT03 is a tumor/normal pair with tumor RNA. Results are written per patient, to `output_chr6/<group_id>/lilac/`.

> **Only LILAC results are kept.** oncoanalyser publishes all its outputs, including BAMs, through one output block that can't be filtered from a config. `RUN.hla_typing.slurm` therefore publishes them as symlinks into `output_chr6_links/`. After a successful run it copies only `<group_id>/lilac/` and `pipeline_info/` into `output_chr6/` and deletes the symlinks folder. The BAMs stay in `work/` only, where `-resume` still uses them. Copy them from `work/` before cleaning it if you need them.

- `group_id`: one per patient. All rows of a patient (tumor, normal, lanes) share it.
- `filetype`: `fastq`, so reads are aligned to the chr6-only reference.
- `filepath`: R1 and R2 FASTQs separated by `;`.
- `info`: `library_id` and `lane` are required for FASTQ input. Add one row per lane if a sample has several (like PAT02); the lanes are merged into one BAM.
- `sample_type`: `tumor` runs LILAC in tumor-only mode. To run in tumor/normal mode, add a second row with `sample_type` `normal` and the same `group_id`.
- `sequence_type`: `dna`, or `rna` for tumor RNA (needs the STAR index, step 1.3). Give the RNA row the same `group_id` as the DNA, and its own `sample_id` and `library_id`.

> **What RNA adds.** LILAC calls the alleles from DNA only. RNA reads fill the `Rna*` columns of `lilac.tsv` (expression support for each called allele), and the allele calls stay the same. A `group_id` with only RNA gets its RNA aligned, but LILAC is skipped.
>
> **PDX samples.** RNA FASTQs that were not cleaned of mouse reads (e.g. with bbsplit, as done for the PDX WES `_hs_` FASTQs) can put mouse H2 reads on the chr6 HLA genes. This only affects the `Rna*` columns.

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

RNA reads are aligned the same way with STAR (splice-aware), then sorted and duplicate-marked with GATK MarkDuplicates. Unlike the DNA BAMs, the RNA BAM keeps unmapped reads (oncoanalyser runs STAR with `--outSAMunmapped Within`). The BAMs (e.g. `PAT03_T.redux.bam` and `PAT03_RNA.md.bam`) are not copied to `output_chr6/`. They stay in the REDUX and MarkDuplicates task folders under `work/`.

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

### Summary table of all patients

`summarize_lilac.py` gathers every `<group_id>/lilac/<group_id>.lilac.tsv` of an output folder into one table. It has one row per patient and gene (HLA-A, -B, -C, -DPA1, -DPB1, -DQA1, -DQB1), with the columns `sample_id`, `gene`, `allele1`, `allele2`, `homozygous` (yes/no for that gene) and `loh_likelihood`. `loh_likelihood` is `yes` for every row of a patient homozygous at all HLA genes. This most likely means loss of heterozygosity (LOH) of the HLA region, because germline homozygosity at all genes is rare. With tumor-only data it is a flag, not an LOH call. The table is not generated by the pipeline. Run it by hand, and again after adding patients (it needs only python3, and runs in seconds):

```bash
python3 summarize_lilac.py output_chr6         # writes output_chr6/lilac_alleles.tsv
python3 summarize_lilac.py output_chr6 --rna   # adds allele1_RnaUnique / allele2_RnaUnique (NA for samples run without RNA)
```

## Credits and Citations

This setup is a thin wrapper around [nf-core/oncoanalyser](https://github.com/nf-core/oncoanalyser), written and maintained by Stephen Watts ([@scwatts](https://github.com/scwatts)) at the University of Melbourne Centre for Cancer Research, with assistance from Hartwig Medical Foundation Australia, as part of the nf-core community. The analysis tools (REDUX, LILAC) are from the [Hartwig Medical Foundation hmftools](https://github.com/hartwigmedical/hmftools) suite. All credit for the pipeline and its tools goes to their authors.

If you use this setup, please cite the pipeline as nf-core/oncoanalyser asks:

- **nf-core/oncoanalyser** Zenodo record, citing the version you ran (3.0.0 in `RUN.hla_typing.slurm`): [10.5281/zenodo.15189386](https://doi.org/10.5281/zenodo.15189386)
- **nf-core framework**:
  > Ewels PA, Peltzer A, Fillinger S, Patel H, Alneberg J, Wilm A, Garcia MU, Di Tommaso P, Nahnsen S. The nf-core framework for community-curated bioinformatics pipelines. _Nat Biotechnol._ 2020 Mar;38(3):276-278. doi: [10.1038/s41587-020-0439-x](https://doi.org/10.1038/s41587-020-0439-x).

Also cite the tools used by this workflow. The full list is in the pipeline's [CITATIONS.md](https://github.com/nf-core/oncoanalyser/blob/master/CITATIONS.md):
- **Nextflow**: Di Tommaso P, et al. Nextflow enables reproducible computational workflows. _Nat Biotechnol._ 2017;35(4):316-319. doi: [10.1038/nbt.3820](https://doi.org/10.1038/nbt.3820).
- **bwa-mem2**: Vasimuddin Md, Misra S, Li H, Aluru S. Efficient Architecture-Aware Acceleration of BWA-MEM for Multicore Systems. _IPDPS_ 2019:314-324. doi: [10.1109/IPDPS.2019.00041](https://doi.org/10.1109/IPDPS.2019.00041).
- **STAR** (RNA samples): Dobin A, et al. STAR: ultrafast universal RNA-seq aligner. _Bioinformatics._ 2013;29(1):15-21. doi: [10.1093/bioinformatics/bts635](https://doi.org/10.1093/bioinformatics/bts635).
- **LILAC**: Martínez-Jiménez F, et al. Genetic immune escape landscape in primary and metastatic cancer. _Nat Genet._ 2023;55(5):820-831. doi: [10.1038/s41588-023-01367-1](https://doi.org/10.1038/s41588-023-01367-1).
- **REDUX**: [hmftools/redux](https://github.com/hartwigmedical/hmftools/tree/master/redux) (Hartwig Medical Foundation).

The resource files in `hmf_data_min/` are copied unchanged from the Hartwig Medical Foundation oncoanalyser reference bundle (`hmf_pipeline_resources.38_v3.0.0--8`).


