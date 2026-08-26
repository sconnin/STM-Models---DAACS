#' Write representative-passage figures and top-essay files per topic.
#'
#' Replaces three near-identical `exemplars()` definitions in
#' essay_examples_final.Rmd, which differed only in output folder, number of
#' documents shown, and text size.
#'
#' Three defects are fixed once here rather than three times:
#'
#'   1. `setwd()` with no restore. Each copy changed the working directory and
#'      never changed it back, so every later chunk in the notebook ran somewhere
#'      else, and an error mid-loop stranded the session in a subdirectory. Paths
#'      are now built with `file.path()` and no directory change happens at all.
#'   2. `for (i in seq_along(topic))` used a POSITION where a TOPIC NUMBER was
#'      meant. This was correct only because every caller passed `1:K`. Calling
#'      `exemplars(model, 6, c(3, 7))` would have silently rendered topics 1 and 2
#'      while labelling the output "Topic 1" and "Topic 2".
#'   3. `findThoughts()` was called twice per topic with identical arguments --
#'      once for `$docs`, once for `$index` -- and the second result was never
#'      used. That doubled the work for nothing.
#'
#' `find_thoughts` and `plot_quote` are injectable so the iteration and naming
#' logic can be tested without fitting an STM model.

#' Build the output directory path for one model's exemplars.
#'
#' Pure path construction: creates nothing, changes no state.
#'
#' @param collection Top-level folder name, e.g. "Essay_Passages".
#' @param model_label Subfolder label identifying the model, e.g. "stm.model12".
#' @param base_dir Directory the collection sits under.
#' @return A single path string.
exemplar_output_dir <- function(collection, model_label, base_dir = getwd()) {
  if (!nzchar(collection) || !nzchar(model_label)) {
    stop("collection and model_label must be non-empty", call. = FALSE)
  }
  file.path(base_dir, collection, model_label)
}

#' Write one representative-passage figure per topic.
#'
#' @param model A fitted STM model.
#' @param model_label Label used in the subfolder name and figure titles.
#' @param topics Integer vector of TOPIC NUMBERS to render (not positions).
#' @param texts Character vector of document texts, aligned to the model.
#' @param collection Top-level output folder.
#' @param n Number of documents per topic.
#' @param text_cex Text scaling passed to the plotting function.
#' @param base_dir Directory the collection sits under.
#' @param find_thoughts,plot_quote Injectable for testing; default to stm's.
#' @return Invisibly, a character vector of the files written.
write_topic_exemplars <- function(model,
                                  model_label,
                                  topics,
                                  texts,
                                  collection = "Essay_Passages",
                                  n = 5,
                                  text_cex = 1,
                                  base_dir = getwd(),
                                  find_thoughts = stm::findThoughts,
                                  plot_quote = stm::plotQuote) {
  stopifnot(is.numeric(topics), length(topics) > 0, is.character(texts))

  out_dir <- exemplar_output_dir(collection, model_label, base_dir)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  written <- character(0)

  # Iterate topic NUMBERS, not positions -- see note 2 above.
  for (topic in topics) {
    path <- file.path(out_dir, paste0("Topic", topic, ".png"))

    grDevices::png(path)
    # Close the device even if plotting fails, so an error does not leave a
    # half-written file open and every later plot redirected into it.
    on.exit(grDevices::dev.off(), add = TRUE)

    docs <- find_thoughts(model, texts = texts, topics = topic, n = n)$docs[[1]]
    plot_quote(
      docs,
      width = 100,
      maxwidth = 500,
      text.cex = text_cex,
      main = paste0(model_label, ": Topic ", topic)
    )

    grDevices::dev.off()
    on.exit()

    written <- c(written, path)
  }

  invisible(written)
}

#' Write the top-N raw essays per topic to text files.
#'
#' Replaces `top.essays()`. Same `setwd()` and loop-index fixes as above.
#'
#' @param topic_table A data frame of document-topic proportions with `doc_id`,
#'   `institution`, and one `TopicN` column per topic.
#' @param topics Integer vector of topic numbers.
#' @param raw_data Data frame with `doc_id`, `institution`, `text`.
#' @param model_label Subfolder label.
#' @param collection Top-level output folder.
#' @param n Number of essays per topic.
#' @param base_dir Directory the collection sits under.
#' @return Invisibly, a character vector of the files written.
write_top_essays <- function(topic_table,
                             topics,
                             raw_data,
                             model_label,
                             collection = "Top Essays",
                             n = 5,
                             base_dir = getwd()) {
  stopifnot(is.data.frame(topic_table), is.data.frame(raw_data), is.numeric(topics))

  out_dir <- exemplar_output_dir(collection, model_label, base_dir)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  written <- character(0)

  for (topic in topics) {
    topic_column <- paste0("Topic", topic)
    if (!topic_column %in% names(topic_table)) {
      stop("topic_table has no column '", topic_column, "'", call. = FALSE)
    }

    # The original sorted with base `order()` on a hard-coded column position,
    # noting in a comment that dplyr::arrange could not be made to work without
    # hardcoding the name. all_of() + .data resolves that cleanly.
    top_docs <- topic_table |>
      dplyr::select(dplyr::all_of(c("doc_id", "institution", topic_column))) |>
      dplyr::arrange(dplyr::desc(.data[[topic_column]])) |> # nolint: object_usage_linter.
      utils::head(n)

    essays <- dplyr::inner_join(raw_data, top_docs, by = c("doc_id", "institution"))

    # OUTPUT CHANGE, deliberate. The original piped the essays through
    # base::table() before write.table():
    #
    #   inner_join(...) %>% select(text) %>% table() # nolint: commented_code_linter.
    #
    # table() counts occurrences of each distinct essay. Essays are unique, so
    # every count was 1, and each line came out as:
    #
    #   "first essay text"\t1
    #
    # -- quoted, with a meaningless frequency column appended. (The local
    # variable `table` did not shadow this: R skips non-function bindings when a
    # name is used in call position.) writeLines() writes the essays plainly,
    # which is evidently what was intended. Verified against the original.
    path <- file.path(out_dir, paste0("topic", topic, "essays.txt"))
    writeLines(essays$text, path)
    written <- c(written, path)
  }

  invisible(written)
}
