# Working on Analysis Kit

Moved out of `README.md`, which is the short guide to using the app.

---

## Repository layout

```
app.R                     UI assembly and reactive wiring, nothing else
R/
  setup_packages.R        what the app needs, and the startup check
  deployment.R            local or served, and what that changes
  read_dataset.R          dataset ingestion and profiling
  read_loa.R              the List of Analysis reader, validator and spec
  ui_components.R         the rules behind the interface, as pure functions
  export_results.R        filenames, export settings, writing the workbook
  compare_workbooks.R     cell-by-cell workbook comparison (not bundled)
  generate_manifest.R     deployment tooling (not bundled with the app)
functions/
  ck_analysis_ona_*.R     the analysis pipeline
  format_my_xlsx_*_ordered_n.R   the MMC export formatter
www/                      stylesheet and logo
docs/
  loa-schema.md           the full workbook specification
  loa_template.xlsx       a filled-in template to start from
  deployment.md           deploying to Posit Cloud
  development.md          this file
tests/testthat/           the test suite
```

Everything in `R/` is pure and Shiny-free, which is what makes it testable
without starting a session. `app.R` assembles the interface and connects
reactives; it holds no analysis and no validation.

The analysis and export functions are sourced from `functions/` at startup, so
they can be replaced without touching the app.

**One caution about replacing the formatter.** Every `.R` file in `functions/`
is sourced, so two files defining `format_my_xlsx_variable_x_group()` do not
error — `source()` order silently decides which one survives, and the older
definition can win. The workbook still builds, just without the newer arguments.
When you drop in a new build, retire the old file rather than leaving it beside
the new one. A test enforces this, and every run prints the build that is
actually loaded as the first line of the formatter's log:

```
format_my_xlsx_variable_x_group [simplified build: n-ordering, empty-group drop, NaN blanking, percent_digits]
```

---

## Running the tests

From the project root:

```r
source("tests/testthat.R")
```

Needs `testthat`, `writexl`, `withr` in addition to the app's own packages. The
suite sources everything in `R/` and `functions/`, and covers the workbook
reader and validator, the variable checks, the interface rules, the export, the
deployment behaviour and the app wiring itself through `shiny::testServer()`.

A few tests skip unless the survey packages are installed. None of them write
anything outside a temporary folder, and none install packages.

---

## Performance

Two things dominate how long a run takes, and the first is decided in the
workbook rather than in the code.

### The `level` column

A row with a `level` is estimated by the survey package, which re-subsets the
data once per level of each grouping variable. A row without one goes to fast
tabulation, which does a single pass whatever the disaggregation. Measured on
one `prop_select_one` analysis against one grouping variable, 10,000
respondents:

| levels in the grouping variable | fast | survey |
|---|---|---|
| 2 | 0.005 s | 0.021 s |
| 12 | 0.005 s | 0.057 s |
| 40 | 0.006 s | 0.144 s |
| 200 | 0.005 s | 0.678 s |

Per analysis, per grouping variable. Across 60 analyses and five disaggregations
that is about 3 s against about 55 s, and `analysistools` adds its own work on
top of those survey figures.

**The point estimates are identical either way** — the design affects only the
variance — so a `level` buys nothing except `stat_low` and `stat_upp`. Set it on
the rows that publish a confidence interval and leave it empty elsewhere. The
**List of Analysis** tab reports the split before you run.

### The width of the output

The export costs roughly a fixed 2.4 s per run plus 0.083 s per group column on
a sheet, and every sector sheet repeats every disaggregation twice — once as
percentages and once as counts. Two settings move along that line without
touching a calculation:

- `min_group_n` drops group levels with too few interviews to report. A 200-town
  disaggregation usually has a long tail of towns with a handful of interviews,
  and those columns are neither publishable nor free.
- Fewer grouping variables in `group_analysis`, when a round does not need all
  of them.

Splitting sheets by grouping variable does *not* help: it writes the same cells
across more sheets and pays the per-sheet cost each time.

### Reading a run's own timings

Every run reports how long each stage took, in the **Run log** on the Results
tab:

```
stage checks                     0.11 s
stage prepare the dataset        0.94 s
stage estimate                   0.50 s
stage reshape and label          0.32 s
workbook built in 18.4 s
```

That is the quickest way to find out where a particular dataset spends its time,
rather than reasoning from someone else's.

---

## Checking that a change moved nothing

`R/compare_workbooks.R` compares two results workbooks cell by cell — every
stored value *and* how it is stored, so a number that has quietly become text is
a failure rather than a match. It is development tooling and is not deployed.

```r
source("R/compare_workbooks.R")
ak_expect_same_workbook("reference/old.xlsx", "outputs/new.xlsx")
```

Keep a reference run — one dataset, one List of Analysis, the workbook as it is
produced today — and compare against it after any change to the pipeline or the
formatter. Styling is not compared.

---

## Known limits

- Nothing is written to `outputs/`; the destination is always a folder you pick
  or a download.
- The Results tab previews the first 12 columns of the wide table only.
- Export settings — the blocks layout, one sheet per `sector` — are fixed house
  style. If they need to vary per workbook, an `export` sheet is the natural
  place; see the open questions in [loa-schema.md](loa-schema.md).
- No `renv` lockfile for local development. `manifest.json` covers deployment.
- The export writes a sheet's data area in one pass, which leaves an empty cell
  where the per-question header and spacer rows fall. The workbook is identical
  to read and about a tenth larger on disk — the trade for an export that is
  about four times faster on a wide disaggregation.
