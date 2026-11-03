# Deploying to Posit Connect Cloud

The live copy is at
**[abu-analysiskit.share.connect.posit.cloud](https://abu-analysiskit.share.connect.posit.cloud/)**.
This is how it gets there, what changes when it runs on a server rather than on
your own machine, and what happens to the data people upload to it.

The host is **Posit Connect Cloud** — not Posit Cloud, which is the browser IDE,
and not shinyapps.io. The three are separate products with separate behaviour,
and this document is about the third.

Moved out of `README.md`, which is the short guide to using the app.

---

## Generate the manifest

Connect Cloud and Posit Connect need a `manifest.json` describing the app's
files and package versions. From the project root:

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

So on a server the app builds the workbook in a temporary folder belonging to
that one session and hands it to you as a **download** instead. The fourth step
is renamed **Delivery**, marks itself complete, and says where the Download
button will appear — because a step headed "Output folder" with nothing under it
reads as broken. Run locally, the picker and the **Destination** step are
unchanged.

The directory browser is not merely hidden when served: `shinyDirChoose()` is
never called, so the server-side observer that answers directory listings is
never created. Hiding the button would not have been enough, because a Shiny
input arrives as a websocket message rather than only from the JavaScript the
page happens to ship.

### Tell the deployment what it is

The app can detect a served environment on its own, and does so correctly on
Connect Cloud today. But none of the signals it looks for is documented as
Connect Cloud's, so **set the environment variable in the host's own settings
rather than relying on the guess**:

```
ANALYSISKIT_SERVER=true
```

In Connect Cloud this goes in the content's variable settings. With it set, a
change to Posit's runtime cannot quietly flip the app into local mode — where it
would offer a folder picker onto the container and start trying to install
packages into a read-only library. Both failures are silent, which is what makes
them worth one line of configuration.

`options(analysiskit.server = TRUE)` does the same thing in an R session, and is
what the tests use.

---

## What happens to uploaded data

Worth being able to answer precisely, because research partners ask.

**The uploads.** `fileInput` writes each uploaded file into a randomly named
subdirectory of the R process's temp directory. Shiny tracks every upload
belonging to a session and deletes those subdirectories when the session ends.
The dataset itself is held in a `reactiveVal` created inside `server()`, so it is
scoped to the session and collected with it. Nothing is assigned to the global
environment and there is no disk cache.

**The results workbook.** Built in `ak_session_output_dir(session$token)` — a
folder named after the session, not shared — and removed by an `onSessionEnded()`
handler when the session ends. The per-session part matters: `tempdir()` belongs
to the R *process*, and one Shiny process serves many sessions, so a single
shared folder would have left one analyst's results in a directory every other
session on the instance could read, for as long as the container lived.

**The deployed files.** Connect Cloud's filesystem is ephemeral. Files written at
runtime last only while users are visiting, and a restart or republish resets the
filesystem to match the repository. Nothing the app writes goes into the bundle
in any case.

**What none of this changes.** While a session is running, the dataset is in the
container's memory and its uploaded copy is on the container's disk. That is
inherent to doing the analysis on a server. Posit states encryption at rest and
account-level isolation and holds a SOC 2 Type I attestation, but the data has
still been sent to a third-party processor.

On Connect Cloud's Free and Basic plans **public access cannot be turned off** —
anyone with the URL can open the app and upload to it. Sessions are isolated, so
no visitor can read another's data, but the app is an open compute endpoint.
Restricting access needs the Enhanced plan or above.

So for a dataset that must not leave a machine you control, run Analysis Kit
locally: the folder picker and the direct save exist for exactly that, and the
data never goes anywhere. The deployed copy suits non-sensitive or already
cleared data, and giving colleagues somewhere to try the workflow.
