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
  notes <- unique(unlist(
    lapply(list(...), ak_exclusive_base_note),
    use.names = FALSE
  ))
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


#' Short Help Text Under a Control
#' @param ... Text.
#' @return A Shiny tag.
ak_help <- function(...) {
  shiny::tags$p(class = "ak-help", ...)
}


#' The Script Behind the Previous / Next Buttons
#'
#' Opens a main tab by its title and scrolls back to the top of the tabs.
#'
#' @return A script tag.
ak_nav_script <- function() {
  shiny::tags$script(shiny::HTML(
    "function akShowTab(value) {
       $('#panels a[data-value=\"' + value + '\"]').tab('show');
       window.scrollTo({top: Math.max($('#panels').offset().top - 12, 0), behavior: 'smooth'});
     }"
  ))
}


#' Previous / Next Buttons at the Foot of a Tab
#'
#' @param prev,nxt Titles of the tabs either side, or `NULL` for none.
#' @return A Shiny tag.
ak_tab_nav <- function(prev = NULL, nxt = NULL) {
  button <- function(direction, target) {
    if (is.null(target)) {
      return(NULL)
    }
    is_prev <- direction == "prev"
    shiny::tags$button(
      type = "button",
      class = paste0("btn btn-default ak-nav-", direction),
      onclick = sprintf("akShowTab('%s')", target),
      if (is_prev) shiny::icon("arrow-left"),
      shiny::tags$span(
        class = "ak-nav-label",
        paste0(if (is_prev) "Previous: " else "Next: ", target)
      ),
      if (!is_prev) shiny::icon("arrow-right")
    )
  }

  shiny::tags$nav(
    class = "ak-nav ak-nav-bottom",
    `aria-label` = "Move between tabs",
    shiny::tags$div(class = "ak-nav-side", button("prev", prev)),
    shiny::tags$div(class = "ak-nav-side ak-nav-side-next", button("next", nxt))
  )
}


#' The State of Each Main Tab
#'
#' Drives the mark on each tab: `warning` (its number, in yellow), `error` (a
#' red cross); `done` and `todo` both show its plain number. Pure, so it can be
#' tested without a browser.
#'
#' @param dataset_ok,dataset_failed Logical: the dataset loaded / failed.
#' @param loa_ok,loa_failed Logical: the List of Analysis loaded / failed.
#' @param problems The problems table, or `NULL` before anything is checked.
#' @param results_ready Logical.
#' @return A named character vector, one state per tab title.
ak_tab_states <- function(
  dataset_ok,
  dataset_failed,
  loa_ok,
  loa_failed,
  problems,
  results_ready
) {
  counts <- if (is.null(problems)) NULL else ak_problem_counts(problems)
  c(
    "Dataset" = if (dataset_ok) {
      "done"
    } else if (dataset_failed) {
      "error"
    } else {
      "todo"
    },
    "List of Analysis" = if (loa_ok) {
      "done"
    } else if (loa_failed) {
      "error"
    } else {
      "todo"
    },
    "Checks" = if (is.null(counts)) {
      "todo"
    } else if (counts[["error"]] > 0L) {
      "error"
    } else if (counts[["warning"]] > 0L) {
      "warning"
    } else {
      "done"
    },
    "Results" = if (results_ready) "done" else "todo"
  )
}
