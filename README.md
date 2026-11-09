# Analysis Kit App

Turns a 4Mi dataset and a **List of Analysis** workbook into an MMC-styled
results workbook. Upload two files, click one button.

## Open it

**Online:** [abu-analysiskit.share.connect.posit.cloud](https://abu-analysiskit.share.connect.posit.cloud/).
Nothing to install.

**Locally:** install the analysis package once, then start the app from
`analysiskitapp.Rproj` in RStudio:

```r
pak::pkg_install("mixedmigrationcentre/analysiskit")   # once
shiny::runApp()
```

## Use it

1. **Upload the dataset** - a 4Mi export, `.csv` or `.xlsx`.
2. **Upload the List of Analysis** - start from **Download the List of Analysis
   template** in the sidebar. Its `readme` sheet explains how to fill it in.
3. **Read the checks** - red must be fixed before you can run; amber is just
   worth reading.
4. **Choose where to save** - locally, pick a folder. Online, the results come
   as a download.
5. **Run the analyses**, then download the results workbook.

Tip: leave the `level` column empty unless a row needs a confidence interval.
Those rows are much slower, and the figures are the same either way.

## How it fits together

The analysis (reading, checks, the pipeline, the export and the template) lives
in the [analysiskit](https://github.com/mixedmigrationcentre/analysiskit)
package. This repository is only the Shiny interface and the deployment setup.

- **Changing the analysis?** Edit the package, push it to GitHub, then
  reinstall it here with `pak::pkg_install("mixedmigrationcentre/analysiskit")`.
- **Changing the interface?** Edit `app.R` or `R/ui_components.R` here.
- **Deploying?** See [docs/deployment.md](docs/deployment.md).
