#!/usr/bin/env python3
# Summarize the LILAC results of an output folder into one table: sample_id, gene, allele1, allele2
# Reads <output_dir>/<group_id>/lilac/<group_id>.lilac.tsv, sample_id is the <group_id> folder name
# USAGE:
# python3 summarize_lilac.py output_chr6                # writes output_chr6/lilac_alleles.tsv
# python3 summarize_lilac.py output_chr6 --rna          # adds RnaUnique fragment counts per allele
# python3 summarize_lilac.py output_chr6 -o my_table.tsv

import argparse
import csv
import glob
import os
import sys
from collections import defaultdict

GENE_ORDER = ["HLA-A", "HLA-B", "HLA-C", "HLA-DPA1", "HLA-DPB1", "HLA-DQA1", "HLA-DQB1"]
RNA_COLS = ["RnaTotal", "RnaUnique", "RnaShared", "RnaWild"]

parser = argparse.ArgumentParser(description="Summarize LILAC alleles of an oncoanalyser output folder")
parser.add_argument("output_dir", help="oncoanalyser output folder, with <group_id>/lilac/ subfolders")
parser.add_argument("-o", "--out", help="output TSV (default: <output_dir>/lilac_alleles.tsv)")
parser.add_argument("--rna", action="store_true",
                    help="add RnaUnique counts per allele (NA for samples run without RNA)")
args = parser.parse_args()
out_file = args.out or os.path.join(args.output_dir, "lilac_alleles.tsv")

# Warn about patients without LILAC results (failed or incomplete runs)
for group_dir in sorted(glob.glob(os.path.join(args.output_dir, "*", ""))):
    group_id = os.path.basename(os.path.dirname(group_dir))
    if group_id not in ("logs", "pipeline_info") and not glob.glob(os.path.join(group_dir, "lilac", "*.lilac.tsv")):
        print(f"WARNING: no lilac.tsv for {group_id}", file=sys.stderr)

lilac_files = sorted(glob.glob(os.path.join(args.output_dir, "*", "lilac", "*.lilac.tsv")))
if not lilac_files:
    sys.exit(f"ERROR: no <group_id>/lilac/*.lilac.tsv found in {args.output_dir}")

rows = []
for lilac_file in lilac_files:
    sample_id = os.path.basename(os.path.dirname(os.path.dirname(lilac_file)))
    with open(lilac_file) as f:
        records = list(csv.DictReader(f, delimiter="\t"))
    # Without an RNA BAM, LILAC writes 0 in all Rna columns: report NA rather than 0 expression
    has_rna = any(float(r[c]) > 0 for r in records for c in RNA_COLS)

    # Class I rows all have Genes=MHC_CLASS_1, so the gene comes from the allele (A*01:01 -> HLA-A).
    # Each gene has 2 rows (allele1, allele2), the same allele twice if homozygous
    alleles = defaultdict(list)
    for r in records:
        alleles["HLA-" + r["Allele"].split("*")[0]].append(r)
    # Homozygous at every HLA gene: likely LOH of the HLA region (germline homozygosity at all genes is rare).
    # Tumor-only typing can't tell the two apart, so this is a flag, not a call
    loh_likely = "yes" if all(len({r["Allele"] for r in a}) == 1 for a in alleles.values()) else "no"

    for gene in sorted(alleles, key=lambda g: (GENE_ORDER.index(g) if g in GENE_ORDER else len(GENE_ORDER), g)):
        gene_rows = alleles[gene]
        if len(gene_rows) != 2:
            print(f"WARNING: {sample_id} {gene} has {len(gene_rows)} alleles instead of 2", file=sys.stderr)
        row = [sample_id, gene] + [r["Allele"] for r in gene_rows[:2]]
        row.append("yes" if len({r["Allele"] for r in gene_rows}) == 1 else "no")
        row.append(loh_likely)
        if args.rna:
            row += [r["RnaUnique"] if has_rna else "NA" for r in gene_rows[:2]]
        rows.append(row)

header = ["sample_id", "gene", "allele1", "allele2", "homozygous", "loh_likelihood"]
if args.rna:
    header += ["allele1_RnaUnique", "allele2_RnaUnique"]
with open(out_file, "w", newline="") as f:
    writer = csv.writer(f, delimiter="\t", lineterminator="\n")
    writer.writerow(header)
    writer.writerows(rows)
print(f"{len(lilac_files)} samples, {len(rows)} rows written to {out_file}", file=sys.stderr)
