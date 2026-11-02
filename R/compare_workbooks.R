# =============================================================================
# Comparing two results workbooks cell by cell
# =============================================================================
#
# The guard behind every performance change: the workbook has to come out the
# same. Keep a reference run - one dataset, one List of Analysis, the workbook
# as it is produced today - and compare against it after every change.
#
#   ak_expect_same_workbook(
#     "reference/analysiskit_4Mi_20261102-090000.xlsx",
#     "analysiskit_4Mi_20261102-101500.xlsx"
#   )
#
# What is compared is every cell's stored value *and* how it is stored. The
# second half matters: a batched write that merges a text column and a numeric
# one produces a workbook that looks perfect and has stopped doing arithmetic,
# and a comparison that only read the displayed values would pass it.
#
# What is not compared is styling. A fill colour that moves is a cosmetic
# regression and shows up by eye; this is about the numbers.
#
# This file is development tooling. It is deliberately left out of
# ak_manifest_files(), so it is never deployed and never recorded as a
# dependency of the application.
# =============================================================================


#' Resolve openxlsx's Shared-String Table to Plain Text
#'
#' A shared string is stored as its `<si>` XML, rich-text runs and all. The
#' tags are dropped and the five XML entities unescaped, which is what the cell
#' shows.
#'
#' @param shared The workbook's `sharedStrings`.
#' @return A character vector, indexed from 1.
#' @keywords internal
ak_shared_strings <- function(shared) {
  if (length(shared) == 0) {
    return(character(0))
  }

  text <- gsub("<[^>]*>", "", as.character(shared))
  text <- gsub("&lt;", "<", text, fixed = TRUE)
  text <- gsub("&gt;", ">", text, fixed = TRUE)
  text <- gsub("&quot;", "\"", text, fixed = TRUE)
  text <- gsub("&apos;", "'", text, fixed = TRUE)
  # Last, or an escaped entity would be unescaped twice.
  gsub("&amp;", "&", text, fixed = TRUE)
}


#' Read Every Populated Cell of a Workbook, With Its Storage Type
#'
#' `read.xlsx()` is not enough here. It infers a type per column, so a
#' statistic column with a text header above it comes back as character for its
#' whole length, and a number that has silently become text is indistinguishable
#' from the number itself. This reads openxlsx's own cell table instead, where
#' the two are different things.
#'
#' @param path Path to an `.xlsx` file.
#' @return A named list, one element per sheet, each a data frame of `row`,
#'   `col`, `type` (`"number"`, `"text"` or openxlsx's own code) and `value`.
#' @export
ak_snapshot_workbook <- function(path) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("Comparing workbooks requires the 'openxlsx' package.", call. = FALSE)
  }
  if (!file.exists(path)) {
    stop(paste0("No workbook at ", path, "."), call. = FALSE)
  }

  wb <- openxlsx::loadWorkbook(path)
  strings <- ak_shared_strings(wb$sharedStrings)

  snapshot <- lapply(seq_along(wb$sheet_names), function(i) {
    cells <- wb$worksheets[[i]]$sheet_data

    keep <- !is.na(cells$v)
    rows <- as.integer(cells$rows)[keep]
    cols <- as.integer(cells$cols)[keep]
    kind <- cells$t[keep]
    value <- as.character(cells$v)[keep]

    # t == 1 is a shared string; anything else stores its value inline, and
    # numbers are much the commonest of those.
    is_text <- !is.na(kind) & kind == 1
    if (any(is_text)) {
      value[is_text] <- strings[as.integer(value[is_text]) + 1L]
    }

    type <- ifelse(is.na(kind), "number", ifelse(kind == 1, "text", paste0("t", kind)))
    type[!is.na(kind) & kind == 0] <- "number"

    data.frame(
      row = rows, col = cols, type = type, value = value,
      stringsAsFactors = FALSE
    )
  })

  stats::setNames(snapshot, wb$sheet_names)
}


#' Describe One Cell Difference
#' @keywords internal
ak_cell_difference <- function(sheet, row, column, before, after) {
  data.frame(
    sheet = sheet,
    row = row,
    column = column,
    before = before,
    after = after,
    stringsAsFactors = FALSE
  )
}


#' Compare Two Results Workbooks Cell by Cell
#'
#' Numbers are compared with a tolerance, because a percentage that survives a
#' round trip through Excel is not bit-identical. Text is compared exactly. A
#' cell that is a number in one workbook and text in the other is a difference
#' however the two read on screen, and a cell populated in one workbook and
#' empty in the other is reported as well.
#'
#' @param before Path to the reference workbook, or a snapshot from
#'   \code{\link{ak_snapshot_workbook}}.
#' @param after Path to the new workbook, or a snapshot.
#' @param tolerance Absolute tolerance for numeric cells. Default `1e-9`.
#' @param max_report How many differing cells to list. Default `50`.
#' @return A list with `identical` (logical), `summary` (one line), and
#'   `differences` (a data frame).
#' @export
ak_compare_workbooks <- function(before, after, tolerance = 1e-9, max_report = 50L) {
  snap <- function(x) if (is.character(x)) ak_snapshot_workbook(x) else x
  a <- snap(before)
  b <- snap(after)

  found <- list()
  note <- function(df) found[[length(found) + 1]] <<- df

  for (sheet in setdiff(names(a), names(b))) {
    note(ak_cell_difference(sheet, NA, NA, "sheet present", "sheet missing"))
  }
  for (sheet in setdiff(names(b), names(a))) {
    note(ak_cell_difference(sheet, NA, NA, "sheet missing", "sheet present"))
  }

  for (sheet in intersect(names(a), names(b))) {
    x <- a[[sheet]]
    y <- b[[sheet]]

    key_x <- paste(x$row, x$col, sep = ",")
    key_y <- paste(y$row, y$col, sep = ",")

    gone <- setdiff(key_x, key_y)
    new <- setdiff(key_y, key_x)
    shared <- intersect(key_x, key_y)

    describe <- function(df, keys) {
      hit <- match(keys, paste(df$row, df$col, sep = ","))
      paste0(df$type[hit], ": ", df$value[hit])
    }

    if (length(gone) > 0) {
      hit <- match(gone, key_x)
      note(ak_cell_difference(
        sheet, x$row[hit], x$col[hit], describe(x, gone), "empty"
      ))
    }
    if (length(new) > 0) {
      hit <- match(new, key_y)
      note(ak_cell_difference(
        sheet, y$row[hit], y$col[hit], "empty", describe(y, new)
      ))
    }
    if (length(shared) == 0) next

    ix <- match(shared, key_x)
    iy <- match(shared, key_y)

    type_x <- x$type[ix]
    type_y <- y$type[iy]
    value_x <- x$value[ix]
    value_y <- y$value[iy]

    # Same type and both numeric: compare the numbers, so a float that came
    # back one bit different is not a finding. Everything else is compared as
    # written, and a type that has changed always is.
    numeric_both <- type_x == "number" & type_y == "number"
    differs <- type_x != type_y

    if (any(numeric_both)) {
      nx <- suppressWarnings(as.numeric(value_x[numeric_both]))
      ny <- suppressWarnings(as.numeric(value_y[numeric_both]))
      differs[numeric_both] <- xor(is.na(nx), is.na(ny)) |
        (!is.na(nx) & !is.na(ny) & abs(nx - ny) > tolerance)
    }

    other <- !numeric_both & type_x == type_y
    if (any(other)) {
      differs[other] <- value_x[other] != value_y[other]
    }

    if (any(differs)) {
      note(ak_cell_difference(
        sheet,
        x$row[ix][differs], x$col[ix][differs],
        paste0(type_x[differs], ": ", value_x[differs]),
        paste0(type_y[differs], ": ", value_y[differs])
      ))
    }
  }

  differences <- if (length(found) == 0) {
    ak_cell_difference(character(0), integer(0), integer(0), character(0), character(0))
  } else {
    do.call(rbind, found)
  }

  summary <- if (nrow(differences) == 0) {
    "The two workbooks are identical in every cell."
  } else {
    paste0(
      nrow(differences), " differing cell(s) across ",
      length(unique(differences$sheet)), " sheet(s)."
    )
  }

  list(
    identical = nrow(differences) == 0,
    summary = summary,
    differences = utils::head(differences, max_report)
  )
}


#' Stop Unless Two Workbooks Match
#'
#' The form to use in a test or a script: silent when nothing moved, and a
#' readable error naming the first few cells that did when something has.
#'
#' @inheritParams ak_compare_workbooks
#' @return Invisibly `TRUE`.
#' @export
ak_expect_same_workbook <- function(before, after, tolerance = 1e-9) {
  result <- ak_compare_workbooks(before, after, tolerance = tolerance)

  if (!result$identical) {
    shown <- utils::head(result$differences, 10)
    stop(
      paste0(
        result$summary, "\n  - ",
        paste(
          sprintf(
            "%s [row %s, col %s]: %s -> %s",
            shown$sheet, shown$row, shown$column, shown$before, shown$after
          ),
          collapse = "\n  - "
        )
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}
