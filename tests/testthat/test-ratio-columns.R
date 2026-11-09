# analysis_var_numerator / analysis_var_denominator.
#
# The two columns are read by one analysis_type only, which makes them easy to
# fill in by mistake - a duplicated row whose analysis_type was changed back
# leaves them behind. These tests pin down what happens then, in the validator
# and in the pipeline, because the failure they used to cause was silent.

ratio_sheets <- function(analysis) {
  fixture_sheets(
    analysis = analysis,
    count_selections = NULL,
    count_combinations = NULL,
    count_exclusive_combinations = NULL
  )
}

problem_text <- function(problems, severity = NULL) {
  if (!is.null(severity)) {
    problems <- problems[problems$severity == severity, , drop = FALSE]
  }
  paste(problems$message, collapse = " | ")
}


# --- validation --------------------------------------------------------------

test_that("a ratio row needs both of its variable columns", {
  analysis <- data.frame(
    analysis_type = "ratio",
    analysis_var = NA_character_,
    analysis_var_numerator = "Q29",
    analysis_var_denominator = NA_character_,
    stringsAsFactors = FALSE
  )

  problems <- validate_loa(
    fixture_workbook(ratio_sheets(analysis)), fixture_dataset()
  )

  expect_true(loa_has_errors(problems))
  expect_match(problem_text(problems, "error"), "analysis_var_denominator")
})


test_that("a value in a ratio column on a non-ratio row warns but does not block", {
  analysis <- data.frame(
    analysis_type = "prop_select_one",
    analysis_var = "Q27",
    analysis_var_numerator = "Q29",
    analysis_var_denominator = NA_character_,
    stringsAsFactors = FALSE
  )

  problems <- validate_loa(
    fixture_workbook(ratio_sheets(analysis)), fixture_dataset()
  )

  expect_false(loa_has_errors(problems))
  expect_match(problem_text(problems, "warning"), "Only a ratio uses")
  expect_match(problem_text(problems, "warning"), "analysis_var_numerator")
})


test_that("analysis_var filled on a ratio row warns", {
  analysis <- data.frame(
    analysis_type = "ratio",
    analysis_var = "Q27",
    analysis_var_numerator = "Q29",
    analysis_var_denominator = "Q29",
    stringsAsFactors = FALSE
  )

  problems <- validate_loa(
    fixture_workbook(ratio_sheets(analysis)), fixture_dataset()
  )

  expect_false(loa_has_errors(problems))
  expect_match(problem_text(problems, "warning"), "does not use analysis_var")
})


test_that("a correctly filled ratio row raises nothing", {
  analysis <- data.frame(
    analysis_type = "ratio",
    analysis_var = NA_character_,
    analysis_var_numerator = "Q29",
    analysis_var_denominator = "Q29",
    stringsAsFactors = FALSE
  )

  problems <- validate_loa(
    fixture_workbook(ratio_sheets(analysis)), fixture_dataset()
  )

  expect_false(loa_has_errors(problems))
  expect_false(grepl("ratio", problem_text(problems), fixed = TRUE))
})


# --- the pipeline ------------------------------------------------------------

test_that("a stray ratio variable does not coerce its dataset column", {
  skip_if_not(exists("ck_coerce_numeric"), "analysis functions not loaded")

  # Q27 is a select_one of text labels. Named in analysis_var_numerator on a
  # prop_select_one row it used to be coerced to numeric for the whole run,
  # turning every gender label into NA while the row still ran as a proportion.
  loa <- data.frame(
    analysis_type = c("prop_select_one", "mean"),
    analysis_var = c("Q27", "Q29"),
    analysis_var_numerator = c("Q27", NA_character_),
    analysis_var_denominator = c("Q31", NA_character_),
    stringsAsFactors = FALSE
  )

  a_type <- tolower(as.character(loa$analysis_type))
  is_ratio_row <- !is.na(a_type) & a_type == "ratio"

  numeric_vars <- loa$analysis_var[!is.na(a_type) & a_type %in% c("mean", "median")]
  for (cc in c("analysis_var_numerator", "analysis_var_denominator")) {
    numeric_vars <- c(numeric_vars, loa[[cc]][is_ratio_row])
  }

  expect_equal(sort(unique(stats::na.omit(numeric_vars))), "Q29")

  coerced <- ck_coerce_numeric(fixture_dataset(), numeric_vars, verbose = FALSE)
  expect_type(coerced$Q27, "character")
  expect_true(all(c("Female", "Male") %in% coerced$Q27))
  expect_type(coerced$Q29, "double")
})


test_that("blank ratio flags resolve to FALSE for both engines", {
  skip_if_not(exists("ck_stack_loa"), "analysis functions not loaded")

  loa <- data.frame(
    analysis_type = "ratio",
    analysis_var = NA_character_,
    analysis_var_numerator = "Q29",
    analysis_var_denominator = "Q29",
    numerator_NA_to_0 = NA,
    stringsAsFactors = FALSE
  )

  stacked <- ck_stack_loa(
    loa, fixture_dataset()[-1, , drop = FALSE],
    group_variables = "Overall", verbose = FALSE
  )

  # Present and FALSE, not NA: create_analysis() would otherwise apply its own
  # TRUE default and disagree with the fast engine on the same row.
  expect_false(is.na(stacked$numerator_NA_to_0[1]))
  expect_false(stacked$numerator_NA_to_0[1])
  expect_false(stacked$filter_denominator_0[1])
})


test_that("the ratio flags are not invented for a workbook with no ratios", {
  skip_if_not(exists("ck_stack_loa"), "analysis functions not loaded")

  loa <- data.frame(
    analysis_type = "mean",
    analysis_var = "Q29",
    stringsAsFactors = FALSE
  )

  stacked <- ck_stack_loa(
    loa, fixture_dataset()[-1, , drop = FALSE],
    group_variables = "Overall", verbose = FALSE
  )

  expect_false("numerator_NA_to_0" %in% names(stacked))
})


test_that("ck_loa_flag reads every shape a spreadsheet produces", {
  skip_if_not(exists("ck_loa_flag"), "analysis functions not loaded")

  expect_equal(ck_loa_flag(c(TRUE, FALSE, NA)), c(TRUE, FALSE, FALSE))
  expect_equal(ck_loa_flag(c("TRUE", "true", "yes", "no", "", NA)),
               c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE))
  expect_equal(ck_loa_flag(c(1, 0, NA)), c(TRUE, FALSE, FALSE))
})


# --- output labelling --------------------------------------------------------

test_that("a ratio is titled from both halves when both are labelled", {
  skip_if_not(exists("ck_ratio_label"), "analysis functions not loaded")

  lookup <- c(
    Q29 = "How old are you?",
    Q31 = "Are you travelling with children?"
  )

  expect_equal(
    ck_ratio_label("Q29 %/% Q31", lookup),
    "How old are you? per Are you travelling with children?"
  )
})


test_that("a half-labelled ratio keeps the raw key", {
  skip_if_not(exists("ck_ratio_label"), "analysis functions not loaded")

  lookup <- c(Q29 = "How old are you?")

  expect_true(is.na(ck_ratio_label("Q29 %/% Q99", lookup)))
  expect_true(is.na(ck_ratio_label("Q27", lookup)))
})


test_that("ck_relabel_questions labels ratio rows", {
  skip_if_not(exists("ck_relabel_questions"), "analysis functions not loaded")

  results <- data.frame(
    analysis_type = c("ratio", "prop_select_one"),
    analysis_var = c("Q29 %/% Q31", "Q27"),
    analysis_var_value = c(NA_character_, "Female"),
    stringsAsFactors = FALSE
  )

  lookup <- c(
    Q27 = "What is your gender?",
    Q29 = "How old are you?",
    Q31 = "Are you travelling with children?"
  )

  out <- ck_relabel_questions(results, lookup)

  expect_equal(
    out$label_analysis_var[1],
    "How old are you? per Are you travelling with children?"
  )
  expect_equal(out$label_analysis_var[2], "What is your gender?")
})


# --- export formatting -------------------------------------------------------

test_that("a ratio is formatted as a number, not a percentage", {
  skip_if_not(exists("ck_is_decimal_type"), "export functions not loaded")

  expect_equal(
    ck_is_decimal_type(c(
      "ratio", "mean", "median", "prop_select_one", "prop_select_multiple",
      "combination_select_multiple", NA
    )),
    c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, FALSE)
  )
})
