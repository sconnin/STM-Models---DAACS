#' Multiple-comparison handling for topic-prevalence regressions.
#'
#' The analysis tests every covariate against all twelve topics and keeps the
#' terms below a threshold. Counted the way the code filters them, that is 228
#' hypotheses in the main-effects set alone -- 12 for gender, 72 for race (seven
#' levels, six contrasts each), 24 for first-generation status (three levels,
#' including UNKNOWN), and 120 for age, because `s(age)` expands to a ten-term
#' spline. At an uncorrected 0.05 you should expect roughly eleven "significant"
#' terms from noise alone.
#'
#' Three complementary responses live here, and they are meant to be used
#' together rather than chosen between:
#'
#'   1. `exploratory_note()` -- the caveat that has to appear in any write-up.
#'      Adjustment narrows the claim; it does not turn exploratory work into
#'      confirmatory work.
#'   2. `adjust_effects()` -- Benjamini-Hochberg false-discovery-rate control
#'      within each covariate family. FDR is the right family here: the question
#'      is "what fraction of the topics I report are spurious", not "am I certain
#'      about this one topic".
#'   3. `joint_effect_test()` -- one test per topic for a multi-term covariate.
#'      "Is age related to this topic" is ONE question, and asking it of ten
#'      spline coefficients separately is both too many tests and the wrong test:
#'      it can flag a topic because a single basis function happened to be steep,
#'      and miss one where age matters smoothly but no term stands out alone.
#'
#' There is a second reason to prefer the joint test. `summary.estimateEffect()`
#' -- which `tidy()` calls -- estimates standard errors by simulating `nsim`
#' draws per posterior sample, so term-level p-values are not reproducible:
#' measured on this corpus they move by up to 0.016 between calls, enough to
#' change how many terms clear 0.05. The pooling below is analytic, and returns
#' bit-identical results on repeat calls.

#' Pool an estimateEffect's posterior draws into one estimate and covariance.
#'
#' `estimateEffect(uncertainty = "Global")` stores several posterior draws per
#' topic, each with its own coefficients and covariance. The distribution of
#' interest is the mixture over draws, whose variance is the mean of the
#' within-draw covariances plus the covariance of the draw estimates -- the
#' quantity `summary.estimateEffect()` approximates by simulation.
#'
#' @param effect An `estimateEffect` fit.
#' @param topic Topic number.
#' @return List of `est` (named vector), `vcov` (matrix) and `rdf` (residual
#'   degrees of freedom, matching the convention used by `summary()`).
pooled_estimates <- function(effect, topic) {
  index <- which(effect$topics == topic)
  if (length(index) != 1) {
    stop("topic ", topic, " is not present in this estimateEffect fit", call. = FALSE)
  }

  draws <- effect$parameters[[index]]
  estimates <- do.call(rbind, lapply(draws, function(d) d$est))
  within <- Reduce(`+`, lapply(draws, function(d) d$vcov)) / length(draws)
  # With a single draw there is no between-draw variation to add, and cov() of
  # one row is NA rather than zero -- which would silently poison the test.
  between <- if (nrow(estimates) > 1) {
    stats::cov(estimates)
  } else {
    matrix(0, nrow = ncol(estimates), ncol = ncol(estimates))
  }

  est <- colMeans(estimates)
  names(est) <- names(draws[[1]]$est)

  list(
    est = est,
    vcov = within + between,
    rdf = nrow(effect$data) - length(est)
  )
}

#' Joint Wald test that a group of terms is zero, one test per topic.
#'
#' Use this for any covariate that enters as more than one column -- a spline, or
#' a factor with several levels -- where the substantive question is whether the
#' covariate matters at all, not whether one particular contrast does.
#'
#' @param effect An `estimateEffect` fit.
#' @param pattern Regular expression matching the coefficient names to test
#'   jointly, e.g. `"^s\\(age\\)"` or `"^race"`. The intercept is never included.
#' @param topics Topics to test; defaults to all topics in the fit.
#' @param method Adjustment applied across topics, passed to [stats::p.adjust()].
#' @return A tibble of `topic`, `n_terms`, `statistic` (F), `df1`, `df2`,
#'   `p.value` and `p.adjusted`.
joint_effect_test <- function(effect, pattern, topics = NULL, method = "BH") {
  if (is.null(topics)) topics <- effect$topics

  rows <- lapply(topics, function(k) {
    pooled <- pooled_estimates(effect, k)
    keep <- grepl(pattern, names(pooled$est)) & names(pooled$est) != "(Intercept)"
    if (!any(keep)) {
      stop(
        "no coefficients match '", pattern, "'. Available: ",
        paste(setdiff(names(pooled$est), "(Intercept)"), collapse = ", "),
        call. = FALSE
      )
    }

    b <- pooled$est[keep]
    v <- pooled$vcov[keep, keep, drop = FALSE]
    q <- length(b)

    # Wald statistic scaled to an F, so that q = 1 reproduces the squared
    # t-statistic summary() reports for a single term.
    statistic <- as.numeric(t(b) %*% solve(v, b)) / q

    tibble::tibble(
      topic = k,
      n_terms = q,
      statistic = statistic,
      df1 = q,
      df2 = pooled$rdf,
      p.value = stats::pf(statistic, q, pooled$rdf, lower.tail = FALSE)
    )
  })

  out <- dplyr::bind_rows(rows)
  out$p.adjusted <- stats::p.adjust(out$p.value, method = method)
  out
}

#' Tidy an effect and add false-discovery-rate adjusted p-values.
#'
#' Adjustment is applied across every non-intercept term in the fit, which is the
#' covariate's own family of tests. Adjusting across a family you did not
#' actually test -- or failing to adjust across one you did -- is the error this
#' function exists to make hard.
#'
#' @param effect An `estimateEffect` fit.
#' @param method Passed to [stats::p.adjust()]. Benjamini-Hochberg by default.
#' @return A tibble of the tidied terms with `p.adjusted` added, ordered by it.
adjust_effects <- function(effect, method = "BH") {
  tidytext::tidy(effect) |>
    dplyr::filter(.data$term != "(Intercept)") |> # nolint: object_usage_linter.
    dplyr::mutate(p.adjusted = stats::p.adjust(.data$p.value, method = method)) |>
    dplyr::arrange(.data$p.adjusted)
}

#' Terms surviving the adjusted threshold.
#'
#' @param effect An `estimateEffect` fit.
#' @param alpha False-discovery rate to control at.
#' @param method Passed to [stats::p.adjust()].
#' @return A tibble of surviving terms.
significant_effects_adjusted <- function(effect, alpha = 0.05, method = "BH") {
  stopifnot(is.numeric(alpha), length(alpha) == 1, alpha > 0, alpha < 1)

  adjust_effects(effect, method = method) |>
    dplyr::filter(.data$p.adjusted < alpha) # nolint: object_usage_linter.
}

#' The caveat that belongs in any write-up of these results.
#'
#' Held here so the results document and the notebooks state the same thing, and
#' so revising it revises it everywhere.
#'
#' @param alpha The false-discovery rate controlled at.
#' @return A single string.
exploratory_note <- function(alpha = 0.05) {
  paste0(
    "These are exploratory, hypothesis-generating results. Every covariate was ",
    "tested against all twelve topics, so p-values are reported after ",
    "Benjamini-Hochberg adjustment within each covariate family, controlling ",
    "the false discovery rate at ", format(alpha), ". Multi-term covariates ",
    "(the age spline, and race across its seven levels) are assessed with one ",
    "joint test per topic rather than one test per coefficient. Adjustment ",
    "narrows what may be claimed; it does not make this a confirmatory study. ",
    "No effect reported here should be treated as established without ",
    "pre-registered replication."
  )
}
