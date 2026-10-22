# hmf_data_min

Minimal subset of the HMF reference data needed by nf-core/oncoanalyser 3.0.0 to run alignment, REDUX and LILAC on GRCh38.

Files are copied unchanged from the Hartwig Medical Foundation oncoanalyser reference bundle `hmf_pipeline_resources.38_v3.0.0--8`, keeping its folder layout:

| File | Used by |
|---|---|
| `common/unmap_regions.38.tsv` | REDUX |
| `dna/variants/msi_jitter_sites.38.tsv.gz` | REDUX |
| `misc/lilac/` | LILAC |

All credit for these resources goes to the [Hartwig Medical Foundation](https://github.com/hartwigmedical/hmftools).
