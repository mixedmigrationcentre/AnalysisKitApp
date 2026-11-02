# The `level` cell decides which estimation engine a row uses, and that is the
# largest performance decision in the application. loa_engine_split() reports
# it before the run; these tests pin it to the routing the pipeline actually
# performs.

spec_with <- function(level, engine = NULL, groups = c("Overall", "G1", "G2")) {
  settings <- list()
  if (!is.null(engine)) settings$engine <- engine

  structure(
    list(
      loa = data.frame(
        analysis_type = rep("prop_select_one", length(level)),
        analysis_var = paste0("Q", seq_along(level)),
        level = level,
        stringsAsFactors = FALSE
      ),
      group_variables = groups,
      settings = settings
    ),
    class = c("analysis_spec", "list")
  )
}


test_that("an empty level column keeps every analysis on the fast engine", {
  split <- loa_engine_split(spec_with(c(NA, NA, NA)))

  expect_equal(split$engine, "auto")
  expect_equal(split$analyses, 3L)
  expect_equal(split$survey, 0L)
  expect_equal(split$fast, 3L)
  expect_equal(split$survey_estimations, 0L)
})


test_that("a filled level sends that row to the survey engine, once per group", {
  split <- loa_engine_split(spec_with(c(0.95, NA, 0.9)))

  expect_equal(split$survey, 2L)
  expect_equal(split$fast, 1L)
  expect_equal(split$group_variables, 3L)
  # Two analyses across three grouping variables, Overall included.
  expect_equal(split$survey_estimations, 6L)
})


test_that("blank and 'NA' text are treated as no level", {
  split <- loa_engine_split(spec_with(c("", "NA", "  ", "0.95")))
  expect_equal(split$survey, 1L)
})


test_that("the engine setting overrides the level column in both directions", {
  expect_equal(loa_engine_split(spec_with(c(0.95, 0.95), "fast"))$survey, 0L)
  expect_equal(loa_engine_split(spec_with(c(NA, NA), "survey"))$survey, 2L)
})


test_that("a List of Analysis with no level column at all is entirely fast", {
  spec <- spec_with(c(NA, NA))
  spec$loa$level <- NULL

  split <- loa_engine_split(spec)
  expect_equal(split$survey, 0L)
  expect_equal(split$fast, 2L)
})


test_that("the note is silent when nothing uses the survey engine", {
  # Nothing to explain in the fast case, and a panel that always says something
  # is a panel nobody reads.
  expect_length(ak_engine_note(loa_engine_split(spec_with(c(NA, NA)))), 0L)
})


test_that("the note names the count and the cost when the survey engine is used", {
  note <- ak_engine_note(loa_engine_split(spec_with(c(0.95, NA))))
  text <- paste(as.character(note), collapse = " ")

  expect_match(text, "1 of 2 analyses")
  expect_match(text, "3 grouping variable")
  expect_match(text, "point estimates are identical")
})
