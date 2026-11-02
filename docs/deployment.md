# Deploying to Posit Cloud

The live copy is at
**[abu-analysiskit.share.connect.posit.cloud](https://abu-analysiskit.share.connect.posit.cloud/)**.
This is how it gets there, and what changes when it runs on a server rather
than on your own machine.

Moved out of `README.md`, which is the short guide to using the app.

---

## Generate the manifest

Posit Cloud and Posit Connect need a `manifest.json` describing the app's files
and package versions. From the project root:

```r
source("R/generate_manifest.R")
```

This must be run **on the machine that has your real library** — the manifest
records your R version and your installed package versions, so one generated
elsewhere will not reproduce. Regenerate it whenever you add a package or change
which files the app needs, and commit the result.

---

## If it fails with a missing package

`rsconnect::writeManifest()` snapshots with renv, and **renv refuses to snapshot
a library whose packages have missing dependencies**. Its own message names one
package at a time; `generate_manifest.R` runs a pre-flight first and reports the
whole list with the commands that fix it.

The usual cause is the survey chain. The analysis pipeline calls `srvyr::` and
`analysistools::` **by name**, so renv records both — and their dependencies —
even though a run only reaches them when a workbook asks for a confidence level.
Deploying pulls them in whether or not you use them.

`cleaningtools` is the exception. It is needed by exactly one call, behind
`recreate_sm_parents = TRUE`, and recording it dragged in eight further
packages — `V8` and `Rtsne` among them, both of which compile from source. It is
reached through `getFromNamespace()` instead, so renv no longer records it and
the deployment no longer builds it. Nothing changes for a run that does set
`recreate_sm_parents`: the startup check still names the package and the install
command if it is missing. **Regenerate `manifest.json` to pick this up** — it
still records the old, larger dependency set until you do.

If you hit `RcppArmadillo [required by survey]`:

```r
install.packages(c("RcppArmadillo", "srvyr"))
```

then run `source("R/generate_manifest.R")` again.

---

## What gets uploaded

`generate_manifest.R` bundles a **named list of files**, not the project
directory. That is deliberate: the repository root holds `.RData` and
`.Rhistory` — an R session's saved workspace and command history. If a dataset
was loaded when that workspace was written, `writeManifest(appDir = ".")` would
upload respondent data to a hosted server. `.rscignore` covers the same ground
for anyone deploying with the RStudio button instead.

`tests/` is left out too, so a deployment does not install a test framework to
run nothing.

---

## What changes when it is served

**The folder picker is gone, and that is deliberate — not a feature that failed
to load.** `shinyFiles` browses the filesystem of whatever machine the app is
running on. Served, that is the server's container, not your computer: a file
written there never reaches your disk and disappears when the container
recycles. Offering the picker anyway would lose runs silently.

So on a server the app builds the workbook in a per-session temporary folder and
hands it to you as a **download** instead. The fourth step is renamed
**Delivery**, marks itself complete, and says where the Download button will
appear — because a step headed "Output folder" with nothing under it reads as
broken. Run locally, the picker and the **Destination** step are unchanged.

The app detects which case it is in from the environment. If it guesses wrong
for a host it does not recognise, tell it:

```r
options(analysiskit.server = TRUE)   # or the ANALYSISKIT_SERVER env var
```
