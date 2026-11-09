library(testthat)
library(analysiskit)

# The analysis, reading, checking and export functions come from the
# analysiskit package, and are tested there. What is tested here is the app:
# its Shiny helpers, deployment tooling and the server wiring in app.R. The
# app's own R/ files are sourced, since the app is not a package.
for (f in list.files("../R", pattern = "[.][Rr]$", full.names = TRUE)) {
  source(f)
}

test_dir("testthat", env = globalenv())
