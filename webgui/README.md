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

## The contract with the pipeline

The page is only correct as long as it emits a config `diann_runner.sh` can source.
That contract is:

| Variable | Notes |
|---|---|
| `DATA_DIRS` | bash array, each entry double-quoted |
| `OUTPUT_DIR`, `LIB_FILE`, `FASTA_FILE`, `CONTAINER_SIF` | absolute paths, quoted |
| `DIANN_VERSION`, `DIANN_BIN_PATH` | derived from the `.sif` filename — emitted literally, never expanded by the page |
| `DIANN_PARAMS` | search flags only: no paths, no `--threads`, no library flags |
| `CHUNK_SIZE` | written **only** when it differs from the default 350 |

Constants live at the top of the `<script>` block in `index.html`:
`RUNNER`, `CONFIG_HOME_FALLBACK`, `DEFAULT_CHUNK`, `B64_CHUNK`, `MAX_ONE_LINE`.

`RUNNER` is the one fixed path — the shared `diann_runner.sh`. It is called by full
path, so there is no `cd`, the whole submission is a single line, and the user never
has to know or type where the pipeline lives. `diann_runner.sh` resolves its own
script folder internally, so calling it from anywhere works.

**No DIA-NN version is baked in.** Releases come often, so the container is a field
the user fills in each time; the placeholder shows the shape only. Don't turn it back
into a default that quietly goes stale.

**If `config.sh` gains a field,** update `buildConfig()` — and add a golden config to
the test suite (see [Tests](#tests)).

## Why paste rather than download, and why base64

A file downloaded on Windows picks up CRLF line endings, and the cluster fails with
`$'\r': command not found` — a mystifying error for someone with no Linux background.
Pasting avoids both that and any file transfer. Download is kept as a secondary option,
and the page documents the `sed -i 's/\r$//'` fix.

**Everything the user pastes is one line.** Many terminals run a *pasted* block one
line at a time, which tears apart any multi-line construct — a here-document and a
`for` loop were both used here originally and both broke in real use. But text *piped
into* bash never passes through the terminal that way. So each action is a single line:

```
echo '<base64>' | base64 -d | bash
```

One paste, one Enter. The script inside can then use a here-document freely and, more
importantly, format its own output — instead of the terminal echoing every long
/scratch path back between prompts, which is unreadable. The path check prints a
`found` / `MISSING` verdict per path with the path on its own indented line, a raw-file
count, and a closing summary; the config write reports where the file went and what to
run next.

Encoding also means no quote, `$`, backtick or newline in the user's own paths can be
re-interpreted on the way in — the whole class of injection bugs disappears at the
boundary rather than being filtered at it.

Above `MAX_ONE_LINE` the payload is split across independent `printf … >> file` lines
and piped to bash afterwards, in case a terminal's input buffer truncates one enormous
line. Both shapes are tested, including execution one line at a time.

The test suite runs the emitted commands for real — against a scratch config folder,
never `$HOME` — and checks their output, including executing them one line at a time.

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

## Why the trimmer drops some settings entirely

`DIANN_PARAMS` is expanded **unquoted** (`$DIANN_PARAMS`) inside `1.sh`–`4.sh`, so the
shell word-splits it before DIA-NN sees it. A value containing a space or a quote
therefore cannot survive the trip however it is escaped, and a `$` or backtick would
*execute* when the config is sourced. So kept flags and values must match:

```
SAFE_FLAG  = /^[A-Za-z0-9][A-Za-z0-9-]*$/
SAFE_VALUE = /^[A-Za-z0-9.,:*_+=!\/\[\]-]+$/
```

`!` is in the set deliberately — `--cut K*,R*,!*P` is plain Trypsin (not before
proline), the most common enzyme setting there is, and bash does not history-expand
inside a quoted here-document or a non-interactive shell. Dropping it silently sent
searches to DIA-NN's default enzyme. There are tests at both layers; don't remove `!`.

Anything else is dropped and shown in the Removed panel with a reason, rather than
silently corrupted. If DIA-NN ever gains a flag needing a character outside that set,
widen `SAFE_VALUE` — but check first that the value still round-trips through unquoted
word splitting.

Paths get the same treatment in `checkPath`: `"`, `'`, `` ` `` and `$` are hard errors,
because `OUTPUT_DIR="…"` is a double-quoted assignment where they would be re-interpreted.

## What the trimmer removes beyond paths

`--reanalyse` / `--reanalyze` are dropped: the four steps *are* a reanalysis (search,
build a library from every sample, search again against it, report), so doing it inside
one step as well duplicates the work.

A run uses exactly **one** FASTA and **one** spectral library. If the pasted command
listed several of either, the page says so and asks the user to merge or choose — the
form itself only has one field for each.

## Adding a preset

Add an entry to `PRESETS` in `index.html`. Value is a plain DIA-NN flag string —
it goes through the same trimmer as a pasted log, so it cannot smuggle in a path.

## Tests

A three-layer suite (about 180 checks) covers this page. **It is not kept in this
repository** — it lives in the maintainer's working copy, because the repo is meant to
stay a small, readable drop for the group. Ask before changing `index.html` if you want
to run it. The layers are:

- **Page logic** (`run_js_tests.js`) — pulls the `<script>` block out of `index.html`
  and runs the page's own suite against DOM stubs, so the tests exercise the code the
  browser really runs rather than a copy.
- **End-to-end** (`e2e_generate.js`) — drives the real logic with a realistic DIA-NN
  log (Windows paths and all), then proves the result is valid bash, sources cleanly,
  and that the pasted file is byte-identical to the downloaded one. It also runs
  `bash -n` over **every block the page tells a user to paste**. Do not weaken that to
  string matching: a `for … ; do` loop with the `; do` on its own line once shipped
  because the test only checked that the output *contained* the right words.
- **Contract** (`check_configs.sh`) — golden configs through `bash -n` and `source`,
  a mock run of the runner's own file discovery over paths with spaces, the Trypsin
  cleavage spec surviving word splitting, and parity with the production `config.sh`.

The first two layers need a JS runtime; the third is plain bash. **With no runtime at
all, open `index.html?test=1` in a browser** — that runs the page's own logic suite and
prints the results on the page, and it works from the live link above. That is the one
check anybody can do without setting anything up.

## Publishing

The page is served by GitHub Pages from this folder, so **pushing a change to `main`
redeploys it** within about a minute — there is no build step. Everything is inlined in
`index.html`, so it also works by double-clicking the file, or from a USB stick, with no
network at all.

Keep `index.html` as the single source: the tests read that file directly, and a second
copy would drift.
