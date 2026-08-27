#' Covariate effects on topic prevalence, and the plots that report them.
#'
#' Replaces four `estimateEffect()` calls, four `tidy() |> filter()` blocks, six
#' `plot(..., method = "difference")` calls and three near-identical gender-by-age
#' interaction triplets in stm_analyses_final.Rmd.
#'
#' The repetition mattered rather than merely being untidy. Every difference plot
#' repeated the same six arguments -- `topics`, `cex`, `model`, `method`,
#' `labeltype` and `custom.labels` -- so a change of model or label had to be
#' made in six places, and the copies had already drifted: one carried
#' `Text.cex`, which is not a graphical parameter, and warned six times per plot
#' (CODE_REVIEW.md S2-9).

#' Estimate covariate effects on topic prevalence.
#'
#' @param model A fitted STM object.
#' @param metadata The corpus `meta` data frame.
#' @param formulas Named list of formulas, e.g. `list(gender = 1:12 ~ gender)`.
#'   Names become the names of the returned list.
#' @param uncertainty Passed to [stm::estimateEffect()].
#' @return A named list of `estimateEffect` fits.
estimate_effects <- function(model, metadata, formulas, uncertainty = "Global") {
  stopifnot(is.list(formulas), length(formulas) > 0, !is.null(names(formulas)))

  lapply(formulas, function(f) {
    stm::estimateEffect(
      formula = f,
      stmobj = model,
      metadata = metadata,
      uncertainty = uncertainty
    )
  })
}

#' Terms whose effect is significant at `alpha`.
#'
#' The intercept is dropped: it is not an effect of anything, and reporting it
#' alongside the covariate terms invites reading it as one.
#'
#' @param effect An `estimateEffect` fit.
#' @param alpha Significance threshold.
#' @return A tibble of significant terms.
significant_effects <- function(effect, alpha = 0.05) {
  stopifnot(is.numeric(alpha), length(alpha) == 1, alpha > 0, alpha < 1)

  # nolint start: object_usage_linter.
  tidytext::tidy(effect) |>
    dplyr::filter(.data$term != "(Intercept)" & .data$p.value < alpha)
  # nolint end
}

#' Contrast two levels of a categorical covariate across all topics.
#'
#' @param effect An `estimateEffect` fit.
#' @param covariate Name of the covariate to plot.
#' @param value1,value2 The two levels to contrast. `value1` plots to the right.
#' @param xlab,main,xlim Axis label, title, and x limits.
#' @param model The STM object the effect was estimated against.
#' @param topics Topics to include.
#' @return Invisibly, the value returned by [stm::plot.estimateEffect()].
plot_difference_effect <- function(effect,
                                   covariate,
                                   value1,
                                   value2,
                                   xlab,
                                   main,
                                   xlim,
                                   model,
                                   topics = 1:12) {
  invisible(plot(
    effect,
    covariate = covariate,
    topics = topics,
    cex = .25,
    model = model,
    method = "difference",
    cov.value1 = value1,
    cov.value2 = value2,
    xlab = xlab,
    main = main,
    xlim = xlim,
    labeltype = "custom",
    custom.labels = topic_labels() # nolint: object_usage_linter.
  ))
}

#' Topic prevalence as a continuous function of a covariate, one plot per topic.
#'
#' @param effect An `estimateEffect` fit.
#' @param covariate Name of the continuous covariate.
#' @param topics Topics to plot, one figure each.
#' @param model The STM object the effect was estimated against.
#' @param xlab Axis label.
#' @return Invisibly `NULL`; called for the plots.
plot_continuous_effect <- function(effect, covariate, topics, model, xlab = "Age") {
  for (k in topics) {
    plot(
      effect,
      covariate,
      method = "continuous",
      topics = k,
      model = model,
      printlegend = FALSE, # TRUE prints the topic number, not a useful legend
      xlab = xlab,
      main = stringr::str_glue("Topic Prevalence as a Function of {xlab}: Topic {k}")
    )
  }
  invisible(NULL)
}

#' One topic's age curve, drawn separately for each gender on shared axes.
#'
#' Three copies of this stood in the notebook, differing only in topic number and
#' y limits. Each was a triplet -- male line, female line added over it, then a
#' hand-placed legend -- where the second call has to omit `main` and `ylim` and
#' pass `add = TRUE`, which is exactly the kind of asymmetry that drifts when
#' copied.
#'
#' @param effect An `estimateEffect` fit for the single topic being plotted.
#' @param model The interaction fit supplying the model frame.
#' @param topic Topic number, used for the title.
#' @param ylim Y limits, chosen per topic to fit the curves.
#' @param legend_x,legend_y Legend position in data coordinates.
#' @param alpha_label Significance level named in the title.
#' @return Invisibly `NULL`; called for the plots.
plot_gender_age_interaction <- function(effect,
                                        model,
                                        topic,
                                        ylim,
                                        legend_x = 18,
                                        legend_y = max(ylim),
                                        alpha_label = "P < 0.10") {
  stopifnot(is.numeric(ylim), length(ylim) == 2)

  plot(
    effect,
    covariate = "age",
    model = model,
    method = "continuous",
    xlab = "Age",
    moderator = "gender",
    moderator.value = "M",
    linecol = "blue",
    ylim = ylim,
    printlegend = FALSE,
    main = paste0(
      # topic_labels() is sourced from R/topic_labels.R, which lintr cannot see.
      "Topic ", topic, ": ", topic_labels(topics = topic), # nolint: object_usage_linter.
      " (", alpha_label, ")"
    )
  )

  plot(
    effect,
    covariate = "age",
    model = model,
    method = "continuous",
    xlab = "Age",
    moderator = "gender",
    moderator.value = "F",
    linecol = "red",
    add = TRUE,
    printlegend = FALSE
  )

  legend(
    legend_x, legend_y, c("Male", "Female"),
    lwd = 2, col = c("blue", "red")
  )
  invisible(NULL)
}
