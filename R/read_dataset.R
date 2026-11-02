read_uploaded_dataset <- function(file_info) {
  if (is.null(file_info) || nrow(file_info) != 1L) {
    stop("Please select one dataset to upload.", call. = FALSE)
  }

  extension <- tolower(tools::file_ext(file_info$name))

  if (!extension %in% c("csv", "xlsx")) {
    stop("Unsupported file type. Please upload a CSV or XLSX file.", call. = FALSE)
  }

  data <- switch(extension,
    csv = utils::read.csv(
      file_info$datapath,
      stringsAsFactors = FALSE,
      check.names = FALSE,
      na.strings = c("", "NA", "N/A", "NULL")
    ),
    xlsx = {
      if (!requireNamespace("readxl", quietly = TRUE)) {
        stop(
          "Reading XLSX files requires the 'readxl' package. Install it with install.packages('readxl').",
          call. = FALSE
        )
      }

      as.data.frame(
        readxl::read_excel(file_info$datapath, sheet = 1),
        check.names = FALSE
      )
    }
  )

  if (ncol(data) == 0L) {
    stop("The uploaded file does not contain any columns.", call. = FALSE)
  }

  list(
    data = data,
    extension = toupper(extension),
    filename = file_info$name,
    size = file_info$size,
    # Counted once, here, rather than inside dataset_overview(). duplicated()
    # on a data frame fingerprints every row against every column - 3.8 s on a
    # 10,000 x 745 export - and dataset_overview() is rendered through
    # renderTable(), so leaving it there paid that cost again on every
    # invalidation of the dataset reactive rather than once per upload.
    duplicate_rows = sum(duplicated(data))
  )
}

dataset_overview <- function(dataset) {
  data <- dataset$data

  # Older callers (and any test building the list by hand) may not carry the
  # count, so it is still computed here when it is absent.
  duplicates <- dataset$duplicate_rows
  if (is.null(duplicates)) duplicates <- sum(duplicated(data))

  data.frame(
    Measure = c(
      "File name",
      "File type",
      "File size",
      "Rows",
      "Columns",
      "Duplicate rows"
    ),
    Value = c(
      dataset$filename,
      dataset$extension,
      format(structure(dataset$size, class = "object_size"), units = "auto"),
      format(nrow(data), big.mark = ","),
      format(ncol(data), big.mark = ","),
      format(duplicates, big.mark = ",")
    ),
    check.names = FALSE
  )
}

dataset_columns <- function(dataset) {
  data <- dataset$data

  data.frame(
    Column = names(data),
    Type = vapply(data, function(column) class(column)[1L], character(1)),
    Missing = vapply(data, function(column) sum(is.na(column)), integer(1)),
    Unique = vapply(data, function(column) length(unique(column[!is.na(column)])), integer(1)),
    check.names = FALSE
  )
}
