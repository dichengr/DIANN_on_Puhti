# DIA-NN Parallel Workflow Guide for Puhti

This guide explains how to use our automated workflow to run DIA-NN on a large number of samples in parallel on the Puhti.csc.fi cluster.

The idea is based on Brett S. Phinney's Youtube video [Running DIA-NN on an HPC cluster](https://youtu.be/75Gk6uQclc8?si=zZqzikGoCqnogNtn)

-----

## Start here: the config builder

**[→ Open the DIA-NN Config Builder](https://dddcr.github.io/DIANN_on_Puhti/webgui/)**

A web page that writes your configuration file for you. Fill in four paths, paste the
settings from your own DIA-NN, and it gives you two lines to copy into a terminal — one
that writes the config, one that starts the run. No file editing, no Linux knowledge
needed. It never contacts the cluster; it only produces text for you to paste.

If you would rather write the config by hand, everything it does is described in
[Setting up a run](#step-2-create-your-config-file) below.

-----

## Overview

This system automates the 4-step DIA-NN workflow to maximize speed and ensure consistent results. You don't need to edit the core scripts or submit jobs manually. You only need to:

1.  Organize your data.
2.  Create a configuration file.
3.  Run a single submission command.

-----

## How This Workflow Works

This workflow is designed to first build a high-quality, experiment-specific spectral library from your data, and then use that library to get the best possible quantification.

Step 1: Initial Parallel Search

All your raw files are searched simultaneously against a large, general "predicted" library. The goal is to quickly identify every peptide that could possibly be in your samples.

Step 2: Create a Project-Specific Library

The results from all the initial searches are combined into a single, smaller library that is tailored to your specific experiment. It only contains peptides that were actually observed in your samples.

Step 3: Second Parallel Search

All your raw files are searched again, but this time against the smaller, high-quality project library created in Step 2. This re-analysis is faster and more accurate.

Step 4: Generate Final Report

The refined results from the second search are combined to generate the final quantification tables for your analysis.

**Large projects are split automatically.** Puhti allows 400 queued jobs per account, so
runs with more raw files than that are submitted in batches, each waiting for the last to
finish. You do not have to do anything differently.

-----

## What is in this repository

| | |
| :--- | :--- |
| `src/` | The master scripts. These live on Puhti at `/scratch/project_2000752/DIA-NN/02_scripts/` and you do not edit them. |
| `webgui/` | The config builder page. Served at the link above. |
| `example_config.sh` | A configuration file to copy and edit, if you are not using the builder. |

-----

### Folder Structure

The entire system is organized to keep shared files separate from your individual projects.

```
DIA-NN/
├── 01_containers/         (Contains the DIA-NN .sif files)
├── 02_scripts/            (Contains the master scripts)
├── 03_resources/          (Contains shared lib and fasta files)
│    ├── lib/
│    └── fasta/
└── 04_projects/           (This is where you'll create your project folders)
     └── userA/
           └── projectX/            <- the experiment folder
                ├── raw_data/       <- your .d or .raw files
                │   ├── sample1.d
                │   └── sample2.d
                ├── configs/        <- config files (the builder puts them here)
                └── myrun_output/
                        ├── logs/
                        ├── step1_quant/
                        ├── step2_lib/
                        ├── step3_quant/
                        └── step4_report/   <- your final report
```

Keeping the raw folder, the configs folder and the output folder side by side in one
experiment folder means everything for a run stays together. The builder follows this
layout automatically.

-----

## How to Run a New Project

### Step 1: Set Up Your Project Folder

First, log into [puhti.csc.fi](https://www.puhti.csc.fi/public/). The main workflow is in `/scratch/project_2000752/DIA-NN`. Create a directory for your project inside `04_projects`, under your own username folder.

```bash
# Example for a new project called 'mouse_brain'
cd /scratch/project_2000752/DIA-NN/04_projects/userx
mkdir -p mouse_brain/raw_data
```

Then put your files in place:

- **Raw data (`.d` / `.raw`)** → your project's `raw_data/` folder.
- **FASTA (`.fasta`)** → your project folder, or `03_resources/fasta/` if others will reuse it.
- **Spectral library (`.speclib`)** → check `03_resources/lib/` first; if a suitable one for your proteome is already there, use it. Otherwise upload yours there.

**The Puhti web interface has a 10 GB upload limit.** For larger files, like a big spectral library, use [Allas](https://allas.csc.fi), CSC's object storage:

```bash
module load allas
allas-conf
a-get your_object_name  # downloads into current dir
```

### Step 2: Create Your Config File

This tells the workflow where your files are and what DIA-NN settings to use.

**The easy way** — open the **[Config Builder](https://dddcr.github.io/DIANN_on_Puhti/webgui/)**, fill in the form, and paste the line it gives you into a Puhti terminal. It checks your paths, counts your raw files, and writes the config into your project's `configs/` folder.

**By hand** — copy `example_config.sh` into your project and edit it. These are the variables:

| Variable | What it is |
| :--- | :--- |
| `DATA_DIRS` | A bash **array** of folders holding your raw files. Add more entries to analyse several batches together. |
| `OUTPUT_DIR` | Where all results are created. Made for you if it does not exist. |
| `LIB_FILE` | The spectral library for the first search. |
| `FASTA_FILE` | Your protein database. One FASTA per run. |
| `CONTAINER_SIF` | The DIA-NN version to use. The version is read from the filename, so it must look like `diann-2.6.1.sif`. |
| `DIANN_PARAMS` | One line of DIA-NN search flags (see the reference below). |
| `CHUNK_SIZE` | *Optional.* How many jobs to queue at once, default 350. Leave it alone unless told otherwise. |

`DATA_DIRS` is an array, so it is written like this — note the brackets:

```bash
DATA_DIRS=(
    "/scratch/project_2000752/DIA-NN/04_projects/userx/mouse_brain/raw_data"
)
```

**Note: Cluster resource settings (CPUs, memory, time) are pre-set in the master scripts for consistency.**

### Step 3: Submit the Workflow

One line, from anywhere on Puhti. The path to the master script never changes; only your config path does.

```bash
/scratch/project_2000752/DIA-NN/02_scripts/diann_runner.sh /scratch/project_2000752/DIA-NN/04_projects/userx/mouse_brain/configs/mouse_brain_config.sh
```

## What Happens Next?

The script prints Job IDs and the whole workflow then runs on its own — steps 2, 3 and 4 are submitted automatically as each one finishes. You do not run them yourself.

  * **To monitor your jobs:** `squeue --me`, or the Puhti website → active jobs.
  * **To check your results:** the final report lands in `<output>/step4_report/` as `final_report_*.tsv`, together with the protein and peptide matrices.
  * **To check for errors:** every job writes a log into `<output>/logs/`. If something fails, that folder says exactly what.

-----

## DIA-NN Parameter Reference

You control the analysis through the `DIANN_PARAMS` variable in your config file.

The full, official list of all command-line flags is on the **[DIA-NN GitHub Page](https://github.com/vdemichev/DiaNN?tab=readme-ov-file#command-line-reference)**.

Do **not** put file paths, `--threads`, `--lib`, `--fasta`, `--out` or `--reanalyse` in
`DIANN_PARAMS`. The workflow supplies those itself, and the four steps already are a
reanalysis. The config builder strips them for you and tells you why.

### Common Parameters

| Parameter | Example Value | What It Does |
| :--- | :--- | :--- |
| `--qvalue` | `0.01` | Sets the Precursor FDR (q-value) cutoff. 0.01 is 1%. |
| `--missed-cleavages`| `1` | Sets the maximum number of missed enzyme cuts allowed. |
| `--met-excision` | (no value) | Tells DIA-NN to consider peptides with the N-terminal methionine removed. |
| `--mass-acc` | `15` | Sets the MS2 fragment mass accuracy in ppm. |
| `--mass-acc-ms1` | `15` | Sets the MS1 precursor mass accuracy in ppm. |
| `--min-pep-len` | `8` | Sets the minimum length for a peptide to be considered. |
| `--fixed-mod` | `UniMod:4,57.021464,C` | Sets a fixed modification. The example is for carbamidomethylation on Cysteine. |
| `--var-mod` | `UniMod:35,15.994915,M` | Sets a variable modification. The example is for Oxidation on Methionine. The format is `UniMod:ID,MassShift,AminoAcids`. |
| `--cut` | `K*,R*,!*P` | Defines the enzyme cleavage rule. This example is Trypsin: cut after Lysine (K) and Arginine (R), but **not** before Proline (`!*P`). Use `K*,R*` for Trypsin/P, which cuts before Proline too. |

-----

**If confused and want to add more customized parameters, AI(ChatGPT, Gemini) is very helpful, but remember double check the parameter is really exist on DIAN-NN Github page**
