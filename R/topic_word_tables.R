#' Top-words tables from `labelTopics()` output.
#'
#' Replaces four near-identical blocks in stm_analyses_final.Rmd that differed
#' only in which element of `labelTopics()` they read and what the caption said.
#' The function was written inline in the notebook; it lives here so a test can
#' reach it.
#'
#' `kable()` is knitr's, not kableExtra's. kableExtra was declared by the
#' notebook and never used, and it depends on svglite -> systemfonts, which needs
#' system font headers the analysis has no other reason to require.

#' One table of the top words per topic under a single weighting.
#'
#' @param label_metric One element of a [stm::labelTopics()] result -- for
#'   example `labels[1]` for probability, `labels[2]` for FREX. Pass the
#'   single-bracket subset, which keeps the matrix wrapped in a list.
#' @param metric_name Name of the weighting, used in the caption.
#' @param model_name Name of the model family, used in the caption.
#' @return A `knitr_kable` object.
topic_word_table <- function(label_metric,
                             metric_name,
                             model_name = "STM Prevalence Model") {
  label_metric |>
    as.data.frame() |>
    tibble::rownames_to_column(var = "topic") |>
    tidyr::unite("collapse", !1, remove = FALSE, sep = ", ") |>
    dplyr::rename(top_words = "collapse") |>
    dplyr::select("topic", "top_words") |>
    knitr::kable(
      caption = paste0(
        'Top Topic Words - "', metric_name, '": ', model_name
      )
    )
}

#' All four weightings for one model, in the order `labelTopics()` returns them.
#'
#' Read all four before judging what a topic is about. `prob` and `frex` favour
#' frequent terms; `lift` and `score` surface the low-frequency, highly
#' distinctive terms that identify a topic's subject matter. Reading only the
#' first two has already produced one wrong conclusion in this project -- topic 5
#' was called mathematics-free when `lift` and `score` both lead with
#' `mathemat` and `equat` (CODE_REVIEW.md, topic-label re-validation).
#'
#' @param labels A [stm::labelTopics()] result.
#' @param model_name Name of the model family, used in the captions.
#' @return A named list of four `knitr_kable` objects.
topic_word_tables <- function(labels, model_name = "STM Prevalence Model") {
  metrics <- c(prob = "Probability", frex = "FREX", lift = "Lift", score = "Score")

  tables <- lapply(seq_along(metrics), function(i) {
    topic_word_table(labels[i], metrics[[i]], model_name)
  })
  stats::setNames(tables, names(metrics))
}
