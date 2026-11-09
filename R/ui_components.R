# =============================================================================
# Presentation helpers for the Analysis Kit interface
# =============================================================================
#
# Only the functions that build Shiny tags live here. The rules behind them -
# ak_step_states(), ak_can_run(), ak_problem_counts(), ak_problems_display(),
# ak_sheet_summary(), ak_exclusive_base_note() - are pure, and come from the
# analysiskit package. These turn those facts into tags and hold no logic
# beyond arranging what they are given.
#
# No analysis and no validation happens here.
# =============================================================================


#' Render the Step Tracker
#'
#' A horizontal row of steps showing where the user is, which is the one piece
#' of the interface that is always on screen.
#'
#' @param states A vector from \code{\link{ak_step_states}}.
#' @param destination_label Label for the destination step, from
#'   \code{\link{ak_destination_mode}}.
#' @return A Shiny tag.
#' @export
ak_step_tracker <- function(states, destination_label = "Destination") {
  steps <- ak_steps(destination_label)

  symbol <- c(
    todo = "○", active = "●", done = "✓",
    warning = "!", error = "×"
  )

  items <- lapply(names(steps), function(id) {
    state <- states[[id]]
    shiny::tags$li(
      class = paste0("ak-step ak-step-", state),
      # The shape carries the state as well as the colour, so the tracker is
      # still readable without relying on colour alone.
      shiny::tags$span(class = "ak-step-mark", symbol[[state]]),
      shiny::tags$span(class = "ak-step-label", steps[[id]])
    )
  })

  shiny::tags$ol(
    class = "ak-steps",
    role = "list",
    `aria-label` = "Workflow progress",
    items
  )
}


#' Render a Row of Severity Badges
#' @param counts A vector from \code{\link{ak_problem_counts}}.
#' @return A Shiny tag.
#' @export
ak_badges <- function(counts) {
  plural <- function(n, one, many) paste(n, if (n == 1L) one else many)

  if (counts[["error"]] == 0L && counts[["warning"]] == 0L) {
    return(shiny::tags$div(
      class = "ak-badges",
      shiny::tags$span(class = "ak-badge ak-badge-ok", "All checks passed")
    ))
  }

  shiny::tags$div(
    class = "ak-badges",
    if (counts[["error"]] > 0L) {
      shiny::tags$span(
        class = "ak-badge ak-badge-error",
        plural(counts[["error"]], "problem to fix", "problems to fix")
      )
    },
    if (counts[["warning"]] > 0L) {
      shiny::tags$span(
        class = "ak-badge ak-badge-warning",
        plural(counts[["warning"]], "warning", "warnings")
      )
    }
  )
}


#' Render a Status Message
#' @param text The message.
#' @param type `"neutral"`, `"success"`, `"warning"` or `"error"`.
#' @return A Shiny tag.
#' @export
ak_status <- function(text, type = "neutral") {
  shiny::tags$div(
    class = paste0(
      "status-message",
      switch(
        type,
        success = " status-success",
        warning = " status-warning",
        error = " status-error",
        ""
      )
    ),
    text
  )
}


#' Say Which Estimation Engine the Run Will Use
#'
#' The `level` cell decides this, and it is the difference between a run that
#' takes seconds and one that takes minutes on a wide disaggregation. Shown
#' before the run rather than discovered during it.
#'
#' Nothing is rendered when no row asks for a confidence interval: that is the
#' fast case, and it needs no explanation.
#'
#' @param split The list returned by `loa_engine_split()`.
#' @return A Shiny tag, or an empty `tagList()`.
#' @export
ak_engine_note <- function(split) {
  if (is.null(split) || split$analyses == 0 || split$survey == 0) {
    return(shiny::tagList())
  }

  shiny::tagList(
    ak_status(
      sprintf(
        paste0(
          "%d of %d analyses set a confidence level, so they are estimated ",
          "with the survey package: %s estimation(s) across %d grouping ",
          "variable(s)."
        ),
        split$survey,
        split$analyses,
        format(split$survey_estimations, big.mark = ","),
        split$group_variables
      ),
      "warning"
    ),
    ak_status(
      paste0(
        "The survey engine re-subsets the data once per level of each ",
        "grouping variable, so its cost grows with the disaggregation while ",
        "the fast engine's does not. Clearing the level cell on rows that do ",
        "not publish a confidence interval is the largest speed-up available ",
        "- the point estimates are identical either way."
      )
    )
  )
}


#' Render the Combination-Base Caveat
#'
#' Both combination maps are passed, because a question can carry either block
#' or both and the caveat is the same either way.
#'
#' @param ... One or more combination maps (`choice_combinations`,
#'   `exclusive_combinations`).
#' @return A Shiny tag; empty when every respondent who answered is in the base.
#' @export
ak_exclusive_base_panel <- function(...) {
  notes <- unique(unlist(lapply(list(...), ak_exclusive_base_note), use.names = FALSE))
  if (length(notes) == 0) {
    return(shiny::tagList())
  }

  shiny::tags$div(
    class = "status-message status-warning",
    shiny::tags$strong(
      "The choice-combination rows use a smaller denominator than the rest of the workbook."
    ),
    shiny::tags$ul(
      class = "ak-caveat",
      lapply(notes, shiny::tags$li)
    ),
    "Footnote this wherever the combination percentages are published."
  )
}


#' Render a Section With a Heading
#' @param title Section heading.
#' @param ... Section contents.
#' @return A Shiny tag.
#' @export
ak_section <- function(title, ...) {
  shiny::tags$div(
    class = "dataset-section",
    shiny::tags$h3(title),
    ...
  )
}
