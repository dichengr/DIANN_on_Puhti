# DIA-NN Parallel Workflow on HPC

Runs DIA-NN over many samples in parallel on HPC.
You organise your data, make a config file, and submit one command — the rest is automatic.

Based on Brett S. Phinney's video [Running DIA-NN on an HPC cluster](https://youtu.be/75Gk6uQclc8?si=zZqzikGoCqnogNtn).

**[→ Open the DIA-NN Config Builder](https://dichengr.github.io/DIANN_on_Puhti/webgui/)** — a web page
that writes the config file for you. No file editing, no Linux needed.

-----

## How it works

The workflow builds a spectral library from your own samples, then re-searches against it
for better quantification. Four steps, submitted for you in order:

1. **Search** — every raw file is searched in parallel against a general predicted library.
2. **Build library** — the hits from all samples are combined into one library specific to your experiment.
3. **Search again** — every raw file is re-searched against that smaller, better library.
4. **Report** — the results are combined into the final quantification tables.

Steps 2–4 are submitted automatically as each one finishes. Runs with more than 400 raw
files are split into batches automatically, because that is Puhti's queue limit per account.

-----

## Setting up a run

### 1. Put your files on Puhti

The workflow lives in `/scratch/project_2000752/DIA-NN`. Make a folder for your experiment
under `04_projects/<your_name>/<your_project>`, with a folder inside it for the raw files:

```bash
cd /scratch/project_2000752/DIA-NN/04_projects/<your_name>
mkdir -p <your_project>/raw_data
```

- **Raw data** (`.d` / `.raw`) → `<your_project>/raw_data/`
- **FASTA** → your experiment folder, or `03_resources/fasta/` to share it
- **Spectral library** → check `03_resources/lib/` first; upload yours there if none fits

**For any files with big size and big amount, recomend using FileZilla or Winscp.**

### 2. Make the config file

**Use the [Config Builder](https://dichengr.github.io/DIANN_on_Puhti/webgui/)** — fill in the
form, paste the line it gives you into terminal. It checks your paths, counts your
raw files, and writes the config into `<your_project>/configs/`.

Or copy `example_config.sh` and edit it by hand:

| Variable | What it is |
| :--- | :--- |
| `DATA_DIRS` | Bash **array** of raw-file folders. Add entries to analyse several batches together. |
| `OUTPUT_DIR` | Where results go. Created if missing. |
| `LIB_FILE` | Spectral library for the first search. |
| `FASTA_FILE` | Protein database. One per run. |
| `CONTAINER_SIF` | DIA-NN version. The name must look like `diann-2.6.1.sif` — the version is read from it. |
| `DIANN_PARAMS` | One line of DIA-NN search flags. |
| `CHUNK_SIZE` | *Optional*, default 350. Jobs queued at once. Leave alone unless told otherwise. |

`DATA_DIRS` is an array — note the brackets:

```bash
DATA_DIRS=(
    "/scratch/project_2000752/DIA-NN/04_projects/<your_name>/<your_project>/raw_data"
)
```

CPUs, memory and time are pre-set in the master scripts, so they are not your concern.

### 3. Submit

One line, from anywhere on Puhti. Only the config path changes between runs:

```bash
/scratch/project_2000752/DIA-NN/02_scripts/diann_runner.sh /scratch/project_2000752/DIA-NN/04_projects/<your_name>/<your_project>/configs/config.sh
```

Job ID numbers mean it worked.

-----

## While it runs, and afterwards

- **Progress:** `squeue --me`, or the Puhti website → active jobs.
- **Results:** `<output>/step4_report/final_report_*.tsv`, plus the protein and peptide matrices.
- **Errors:** every job writes a log to `<output>/logs/` saying exactly what failed.

```
<your_project>/              <- experiment folder
├── raw_data/                <- your .d or .raw files
├── configs/                 <- config files
└── mouse_brain_output/
    ├── logs/
    ├── step1_quant/  step2_lib/  step3_quant/
    └── step4_report/        <- your final report
```

-----

## Search parameters

`DIANN_PARAMS` holds the DIA-NN flags. Full list on the
[DIA-NN command-line reference](https://github.com/vdemichev/DiaNN?tab=readme-ov-file#command-line-reference).

**Do not include** file paths, `--threads`, `--lib`, `--fasta`, `--out` or `--reanalyse` —
the workflow sets those itself, and the four steps already are a reanalysis. The Config
Builder removes them for you and explains why.

One that is easy to get wrong: `--cut K*,R*,!*P` is plain Trypsin (not before proline).
`--cut K*,R*` is Trypsin/P, which cuts before proline too.

-----

## This repository

| | |
| :--- | :--- |
| `src/` | The master scripts, deployed at `02_scripts/` on Puhti. You do not edit these. |
| `webgui/` | The Config Builder page. |
| `example_config.sh` | Config template for editing by hand. |
