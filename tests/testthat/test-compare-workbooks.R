# The guard behind the optimisation work: a results workbook has to come out of
# a faster pipeline exactly as it came out of the slower one. These tests are
# about the comparison itself - that it notices the ways a workbook can change,
# and that it does not cry wolf when nothing has.

skip_without_openxlsx <- function() {
  skip_if_not_installed("openxlsx")
}

# Two sheets, mixed types, a few NA cells - enough shape for the comparison to
# have something to get wrong.
write_test_book <- function(path, value = 0.25, label = "Choice 1", as_text = FALSE) {
  wb <- openxlsx::createWorkbook()

  openxlsx::addWorksheet(wb, "Demographics")
  openxlsx::writeData(
    wb, "Demographics",
    data.frame(
      a = c("VARIABLE: gender", label, "Choice 2"),
      b = if (as_text) c(NA, as.character(value), "0.75") else c(NA, value, 0.75),
      stringsAsFactors = FALSE
    ),
    colNames = FALSE
  )

  openxlsx::addWorksheet(wb, "Drivers")
  openxlsx::writeData(
    wb, "Drivers",
    data.frame(a = c("x", "y"), b = c(1, 2), stringsAsFactors = FALSE),
    colNames = FALSE
  )

  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  path
}


test_that("a workbook compares equal to a copy of itself", {
  skip_without_openxlsx()

  a <- write_test_book(withr::local_tempfile(fileext = ".xlsx"))
  b <- write_test_book(withr::local_tempfile(fileext = ".xlsx"))

  result <- ak_compare_workbooks(a, b)

  expect_true(result$identical)
  expect_equal(nrow(result$differences), 0L)
  expect_match(result$summary, "identical")
  expect_silent(ak_expect_same_workbook(a, b))
})


test_that("a moved number is reported, with its before and after", {
  skip_without_openxlsx()

  a <- write_test_book(withr::local_tempfile(fileext = ".xlsx"), value = 0.25)
  b <- write_test_book(withr::local_tempfile(fileext = ".xlsx"), value = 0.26)

  result <- ak_compare_workbooks(a, b)

  expect_false(result$identical)
  expect_equal(nrow(result$differences), 1L)
  expect_equal(result$differences$sheet, "Demographics")
  expect_equal(result$differences$before, "number: 0.25")
  expect_equal(result$differences$after, "number: 0.26")
  expect_error(ak_expect_same_workbook(a, b), "differing cell")
})


test_that("a number written as text is a difference, not a match", {
  skip_without_openxlsx()

  # The failure mode of a careless batched write: the styling survives, the
  # value looks right on screen, and Excel has stopped treating it as a number.
  a <- write_test_book(withr::local_tempfile(fileext = ".xlsx"))
  b <- write_test_book(withr::local_tempfile(fileext = ".xlsx"), as_text = TRUE)

  result <- ak_compare_workbooks(a, b)

  expect_false(result$identical)
  expect_match(result$differences$before[1], "^number: ")
  expect_match(result$differences$after[1], "^text: ")
})


test_that("a changed label is reported", {
  skip_without_openxlsx()

  a <- write_test_book(withr::local_tempfile(fileext = ".xlsx"))
  b <- write_test_book(withr::local_tempfile(fileext = ".xlsx"), label = "Choice A")

  result <- ak_compare_workbooks(a, b)

  expect_false(result$identical)
  expect_equal(result$differences$before, "text: Choice 1")
  expect_equal(result$differences$after, "text: Choice A")
})


test_that("a missing sheet is reported rather than ignored", {
  skip_without_openxlsx()

  a <- write_test_book(withr::local_tempfile(fileext = ".xlsx"))

  path <- withr::local_tempfile(fileext = ".xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Demographics")
  openxlsx::writeData(
    wb, "Demographics",
    data.frame(
      a = c("VARIABLE: gender", "Choice 1", "Choice 2"),
      b = c(NA, 0.25, 0.75),
      stringsAsFactors = FALSE
    ),
    colNames = FALSE
  )
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)

  result <- ak_compare_workbooks(a, path)

  expect_false(result$identical)
  expect_true("Drivers" %in% result$differences$sheet)
})


test_that("a tolerance covers a float that survived a round trip", {
  skip_without_openxlsx()

  a <- write_test_book(withr::local_tempfile(fileext = ".xlsx"), value = 0.25)
  b <- write_test_book(withr::local_tempfile(fileext = ".xlsx"), value = 0.25 + 1e-12)

  expect_true(ak_compare_workbooks(a, b)$identical)
  expect_false(ak_compare_workbooks(a, b, tolerance = 1e-15)$identical)
})


test_that("the comparison is not part of the deployment", {
  # It reads workbooks and is only ever run by a developer checking a change.
  # Bundling it would ship test tooling to the server.
  expect_false("R/compare_workbooks.R" %in% ak_manifest_files("../.."))
})
