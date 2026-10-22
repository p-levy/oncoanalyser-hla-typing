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

### 3. Run Alignment and LILAC HLA typing

Update the `ref_data_hmf_data_path` to point to your HMF tools reference data:
```groovy
--ref_data_hmf_data_path "/your/actual/path/to/hmftools_data/"
```

Prepare `input.csv` (oncoanalyser samplesheet), one row per sample/FASTQ pair, e.g.:
```csv
group_id,subject_id,sample_id,sample_type,sequence_type,filetype,info,filepath
NCI3998,NCI3998,NCI3998N,tumor,dna,fastq,library_id:NCI3998N;lane:1,/path/to/3998N_1.fastq.gz;/path/to/3998N_2.fastq.gz
```
- `filetype`: `fastq`, so reads are aligned to the chr6-only reference.
- `filepath`: R1 and R2 FASTQs separated by `;`.
- `info`: `library_id` and `lane` are required for FASTQ input. Add one row per lane if a sample has several.
- `sample_type`: `tumor` runs LILAC in tumor-only mode. To run in tumor/normal mode, add a second row with `sample_type` `normal` and the same `group_id`.

Submit the job to align only to chromosome 6:
```bash
sbatch -J CHR6-ALIGN --mail-user=your.email@vhio.net RUN.chr6_alignment.slurm input.csv output_chr6
```

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
| `<tumor_id>.lilac.tsv` | **Main result**: one row per called HLA class I allele (2 each for A, B, C), e.g. `A*02:05` |
| `<tumor_id>.lilac.qc.tsv` | One-row QC summary for the sample |
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

- **nf-core/oncoanalyser** Zenodo record, citing the version you ran (3.0.0 in `RUN.chr6_alignment.slurm`): [10.5281/zenodo.15189386](https://doi.org/10.5281/zenodo.15189386)
- **nf-core framework**:
  > Ewels PA, Peltzer A, Fillinger S, Patel H, Alneberg J, Wilm A, Garcia MU, Di Tommaso P, Nahnsen S. The nf-core framework for community-curated bioinformatics pipelines. _Nat Biotechnol._ 2020 Mar;38(3):276-278. doi: [10.1038/s41587-020-0439-x](https://doi.org/10.1038/s41587-020-0439-x).

Also cite the tools used by this workflow. The full list is in the pipeline's [CITATIONS.md](https://github.com/nf-core/oncoanalyser/blob/master/CITATIONS.md):
- **Nextflow**: Di Tommaso P, et al. Nextflow enables reproducible computational workflows. _Nat Biotechnol._ 2017;35(4):316-319. doi: [10.1038/nbt.3820](https://doi.org/10.1038/nbt.3820).
- **bwa-mem2**: Vasimuddin Md, Misra S, Li H, Aluru S. Efficient Architecture-Aware Acceleration of BWA-MEM for Multicore Systems. _IPDPS_ 2019:314-324. doi: [10.1109/IPDPS.2019.00041](https://doi.org/10.1109/IPDPS.2019.00041).
- **LILAC**: Martínez-Jiménez F, et al. Genetic immune escape landscape in primary and metastatic cancer. _Nat Genet._ 2023;55(5):820-831. doi: [10.1038/s41588-023-01367-1](https://doi.org/10.1038/s41588-023-01367-1).
- **REDUX**: [hmftools/redux](https://github.com/hartwigmedical/hmftools/tree/master/redux) (Hartwig Medical Foundation).


