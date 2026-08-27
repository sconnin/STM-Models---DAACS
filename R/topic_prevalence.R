#' Mean topic prevalence across the corpus, and the bar chart that shows it.
#'
#' Replaces five near-identical blocks in stm_analyses_final.Rmd -- one per
#' model family -- that differed only in which model they read and what the plot
#' subtitle said. Each block tidied gamma, summed it by topic, divided by the
#' document count, reordered the topic factor by proportion, and drew the same
#' `geom_col`.
#'
#' Two corrections are baked in here rather than repeated five times
#' (CODE_REVIEW.md S1-4, S1-5):
#'
#'   - The divisor is passed in and asserted, not hard-coded. The original wrote
#'     8120 where the corpus holds 8210 -- the same digits transposed.
#'   - NAs are removed with `na.rm = TRUE`. The original wrote
#'     `sum(., is.na(.), 0)`, and because `sum()` is variadic that added the
#'     COUNT of NAs to the total rather than excluding them.
#'
#' Each document's topic proportions sum to 1, so summing gamma across documents
#' and dividing by the document count gives the mean proportion per topic.

#' Mean proportion of the corpus attributable to each topic.
#'
#' @param model A fitted STM object.
#' @param n_documents Number of documents in the corpus the model was fitted on.
#'   Pass `length(documents)` rather than a literal.
#' @return A tibble of `topic`, `gamma` (summed) and `proportion` (percent).
#'   `topic` is a factor ordered by ascending proportion, which is what puts the
#'   largest topic at the top once the plot is flipped.
topic_proportions <- function(model, n_documents) {
  stopifnot(
    is.numeric(n_documents),
    length(n_documents) == 1,
    n_documents > 0
  )

  # nolint start: object_usage_linter.
  # `.data` is the documented-safe way to name a column inside a data mask. It
  # has to stay unqualified -- `rlang::.data$x` is evaluated eagerly and errors.
  # lintr cannot resolve it outside a package namespace.
  proportions <- tidytext::tidy(model, matrix = "gamma") |>
    dplyr::group_by(.data$topic) |>
    dplyr::summarise(gamma = sum(.data$gamma, na.rm = TRUE), .groups = "drop") |>
    dplyr::mutate(proportion = (.data$gamma / n_documents) * 100)
  # nolint end

  ordered_topics <- proportions$topic[order(proportions$proportion, decreasing = FALSE)]
  proportions$topic <- factor(proportions$topic, levels = ordered_topics)
  proportions
}

#' Bar chart of topic prevalence.
#'
#' @param proportions Output of [topic_proportions()].
#' @param title Plot title.
#' @param subtitle Plot subtitle -- name the model family here, since that is
#'   the only thing that distinguishes these charts from one another.
#' @return A ggplot object.
plot_topic_proportions <- function(proportions, title, subtitle) {
  stopifnot(
    is.data.frame(proportions),
    all(c("topic", "proportion") %in% names(proportions))
  )

  ggplot2::ggplot(
    proportions,
    # nolint next: object_usage_linter.
    ggplot2::aes(x = .data$topic, y = .data$proportion, fill = .data$proportion)
  ) +
    ggplot2::geom_col(alpha = 0.8, show.legend = FALSE) +
    ggplot2::labs(
      title = title,
      subtitle = subtitle,
      y = "Proportion (%)",
      x = "Topic"
    ) +
    ggplot2::coord_flip() +
    ggplot2::theme_classic()
}
