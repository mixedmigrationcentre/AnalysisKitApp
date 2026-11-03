# Analysis Kit App

Turns a 4Mi dataset and a **List of Analysis** workbook into an MMC-styled
results file. Upload two files, click one button.

---

## Open it

### Online

**[abu-analysiskit.share.connect.posit.cloud](https://abu-analysiskit.share.connect.posit.cloud/)**

Nothing to install. This is the copy to send people. The results workbook
arrives as a download.

### Or run it locally

Open `analysiskitapp.Rproj` in RStudio and run:

```r
shiny::runApp()
```

The first launch installs what it needs from CRAN. If something is missing, the
app says so — with the command that fixes it — before the interface appears.
Running locally you also pick a folder, and the workbook is saved there as well
as offered as a download.

---

## Use it

Five steps. The app shows which one you are on.

### 1. Upload the dataset

A 4Mi ONA export, `.csv` or `.xlsx`, up to about 100 MB. Row 1 should be the
label row; the app sets it aside so it is never counted as a respondent.

### 2. Upload the List of Analysis

The workbook that says which analyses to run. Use `.xlsx` — a `.csv` carries
only one table, so everything except the analysis list falls back to defaults.

Start from the template: **Download the List of Analysis template** in the
sidebar. Write raw question codes (`Q27`, `Q78`) everywhere in it; the app puts
the readable names in the output. Every sheet and setting is documented in
[docs/loa-schema.md](docs/loa-schema.md).

### 3. Read the checks

They run by themselves the moment both files are in.

- **Red** must be fixed. The run button stays disabled until it is.
- **Amber** is worth reading, but you can run.
- **Variable coverage** is the quickest way to spot a List of Analysis from the
  wrong round.
- **Estimation engine** says how many analyses will take the slow route. See
  [One thing worth knowing](#one-thing-worth-knowing).

### 4. Choose where to save

Online this step settles itself: there is no folder of yours on the server, so
the workbook arrives as a **download**. Running locally, pick the folder to save
into.

### 5. Run the analyses

The progress bar carries the pipeline's own messages — variables skipped,
choices excluded, groups set aside, and how long each stage took. They are all
kept in the **Run log** on the Results tab.

Nothing is written to disk unless the run finishes without error.

---

## What you get

One MMC-branded `.xlsx`:

- one small table per question, percentages on the left, matching counts on the right
- disaggregation groups ordered by sample size, largest first
- one sheet per `sector`
- a `readme` sheet recording the dataset, the List of Analysis and every setting used

Percentages show to the nearest whole number. That is a *display* format — the
cell still holds every digit, so the column still sums and averages correctly.
Means and medians keep two decimals.

Named `analysiskit_<dataset>_<date-time>.xlsx`. An existing file is never
overwritten. A **Download** button is offered as well as the saved copy.

---

## One thing worth knowing

The `level` column of the `analysis` sheet decides how long a run takes.

Leave it empty unless that row publishes a confidence interval. A row with a
level is estimated by the survey package, which gets slower the more
disaggregation groups you have; a row without one is estimated by fast
tabulation, which does not. **The percentages are identical either way** — a
level only adds the confidence-interval columns.

The **List of Analysis** tab tells you how many rows will take the slow route
before you run.

---

## More

| | |
|---|---|
| [docs/loa-schema.md](docs/loa-schema.md) | the workbook: every sheet, column and setting |
| [docs/deployment.md](docs/deployment.md) | deploying to Posit Connect Cloud, and what your data does there |
| [docs/development.md](docs/development.md) | repository layout, tests, performance, known limits |
