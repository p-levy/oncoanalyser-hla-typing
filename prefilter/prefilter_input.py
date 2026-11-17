#!/usr/bin/env python3
# Prepares the HLA read pre-filter of a samplesheet (see hla_prefilter.slurm):
#   - <fastq_dir>/tasks.tsv: one line per FASTQ row (= one job array task): R1, R2, output prefix
#   - <out_csv>: the samplesheet with FASTQ rows pointing to the filtered FASTQs (bam / redux_dir rows unchanged)
# USAGE: python3 prefilter_input.py <input.csv> <fastq_dir> <out_csv>
import csv
import os
import re
import sys

input_csv, fastq_dir, out_csv = sys.argv[1:4]
fastq_dir = os.path.abspath(fastq_dir)
os.makedirs(fastq_dir, exist_ok=True)

with open(input_csv) as f:
    rows = list(csv.DictReader(f))
header = list(rows[0].keys())

tasks, out, seen = [], [], set()
for r in rows:
    if r["filetype"] != "fastq":
        out.append(r)
        continue
    r1, r2 = r["filepath"].split(";")
    lane = re.search(r"lane:([^;]+)", r["info"])
    prefix = f"{r['group_id']}__{r['sample_id']}__{lane.group(1) if lane else len(tasks) + 1}"
    if prefix in seen:
        sys.exit(f"ERROR: two FASTQ rows give the same output name {prefix}")
    seen.add(prefix)
    # Relative FASTQ paths are relative to the launch folder, like in oncoanalyser
    tasks.append((os.path.abspath(r1), os.path.abspath(r2), prefix))
    out.append({**r, "filepath": f"{fastq_dir}/{prefix}_R1.fq.gz;{fastq_dir}/{prefix}_R2.fq.gz"})

with open(os.path.join(fastq_dir, "tasks.tsv"), "w") as f:
    f.writelines("\t".join(t) + "\n" for t in tasks)
with open(out_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=header, lineterminator="\n")
    w.writeheader()
    w.writerows(out)
print(len(tasks))
