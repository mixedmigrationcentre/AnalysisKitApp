# Each test here pins an optimisation to the behaviour it must not change.
# They are cheap, and they are the difference between "this is faster" and
# "this is faster and still right".

skip_without_app <- function() {
  skip_if_not(
    exists("run_group_analysis_pipeline", mode = "function"),
    "analysis functions are not in the repository yet"
  )
}


# -----------------------------------------------------------------------------
# The style collector
# -----------------------------------------------------------------------------

test_that("the style grid collects rectangles and flushes them once per style", {
  skip_if_not_installed("openxlsx")
  skip_without_app()

  sg <- ck_new_style_grid()
  red <- ck_style(sg, fontColour = "#FF0000")
  blue <- ck_style(sg, fontColour = "#0000FF")

  ck_add_rect(sg, red, 1:3, 1:2)
  ck_add_rect(sg, blue, 5, 1)
  ck_add_rect(sg, red, 9, 4)

  expect_equal(sg$n, 3L)

  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "s")
  expect_equal(ck_flush_styles(sg, wb, "s"), 2L)

  # Flushing empties the grid, so a second sheet does not inherit the first
  # sheet's rectangles.
  expect_equal(sg$n, 0L)
  expect_equal(ck_flush_styles(sg, wb, "s"), 0L)
})


test_that("an empty row or column set adds nothing", {
  skip_without_app()

  sg <- ck_new_style_grid()
  key <- ck_style(sg, fontColour = "#000000")

  ck_add_rect(sg, key, integer(0), 1)
  ck_add_rect(sg, key, 1, integer(0))

  expect_equal(sg$n, 0L)
})


test_that("the collector styles the same cells however many rectangles it took", {
  skip_if_not_installed("openxlsx")
  skip_without_app()

  cells <- function(build) {
    sg <- ck_new_style_grid()
    key <- ck_style(sg, fontColour = "#003D58")
    build(sg, key)
    wb <- openxlsx::createWorkbook()
    openxlsx::addWorksheet(wb, "s")
    ck_flush_styles(sg, wb, "s")
    sort(unlist(lapply(wb$styleObjects, function(s) {
      paste(s$rows, s$cols, sep = ",")
    })))
  }

  # One rectangle over four columns, against four rectangles of one column:
  # this is exactly the change made in the blocks layout, and the styled cells
  # have to come out the same.
  one <- cells(function(sg, key) ck_add_rect(sg, key, 4:6, 2:5))
  many <- cells(function(sg, key) {
    for (g in 2:5) ck_add_rect(sg, key, 4:6, g)
  })

  expect_equal(one, many)
})


# -----------------------------------------------------------------------------
# Batched writing
# -----------------------------------------------------------------------------

test_that("the batched write keeps numbers numeric and text text", {
  skip_if_not_installed("openxlsx")
  skip_without_app()

  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "s")

  headers <- list(
    list(row = 1L, values = matrix(c("VARIABLE: Q1", NA, "Category", "n"), 2, 2)),
    list(row = 6L, values = matrix(c("VARIABLE: Q2", NA, "Category", "n"), 2, 2))
  )
  bodies <- list(
    list(row = 3L, values = list(c("Yes", "No"), c(0.25, 0.75))),
    list(row = 8L, values = list(c("Yes", "No"), c(0.4, 0.6)))
  )

  calls <- ck_write_question_cells(wb, "s", headers, bodies, n_col = 2L, last_row = 9L)

  # One body write plus one per question's header block, rather than two per
  # question.
  expect_equal(calls, 3L)

  path <- withr::local_tempfile(fileext = ".xlsx")
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)

  # Read as stored, not as read.xlsx infers it: the point of the test is that
  # the headers are text and the statistics under them are still numbers.
  cells <- ak_snapshot_workbook(path)[["s"]]
  at <- function(r, c) cells[cells$row == r & cells$col == c, , drop = FALSE]

  expect_equal(at(1, 1)$value, "VARIABLE: Q1")
  expect_equal(at(1, 1)$type, "text")
  expect_equal(at(3, 1)$value, "Yes")
  expect_equal(at(2, 2)$type, "text")
  expect_equal(at(3, 2)$type, "number")
  expect_equal(as.numeric(at(3, 2)$value), 0.25)
  expect_equal(as.numeric(at(9, 2)$value), 0.6)
})


test_that("a column of mixed types falls back to writing each question", {
  skip_if_not_installed("openxlsx")
  skip_without_app()

  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "s")

  headers <- list(list(row = 1L, values = matrix("VARIABLE: Q1", 1, 1)))
  bodies <- list(
    list(row = 2L, values = list(c(0.25, 0.75))),
    list(row = 5L, values = list(c("n/a", "n/a")))
  )

  # Two bodies and one header: stacking them would turn the numbers into text,
  # so the sheet is written question by question instead.
  expect_equal(
    ck_write_question_cells(wb, "s", headers, bodies, n_col = 1L, last_row = 6L),
    3L
  )
})


# -----------------------------------------------------------------------------
# Restricted blank cleaning
# -----------------------------------------------------------------------------

test_that("ck_blank_to_na cleans every character column by default", {
  skip_without_app()

  data <- data.frame(
    a = c("x", "", "  "),
    b = c("", "y", "z"),
    n = c(1, 2, 3),
    stringsAsFactors = FALSE
  )

  out <- ck_blank_to_na(data)
  expect_equal(out$a, c("x", NA, NA))
  expect_equal(out$b, c(NA, "y", "z"))
  expect_equal(out$n, c(1, 2, 3))
})


test_that("ck_blank_to_na touches only the columns it is given", {
  skip_without_app()

  data <- data.frame(
    a = c("x", ""),
    b = c("", "y"),
    stringsAsFactors = FALSE
  )

  out <- ck_blank_to_na(data, columns = "a")
  expect_equal(out$a, c("x", NA))
  expect_equal(out$b, c("", "y"))

  # A column name that is not in the dataset is ignored rather than an error.
  expect_equal(ck_blank_to_na(data, columns = c("a", "nope"))$a, c("x", NA))
})


test_that("the pipeline cleans the variables it reads and leaves the rest", {
  skip_without_app()

  data <- data.frame(
    Q1 = c("label", "Yes", ""),
    G1 = c("label", "", "Male"),
    SPARE = c("label", "", ""),
    stringsAsFactors = FALSE
  )
  loa <- data.frame(
    analysis_type = "prop_select_one",
    analysis_var = "Q1",
    stringsAsFactors = FALSE
  )

  cleaned <- ck_design_columns(data, loa, c("Overall", "G1"))

  expect_true(all(c("Q1", "G1") %in% cleaned))
  expect_false("SPARE" %in% cleaned)
})


# -----------------------------------------------------------------------------
# The select_multiple selection cache
# -----------------------------------------------------------------------------

test_that("a cached selection matrix equals the uncached one", {
  skip_without_app()

  data <- fixture_dataset(6)[-1, , drop = FALSE]

  plain <- ck_sm_selection_matrix(data, "Q78")
  cache <- new.env(parent = emptyenv())
  first <- ck_sm_selection_matrix(data, "Q78", cache = cache)
  second <- ck_sm_selection_matrix(data, "Q78", cache = cache)

  expect_equal(first, plain)
  expect_equal(second, plain)
  expect_equal(length(ls(cache)), 1L)
})


test_that("the cache keys on everything that changes the answer", {
  skip_without_app()

  data <- fixture_dataset(6)[-1, , drop = FALSE]
  cache <- new.env(parent = emptyenv())

  all_choices <- ck_sm_selection_matrix(data, "Q78", cache = cache)
  fewer <- ck_sm_selection_matrix(
    data, "Q78",
    exclude_choices = "Economic reasons", cache = cache
  )

  expect_equal(length(ls(cache)), 2L)
  expect_true(ncol(all_choices$selected) > ncol(fewer$selected))
  expect_false("Economic reasons" %in% fewer$suffixes)
})


test_that("a parent with no children is cached as such", {
  skip_without_app()

  data <- fixture_dataset(6)[-1, , drop = FALSE]
  cache <- new.env(parent = emptyenv())

  expect_null(ck_sm_selection_matrix(data, "Q27", cache = cache))
  expect_null(ck_sm_selection_matrix(data, "Q27", cache = cache))
  expect_equal(length(ls(cache)), 1L)
})


# -----------------------------------------------------------------------------
# Upload profiling
# -----------------------------------------------------------------------------

test_that("the duplicate-row count is carried on the dataset, not recomputed", {
  data <- data.frame(a = c(1, 1, 2), b = c("x", "x", "y"), stringsAsFactors = FALSE)

  # Counted at upload: the overview reads the number it is given.
  overview <- dataset_overview(list(
    data = data, filename = "d.csv", extension = "CSV", size = 10,
    duplicate_rows = 7
  ))
  expect_equal(overview$Value[overview$Measure == "Duplicate rows"], "7")

  # And still works for a dataset built without one.
  overview <- dataset_overview(list(
    data = data, filename = "d.csv", extension = "CSV", size = 10
  ))
  expect_equal(overview$Value[overview$Measure == "Duplicate rows"], "1")
})
