# runAnalysisLocally

The [Analysis Kit](https://github.com/iAthman83/analysiskit) workflow as an R
package. It turns a 4Mi dataset and a **List of Analysis** workbook into a
branded, MMC-styled results workbook — from the console, with no interface and
no script to edit each round.

```r
run <- run_analysis_locally(
  dataset       = "data/mmr_analysis_data_25_26.xlsx",
  loa           = "resources/loa_template.xlsx",
  output_folder = "output"
)
```

The analysis engine, the workbook reader, the validator and the exporter are the
same code the Shiny application uses. What this package adds is a way to call
them: so a run can be scripted, scheduled, repeated over a folder of exports, or
dropped into a larger pipeline.

---

## Contents

- [Why a package](#why-a-package)
- [Installation](#installation)
- [Quick start](#quick-start)
- [The two inputs](#the-two-inputs)
- [The List of Analysis workbook](#the-list-of-analysis-workbook)
- [Doing it a step at a time](#doing-it-a-step-at-a-time)
- [The checks](#the-checks)
- [The output workbook](#the-output-workbook)
- [Function reference](#function-reference)
- [Things that will bite you](#things-that-will-bite-you)
- [Speed, and which engine runs](#speed-and-which-engine-runs)
- [Package layout](#package-layout)
- [Running the tests](#running-the-tests)
- [Known limits](#known-limits)

---

## Why a package

The application is the right tool when someone is analysing one round of data
once, and wants to see the checks before committing. It is the wrong tool for
everything else: running the same List of Analysis over twelve country exports,
re-running last month's analysis after a cleaning fix, calling the pipeline from
a larger script, or doing any of that on a schedule.

A package also fixes something the application could not. Analysis Kit sources
its analysis and export code from a `functions/` folder, and every `.R` file in
there gets sourced — so two files defining `format_my_xlsx_variable_x_group()`
do not error. `source()` order silently decides which survives, and the older
definition can win, producing a workbook that builds correctly and formats
wrongly. In a package there is one definition, resolved at build time. A test
pins it.

---

## Installation

R 4.1 or later.

```r
# install.packages("remotes")
remotes::install_github("iAthman83/runAnalysisLocally")
```

Installing brings in what every run needs: `dplyr`, `tidyr`, `stringr`,
`readxl`, `openxlsx`.

Three packages are **optional**, and only one feature reaches them:

| Package | Needed for | Install |
|---|---|---|
| `srvyr` | confidence intervals (an `analysis` row with a `level`) | `install.packages("srvyr")` |
| `analysistools` | the same | `remotes::install_github("impact-initiatives/analysistools")` |
| `cleaningtools` | rebuilding select_multiple parent columns (`recreate_sm_parents`) | `remotes::install_github("impact-initiatives/cleaningtools")` |

**If you never set a `level`, you never need them.** The fast tabulation engine
produces the same point estimates without a survey design, and does it in a
fraction of the time — see [Speed](#speed-and-which-engine-runs).

To see what you have:

```r
check_analysis_packages()
#>         package     need installed version                            install
#> 1         dplyr required      TRUE   1.1.4
#> 6         srvyr optional     FALSE    <NA>        install.packages('srvyr')
#> 7 analysistools optional     FALSE    <NA> remotes::install_github('impac...
```

---

## Quick start

```r
library(runAnalysisLocally)

# 1. A folder structure to work in, if you want one
setup_project_folders()          # creates data/, resources/, output/

# 2. A List of Analysis to fill in
copy_loa_template("resources")

# 3. Check before you commit to a run
checks <- check_analysis_inputs(
  dataset = "data/mmr_analysis_data_25_26.xlsx",
  loa     = "resources/loa_template.xlsx"
)
checks
#> <analysis_readiness>
#>   dataset          : mmr_analysis_data_25_26.xlsx (6,001 rows x 214 columns)
#>   List of Analysis : loa_template.xlsx (38 analyses)
#>   disaggregations  : Overall, Respondent_Gender, Region_of_interview
#>   problems         : 0 must fix, 2 warning(s)
#>   variables absent : 1 of 41 - Q91
#>   ready to run     : yes

ak_problems_display(checks$problems)     # every problem, must-fix first
subset(checks$coverage, !present)        # what the dataset does not have

# 4. Run it
run <- run_analysis_locally(
  dataset       = "data/mmr_analysis_data_25_26.xlsx",
  loa           = "resources/loa_template.xlsx",
  output_folder = "output"
)
run
#> <analysis_run>
#>   dataset      : mmr_analysis_data_25_26.xlsx
#>   analyses     : 38
#>   disaggregated: Overall, Respondent_Gender, Region_of_interview
#>   result table : 412 rows x 190 columns
#>   elapsed      : 14.6 seconds
#>   saved        : output/analysiskit_mmr_analysis_data_25_26_20260908-142233.xlsx
```

The results are in `run$results`, the pipeline's diagnostics in `run$log`, and
the file at `run$output_path`.

### The same List of Analysis over a folder of exports

```r
runs <- lapply(
  list.files("data", pattern = "[.]xlsx$", full.names = TRUE),
  run_analysis_locally,
  loa           = "resources/loa.xlsx",
  output_folder = "output",
  verbose       = FALSE
)

vapply(runs, function(r) basename(r$output_path), character(1))
```

### Analyse without writing anything

```r
run <- run_analysis_locally("data/export.xlsx", "resources/loa.xlsx")
run$output_path   # NULL — nothing was written
head(run$results$combined_results)
```

---

## The two inputs

**The dataset** — a 4Mi ONA export, `.csv` or `.xlsx`.

**Row 1 is expected to be the label row.** ONA puts the question text there, and
the pipeline sets it aside so it never counts as a respondent. Leave it in
place: `read_analysis_dataset()` reads the file as it is, and the pipeline
handles the row under the `skip_label_row` setting. If your dataset has no label
row, say so by setting `skip_label_row` to `FALSE` in the workbook's `settings`
sheet — otherwise the first respondent is silently dropped.

Choice labels live in the select_multiple child columns
(`Q78/Economic reasons`), which is how ONA exports them. Column names are
preserved exactly, because those labels contain characters R would otherwise
mangle.

You can also pass a **data frame** you already have in the session — a cleaned
export, say — instead of a path. It reads identically:

```r
run_analysis_locally(my_cleaned_export, "resources/loa.xlsx", "output")
```

**The List of Analysis** — the workbook below. `.xlsx` is effectively required:
a `.csv` carries only one table, so it is read as the `analysis` sheet alone and
every other sheet falls back to defaults. No disaggregations, no selection
counts, no settings.

---

## The List of Analysis workbook

```r
copy_loa_template("resources")     # a filled-in workbook to start from

# The full specification: every sheet, every setting, every validation rule
file.show(system.file("extdata", "loa-schema.md", package = "runAnalysisLocally"))
```

Up to seven sheets. Only `analysis` is required; a missing or empty sheet means
"not requested", and the pipeline's own default applies — never a guessed value.

Sheet names are matched case-insensitively, and after collapsing spaces and
hyphens to underscores, so `Group Analysis` and `group_analysis` both resolve.
An **unrecognised** sheet name is a fatal error, not a silent skip: a typo would
otherwise look exactly like a deliberate decision not to configure that sheet.
Sheets named `readme` or `notes`, or beginning with `_`, are ignored, so the
workbook can carry its own instructions.

### `analysis` — one row per requested analysis

| Column | Notes |
|---|---|
| `analysis_type` | `prop_select_one`, `prop_select_multiple`, `mean`, `median` or `ratio` |
| `analysis_var` | the dataset variable, or the select_multiple parent |
| `level` | leave empty for no confidence interval. `0.95` (or `95`) asks for one |
| `analysis_var_numerator` / `_denominator` | required when `analysis_type` is `ratio` |
| *anything else* | free metadata — name it in `settings/extra_columns` to carry it into the output |

`sector` is the metadata column the exporter looks for: each of its values
becomes one sheet in the results workbook.

`count_select_multiple`, `combination_select_multiple` and
`exclusive_combination_select_multiple` are **not** valid here. They are
produced from the sheets below and appear only in the output; writing one into
`analysis` aborts the run.

### `group_analysis` — the disaggregations, and their output names

| raw_data_name | new_name | include |
|---|---|---|
| Q27 | Respondent_Gender | TRUE |
| Q42 | Region_of_interview | TRUE |

**Write raw question codes everywhere in the workbook.** This mapping is applied
to the dataset — parents *and* their select_multiple children — and to every
other sheet, so `Q27` works in the `analysis` sheet too and the readable name
appears only in the output.

`Overall` is prepended automatically and must not be listed. Row order sets the
order of the column blocks after `Overall`.

### `count_selections` — how many choices each respondent picked

One column, `analysis_var`, one row per select_multiple parent. Reports none /
exactly one / more than one.

Read the "no choice selected" figure carefully: it counts respondents with
nothing recorded, which lumps together those never asked the question and those
asked who left it blank. If the question was asked of everyone the two are the
same thing; if it was conditional, this is "not answered", not "declined".

### `count_combinations` — which combination of choices they picked

| analysis_var | choice_label | display_name |
|---|---|---|
| Q78 | Economic reasons | Economic |
| Q78 | Armed conflict, generalised violence, and insecurity | Conflict |

Gives four mutually exclusive rows — *Economic + Conflict*, *Economic*,
*Conflict*, *None of these* — that add to 100%. `choice_label` must match the
export exactly, punctuation and all; a mistyped label is a fatal error with a
"did you mean" suggestion rather than a table that looks fine and is wrong.

### `count_exclusive_combinations` — the strict version

Same three columns. `count_combinations` asks *"selected Economic, whatever
else"*; this asks *"selected Economic and nothing else at all"*. Rows read
*Economic only*, and the catch-all is *Other choices only*. A question can carry
both blocks.

> ⚠ **These rows sit on a smaller denominator than every other table in the
> output.** Anyone who picked a listed choice *together with* an unlisted one
> belongs to no category and leaves the base entirely. That is what "only"
> means, and it is invisible in the finished workbook — the percentages look
> like every other percentage.
>
> `run_analysis_locally()` prints how many that is, per question, when you print
> the run. **Footnote it wherever these percentages are published**: two tables
> in the same workbook, both labelled as percentages of respondents, will not
> share a denominator.

### `exclude_choices` — labels that leave the denominator

One `choice_label` per row (`Don't know`, `Refused`). Its own sheet rather than a
setting because 4Mi labels contain commas, and a comma-separated list in one
cell would split one label into three and match nothing.

Note what this does: it changes the **denominator**. Someone who picked an
excluded choice leaves the base for that question entirely — the rows are not
merely hidden. Grouping variables are untouched.

### `settings` — everything else

Two columns, `setting` and `value`, one row per setting, order irrelevant.
Forty-two keys are accepted, covering every remaining argument of the pipeline:

```
sm_separator        /
skip_label_row      TRUE
value_columns       stat,n,n_total
extra_columns       sector
engine              auto
weight_column       weight
min_group_n         30
```

`loa_settings_schema()` lists every accepted key with its type.

A **misspelled key is a fatal error**, not a silent skip — a typo that was
ignored would look exactly like a setting that had been applied, which is the
failure this sheet exists to prevent. A blank value means "not set", and the
pipeline's default applies.

Wrap a value in double quotes to keep a leading or trailing space. A spreadsheet
drops them, so `" only"` and `" + "` need the quotes or the label renders
`Economiconly`.

---

## Doing it a step at a time

`run_analysis_locally()` is these five steps in order. Each is available on its
own, so a run can be inspected or altered at any point.

```r
# 1. Read
dataset  <- read_analysis_dataset("data/export.xlsx")
workbook <- read_loa_workbook("resources/loa.xlsx")

dataset_overview(dataset)      # file, size, rows, columns, duplicate rows
dataset_columns(dataset)       # type, missing and unique per column
ak_sheet_summary(workbook)     # which sheets were supplied, which defaulted

# 2. Validate — never stops, returns the problems
problems <- validate_loa(workbook, dataset$data)
coverage <- loa_variable_coverage(workbook, dataset$data)

# 3. Build the specification — the one internal description of a run
spec <- build_analysis_spec(workbook, dataset$data)
spec
#> <analysis_spec>
#>   analyses          : 38
#>   group variables   : Overall, Respondent_Gender, Region_of_interview
#>   ...

analysis_spec_args(dataset$data, spec)   # the pipeline call, without running it

# 4. Run
results <- run_analysis_spec(dataset$data, spec, verbose = TRUE)

# 5. Export
path <- ak_export_results(
  results      = results,
  spec         = spec,
  folder       = "output",
  dataset_name = dataset$filename
)
```

### Bypassing the workbook entirely

`run_group_analysis_pipeline()` is the engine, and it takes plain R arguments.
Use it for a one-off that does not deserve a workbook, or when the arguments are
being generated by something else:

```r
results <- run_group_analysis_pipeline(
  dataset         = dataset$data,
  loa             = data.frame(
    analysis_type = c("prop_select_one", "mean"),
    analysis_var  = c("Q27", "Q29")
  ),
  group_variables = c("Overall", "Q42"),
  count_combinations = list(
    Q78 = c(Economic = "Economic reasons", Conflict = "Armed conflict, generalised violence, and insecurity")
  ),
  exclude_choices = c("Don't know", "Refused"),
  engine          = "fast"
)
```

Its fifty arguments are documented in `?run_group_analysis_pipeline`. Anything
the workbook can set, this can set.

---

## The checks

Both files are compared against each other, and the severity rule throughout is:

> **Must fix** when the run would produce *wrong or misleading* output.
> **Warning** when it would only produce *less* output.

So a variable named in the workbook but absent from the dataset **warns** — that
analysis is skipped, the rest still runs. But two grouping variables where one
name contains the other is a **must fix**: the output table would be correct
while the map that labels its columns would not. With both `Region` and
`Region_of_origin` in play, `stat_Region_of_origin_East Africa` matches
`_Region_` first, and every `Region_of_origin` column is attributed to `Region`.

`run_analysis_locally()` and `run_analysis_spec()` **refuse to start** when
anything is fatal, and the error names every problem at once. That is the point:
the alternative is a workbook full of plausible numbers attributed to the wrong
disaggregation.

Warnings do not stop a run — but they change what is in the file, so `run$log`
is worth reading rather than skipping. A grouping variable dropped, a
`Don't know` label that matched nothing, a town set aside for having four
interviews: all warnings, all consequential.

**Variable coverage** (`loa_variable_coverage()`) lists every dataset variable
the workbook names, where it is named, and whether your dataset has it. It is
the quickest way to spot a List of Analysis from the wrong round. Presence uses
the pipeline's own rule, so a select_multiple parent counts as present when its
child columns are there, even though ONA did not export the concatenated parent.

---

## The output workbook

One MMC-branded `.xlsx`, styled by `format_my_xlsx_variable_x_group()`:

- one small table per question, percentages on the left, matching counts on the
  right
- disaggregation groups ordered by sample size, largest first
- one sheet per `sector`
- a `readme` sheet recording the dataset, the List of Analysis, the
  disaggregations and every setting that was applied — so a file found six
  months later can be traced back to what produced it

Named `analysiskit_<dataset stem>_<YYYYmmdd-HHMMSS>.xlsx`. An existing file is
**never** overwritten; a second run in the same second gets a `_1` suffix.

### Number formats

**Percentages are shown to the nearest whole number**, so `66.8039538714992`
prints as `67%`. That is a *display* format, not a rounded value — the cell
still holds every digit. It matters: a column of whole-number percentages
continues to sum and average correctly, and anyone who needs the precision can
widen the format in Excel without re-running anything.

Means and medians keep two decimals; counts are whole numbers.

To publish decimals instead, pass `percent_digits` to the formatter directly, or
change it in `ak_export_settings()`. `1` gives `66.8%`.

### Nothing is written until the analysis succeeds

The output folder is checked for existence and write access **before** the
analysis starts, so a long run is never lost to a read-only destination. And if
the analysis succeeds while only the saving fails, the results are still
returned and a warning says what went wrong:

```r
run$results      # the analysis, intact
run$save_error   # why the file was not written
```

A long run is not thrown away over a bad folder.

---

## Function reference

Anything that **runs an analysis** is named `run_*`. Everything else reads,
validates, reshapes or writes.

### Running

| Function | Does |
|---|---|
| `run_analysis_locally()` | the whole workflow: read, check, run, export |
| `run_analysis_spec()` | run an `analysis_spec` |
| `run_group_analysis_pipeline()` | the engine, with plain R arguments |

### Reading

| Function | Does |
|---|---|
| `read_analysis_dataset()` | read and profile a `.csv` / `.xlsx` dataset |
| `read_uploaded_dataset()` | the same reader, from an upload record |
| `dataset_overview()`, `dataset_columns()` | profile a dataset |
| `read_loa_workbook()` | read every recognised sheet, interpreting nothing |
| `copy_loa_template()` | write the template workbook somewhere |

### Checking

| Function | Does |
|---|---|
| `check_analysis_inputs()` | everything a run checks, with nothing run |
| `validate_loa()` | every schema check; returns problems, never stops |
| `loa_variable_coverage()`, `loa_coverage_summary()` | which variables the workbook names, and whether the dataset has them |
| `loa_has_errors()` | is the run blocked |
| `ak_problem_counts()`, `ak_problems_display()` | count and format problems |
| `ak_sheet_summary()` | which sheets were supplied |
| `ak_step_states()`, `ak_can_run()` | the readiness gate |
| `check_analysis_packages()` | required and optional packages, and what is installed |
| `loa_settings_schema()`, `loa_known_sheets()`, `loa_known_analysis_types()` | the schema itself |

### Specifying

| Function | Does |
|---|---|
| `build_analysis_spec()` | workbook → the one internal description of a run |
| `analysis_spec_args()` | the pipeline call, without running it |
| `apply_rename_map()` | rename a dataset, parents *and* select_multiple children |

### Exporting

| Function | Does |
|---|---|
| `ak_export_results()` | write a completed run to a folder |
| `format_my_xlsx_variable_x_group()` | the MMC-branded formatter |
| `ak_export_settings()` | the formatter arguments a run implies |
| `ak_prepare_for_export()` | handle the separator rows before formatting |
| `ak_output_filename()`, `ak_check_folder()`, `ak_provenance()` | filenames, destination, the readme record |
| `ak_exclusive_base_note()` | the exclusive-denominator caveat, in sentences |

### The pipeline's own parts

Every stage of the engine is exported as a `ck_*` function — `ck_fast_analysis()`,
`ck_exclude_choices()`, `ck_add_choice_combinations()`,
`ck_pivot_variable_x_group()` and the rest — so an unusual analysis can be
assembled from the pieces. `ls("package:runAnalysisLocally")` lists them.

### `setup_project_folders()`

Unchanged from the original package: creates `data/`, `resources/` and
`output/`, skipping what already exists.

---

## Things that will bite you

**The label row.** Row 1 of an ONA export is question text. Left in place it is
counted as a respondent: it adds a bogus category to every proportion and
becomes `NA` for every mean. The pipeline removes it by default. If your dataset
has no label row and you do not set `skip_label_row` to `FALSE`, your first
respondent is silently dropped.

**`exclude_choices` changes the denominator.** It is not a filter on the output
rows. Someone who picked `Don't know` leaves the base for that question
altogether — which is what "of those who answered" means, and is why dropping
the rows afterwards would be the opposite of correct.

**Exclusive combinations do not share a denominator with anything else.** See
the warning above. Print the run and read what it tells you.

**Names that contain other names.** Two `new_name` values where one contains the
other is fatal, and rightly so. Containment anywhere counts, not just a prefix:
`of` and `Region_of_origin` collide too.

**A group level literally called `Overall`.** It produces
`stat_<group>_Overall`, which the column matcher attributes to the Overall
block. Checked against the real levels in your dataset, and fatal.

**`recreate_sm_parents` needs a column literally named `uuid`.** The pipeline
hardcodes that name.

**Weights and strata are optional, and strata only affect the variance.** Under
`engine = "fast"` a `strata_column` changes nothing at all, and the pipeline
says so rather than letting you believe otherwise.

---

## Speed, and which engine runs

The point estimate of a weighted mean, proportion or ratio is `sum(w*x)/sum(w)`
whatever the strata are. So when an `analysis` row has no `level`, no confidence
interval was asked for, there is nothing for the survey package to do, and the
row is tabulated in one pass instead.

Measured on a 6,000 × 210 export, 200-level disaggregation, 10 questions:

| Engine | Time |
|---|---|
| `survey` (`svyby`) | 9.43 s |
| `fast` (tabulation) | 0.05 s |

`engine = "auto"` (the default) routes each row by whether it asked for an
interval. `"fast"` forces tabulation everywhere and needs neither `srvyr` nor
`analysistools`. `"survey"` forces the old behaviour.

`min_group_n` is the other lever: a 200-town disaggregation usually contains
towns with a handful of interviews, whose estimates are not reportable and are
also what makes the run slow.

---

## Package layout

```
R/
  runAnalysisLocally-package.R  package documentation
  run_local.R                   the run_* entry points and input coercion
  checks.R                      the readiness rules and check_analysis_inputs()
  read_dataset.R                dataset ingestion and profiling
  read_loa.R                    the List of Analysis reader, validator and spec
  export_results.R              filenames, export settings, writing the workbook
  analysis_pipeline.R           the analysis engine (ck_* and the pipeline)
  format_xlsx.R                 the MMC export formatter
  setup_project_folders.R       the project folder scaffold
inst/extdata/
  loa-schema.md                 the full workbook specification
  loa_template.xlsx             a filled-in template to start from
tests/testthat/                 the test suite
```

`read_loa.R`, `export_results.R`, `analysis_pipeline.R` and `format_xlsx.R` are
ported from Analysis Kit **unchanged in behaviour**, so a fix in either place
can be carried across by diff. `run_local.R` and `checks.R` are what this
package adds; `checks.R` is the Shiny-free half of the application's
`ui_components.R`.

The application's `app.R`, `deployment.R`, `manifest.R` and `setup_packages.R`
have no counterpart here: they exist to serve and install an interface.

---

## Running the tests

```r
devtools::test()
# or
testthat::test_local()
```

Needs `testthat` and `writexl` in addition to the package's own dependencies.
The suite covers the workbook reader and validator, the variable checks, the
readiness rules, the export, the exclusive combinations, the percentage
formatting and the `run_*` entry points. Nothing is written outside a temporary
folder, and nothing installs packages.

A full check:

```r
devtools::check()
```

Two tests skip in environments where they cannot be meaningful — one needs a
folder the current user genuinely cannot write to, which is not true when
running as root.

---

## Known limits

- Export settings — the blocks layout, one sheet per `sector`, whole-number
  percentages — are fixed house style, derived from the run rather than
  configurable per workbook. If they need to vary, an `export` sheet is the
  natural place; see the open questions in `loa-schema.md`.
- `analysis_type_labels` is not settable from the workbook. The eight built-in
  labels are it.
- No `renv` lockfile. `DESCRIPTION` pins the dependencies but not their
  versions.
- The workbook is the single source of truth for a run, and `...` overrides it.
  There is deliberately no mechanism for a partial override that gets recorded
  in the output's provenance — so a run reproduced from the readme sheet alone
  will not include anything passed through `...`.
