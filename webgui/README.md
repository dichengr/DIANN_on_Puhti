# DIA-NN Config Builder

**Live: <https://dddcr.github.io/DIANN_on_Puhti/webgui/>**

A single web page that writes a `config.sh` for the group's DIA-NN pipeline, so a
biologist can start a run without editing any file on the cluster.

`index.html` is self-contained — no server, no install, no build step. It works
published as a link *and* by double-clicking the file. **It never contacts the
cluster**; it only produces text for the user to paste.

## What it does

1. **Paths** — raw folder(s), output, library, FASTA, container. Shape-checked live
   (absolute, not Windows, sensible extensions). Emits a paste-to-verify command,
   since the page cannot see the cluster itself.
2. **Parameters** — the user pastes the command line from their own DIA-NN log; the
   page strips what the pipeline supplies and keeps the science, showing
   Kept / Removed-with-reason / Warnings.
3. **Config** — live preview, plus a block of standalone commands that writes the
   file on the cluster in one paste.
4. **Run** — one line that submits the whole workflow, monitoring, and where results land.

## Where things are placed

Everything for one experiment sits in one folder. Given a raw folder
`.../Vitreous_Fluid/MS_RERUN_RAW_PLT2-PLT3`, the page derives:

| | |
|---|---|
| output | `.../Vitreous_Fluid/<run name>_output` |
| configs | `.../Vitreous_Fluid/configs/` |
| config file | `.../Vitreous_Fluid/configs/<run name>_config.sh` |

Both come from `parentOf(first raw folder)` — the experiment folder. The run name is
part of the output folder so two experiments sharing a folder cannot collide on
`.quant` filenames. `configHome()` falls back to `~/diann_configs` only when no usable
raw folder has been entered yet.

The staging file for the chunked fallback lives in `$HOME`, **not** the configs folder:
that folder is created by the script itself, so writing the payload there would fail
before the script ever ran.


## What the trimmer removes beyond paths

`--reanalyse` / `--reanalyze` are dropped: the four steps *are* a reanalysis (search,
build a library from every sample, search again against it, report), so doing it inside
one step as well duplicates the work.

A run uses exactly **one** FASTA and **one** spectral library. If the pasted command
listed several of either, the page says so and asks the user to merge or choose — the
form itself only has one field for each.
