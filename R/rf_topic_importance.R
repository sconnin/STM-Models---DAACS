#' Random forest models of topic prevalence against SRL predictors.
#'
#' Replaces twelve copy-pasted `randomForest()` blocks and twelve `vip()` calls
#' in stm.rforestmodels.final.Rmd.
#'
#' Two deliberate departures from the code this replaces, both of which change
#' reported numbers:
#'
#'   1. Every model reads the same topic table. The original block read
#'      `srl.topics.32` for topic 2 and `srl.topics.12` for the other eleven,
#'      so the topic-2 result described a different latent topic than its label
#'      claimed (CODE_REVIEW.md S1-2). Iterating makes that class of error
#'      impossible rather than merely fixed.
#'   2. Fitting is seeded. The original called `randomForest()` with no
#'      `set.seed()`, so its variance-explained figures could not be regenerated
#'      (S3-2). Several of those figures were near zero or negative, where the
#'      sign itself is not stable across runs.
#'
#' Variance explained is returned as data rather than recorded in trailing
#' comments (S3-4), so it can be sorted, plotted, and diffed against a re-run.
#'
#' Variable importance is drawn with ggplot2 instead of `vip::vip()`. vip does
#' no computation for a randomForest object -- it reads
#' `randomForest::importance()` and plots it -- and vip has been archived from
#' CRAN, so `install.packages("vip")` fails. The numbers are unchanged; only the
#' rendering differs.

#' Fit one random forest per topic.
#'
#' @param topic_data Data frame with one column per topic (`Topic1`, `Topic2`,
#'   ...) and the predictor columns.
#' @param topics Integer vector of topic numbers to model.
#' @param predictor_prefix Column-name prefix identifying predictors.
#' @param ntree Number of trees per forest.
#' @param seed Base seed. Topic `k` is fitted with `seed + k` so each model is
#'   independently reproducible.
#' @return A tibble with one row per topic: `topic`, `n_obs`, `var_explained`
#'   (maximum of `rsq * 100`), and `model` (a list column of the fitted forests).
fit_topic_forests <- function(topic_data,
                              topics,
                              predictor_prefix = "srl",
                              ntree = 1000,
                              seed = 20220527) {
  stopifnot(is.data.frame(topic_data), is.numeric(topics), length(topics) > 0)

  missing_cols <- setdiff(paste0("Topic", topics), names(topic_data))
  if (length(missing_cols) > 0) {
    stop(
      "topic_data is missing expected columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  fit_one <- function(k) {
    response <- paste0("Topic", k)
    model_data <- topic_data |>
      dplyr::select(dplyr::all_of(response), dplyr::starts_with(predictor_prefix)) |>
      stats::na.omit()

    if (ncol(model_data) < 2) {
      stop("no predictor columns matched prefix '", predictor_prefix, "'", call. = FALSE)
    }

    set.seed(seed + k)
    model <- randomForest::randomForest(
      stats::as.formula(paste(response, "~ .")),
      data = model_data,
      ntree = ntree,
      importance = TRUE
    )

    tibble::tibble(
      topic = k,
      n_obs = nrow(model_data),
      var_explained = max(model$rsq) * 100,
      model = list(model)
    )
  }

  purrr::list_rbind(purrr::map(topics, fit_one))
}

#' Extract variable importance from a fitted random forest.
#'
#' @param model A `randomForest` object fitted with `importance = TRUE`.
#' @param metric Importance column to extract. `"%IncMSE"` for regression,
#'   `"MeanDecreaseGini"` for classification.
#' @param n_features Number of top predictors to keep.
#' @return A tibble of `variable` and `importance`, descending.
topic_importance <- function(model, metric = "%IncMSE", n_features = 10) {
  importance_matrix <- randomForest::importance(model)

  if (!metric %in% colnames(importance_matrix)) {
    stop(
      "metric '", metric, "' not found; available: ",
      paste(colnames(importance_matrix), collapse = ", "),
      ". Was the model fitted with importance = TRUE?",
      call. = FALSE
    )
  }

  # Plain base sort rather than dplyr::arrange(): this is a small frame built
  # locally, so tidy evaluation buys nothing and pulls in a `.data` pronoun the
  # linter cannot resolve outside a data mask.
  importance_values <- as.numeric(importance_matrix[, metric])
  ranked <- order(importance_values, decreasing = TRUE)

  tibble::tibble(
    variable = rownames(importance_matrix)[ranked],
    importance = importance_values[ranked]
  ) |>
    utils::head(n_features)
}

#' Plot variable importance for one fitted forest.
#'
#' Drop-in replacement for `vip::vip()`; reads the same underlying values.
#'
#' @inheritParams topic_importance
#' @param title Plot title.
#' @return A ggplot object.
plot_topic_importance <- function(model,
                                  metric = "%IncMSE",
                                  n_features = 10,
                                  title = NULL) {
  importance_data <- topic_importance(model, metric = metric, n_features = n_features)

  # Reverse so the largest bar sits at the top once flipped.
  importance_data$variable <- factor(
    importance_data$variable,
    levels = rev(importance_data$variable)
  )

  # `.data$` is the documented-safe way to refer to columns inside aes(). It has
  # to stay unqualified -- `rlang::.data$x` is evaluated eagerly and errors with
  # "Can't subset `.data` outside of a data mask context". lintr cannot resolve
  # the pronoun, hence the exclusion.
  ggplot2::ggplot(
    importance_data,
    ggplot2::aes(x = .data$variable, y = .data$importance) # nolint: object_usage_linter.
  ) +
    ggplot2::geom_col(alpha = 0.8) +
    ggplot2::coord_flip() +
    ggplot2::labs(x = NULL, y = metric, title = title) +
    ggplot2::theme_classic()
}
