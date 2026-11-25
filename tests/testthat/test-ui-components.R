# The Shiny helpers in R/ui_components.R: they turn facts into tags. The rules
# behind those facts (ak_step_states(), ak_can_run(), ...) are tested in the
# analysiskit package.

test_that("badges read as sentences and get the plural right", {
  expect_match(
    as.character(ak_badges(c(error = 0L, warning = 0L))), "All checks passed"
  )
  expect_match(
    as.character(ak_badges(c(error = 1L, warning = 0L))), "1 problem to fix"
  )
  expect_match(
    as.character(ak_badges(c(error = 2L, warning = 1L))), "2 problems to fix"
  )
  expect_match(
    as.character(ak_badges(c(error = 0L, warning = 1L))), "1 warning<"
  )
})

test_that("status tones map to the stylesheet's classes", {
  expect_match(as.character(ak_status("x", "success")), "status-success")
  expect_match(as.character(ak_status("x", "warning")), "status-warning")
  expect_match(as.character(ak_status("x", "error")), "status-error")
  expect_no_match(as.character(ak_status("x")), "status-success")
})


# --- the engine note --------------------------------------------------------

# value_columns reports the interval by default here, because analysiskit only
# sends a row with a level to the survey engine when the interval it asks for
# will actually be shown.
spec_with <- function(level,
                      engine = NULL,
                      groups = c("Overall", "G1", "G2"),
                      value_columns = c("stat", "stat_low", "stat_upp", "n", "n_total")) {
  settings <- list(value_columns = value_columns)
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


# --- the exclusive-combinations caveat ---------------------------------------

test_that("the caveat panel renders only when there is something to say", {
  quiet <- ak_exclusive_base_panel(
    data.frame(analysis_var = "Q78", n_in_base = 10, n_no_selection = 0)
  )
  expect_equal(trimws(paste(as.character(quiet), collapse = "")), "")

  loud <- as.character(ak_exclusive_base_panel(
    data.frame(analysis_var = "Q78", n_in_base = 800, n_no_selection = 200)
  ))
  expect_match(loud, "status-warning", all = FALSE)
  expect_match(loud, "smaller denominator", all = FALSE)
  expect_match(loud, "Footnote this", all = FALSE)

  # Both maps at once, as the Results tab passes them: one question, one note.
  both <- as.character(ak_exclusive_base_panel(
    data.frame(analysis_var = "Q78", n_in_base = 800, n_no_selection = 200),
    data.frame(analysis_var = "Q78", n_in_base = 800, n_no_selection = 200)
  ))
  expect_equal(lengths(regmatches(both, gregexpr("<li>", both))), 1L)
})


test_that("the note is silent when a level is set but no interval is reported", {
  # The default value_columns shows no interval, so analysiskit tabulates the
  # row and there is no survey cost to warn about.
  split <- loa_engine_split(spec_with(c(0.95, 0.95), value_columns = c("stat", "n", "n_total")))
  expect_equal(split$survey, 0L)
  expect_length(ak_engine_note(split), 0L)
})

test_that("each main tab is marked from the files and what the checks found", {
  none <- ak_tab_states(FALSE, FALSE, FALSE, FALSE, NULL, FALSE)
  expect_equal(unname(none), rep("todo", 4L))
  expect_equal(
    names(none),
    c("Dataset", "List of Analysis", "Checks", "Results")
  )

  problems <- data.frame(
    sheet = "analysis",
    severity = "warning",
    row = 1L,
    message = "check this"
  )
  expect_equal(
    unname(ak_tab_states(TRUE, FALSE, TRUE, FALSE, problems, TRUE)),
    c("done", "done", "warning", "done")
  )
  problems$severity <- "error"
  expect_equal(
    unname(ak_tab_states(FALSE, TRUE, FALSE, TRUE, problems, FALSE)),
    c("error", "error", "error", "todo")
  )
})
