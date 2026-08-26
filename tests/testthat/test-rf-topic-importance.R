# Tests for R/rf_topic_importance.R
#
# Synthetic data only. Nothing here touches the DAACS corpus, so these run on
# any machine with the package library restored.

make_synthetic_topics <- function(n = 200, n_topics = 3, seed = 1) {
  set.seed(seed)
  srl_names <- c(
    "srl_grit", "srl_strategies", "srl_motivation", "srl_anxiety", "srl_planning"
  )
  d <- as.data.frame(matrix(stats::runif(n * length(srl_names)), nrow = n))
  names(d) <- srl_names

  # Topic1 has real signal from srl_anxiety; the rest are noise. This gives the
  # importance assertions something deterministic to find.
  d$Topic1 <- 0.8 * d$srl_anxiety + stats::rnorm(n, sd = 0.02)
  for (k in seq_len(n_topics)[-1]) {
    d[[paste0("Topic", k)]] <- stats::runif(n)
  }
  d
}

test_that("fit_topic_forests returns one row per requested topic", {
  d <- make_synthetic_topics()
  out <- fit_topic_forests(d, topics = 1:3, ntree = 50)

  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 3)
  expect_equal(out$topic, 1:3)
  expect_setequal(names(out), c("topic", "n_obs", "var_explained", "model"))
  expect_true(all(vapply(out$model, inherits, logical(1), "randomForest")))
})

test_that("each topic is modelled against its own response column", {
  d <- make_synthetic_topics()
  out <- fit_topic_forests(d, topics = 1:3, ntree = 50)

  responses <- vapply(
    out$model,
    function(m) all.vars(stats::formula(m))[1],
    character(1)
  )
  expect_equal(responses, c("Topic1", "Topic2", "Topic3"))
})

test_that("fitting is reproducible under a fixed seed", {
  d <- make_synthetic_topics()
  a <- fit_topic_forests(d, topics = 1:2, ntree = 50, seed = 99)
  b <- fit_topic_forests(d, topics = 1:2, ntree = 50, seed = 99)

  expect_equal(a$var_explained, b$var_explained)
  expect_equal(
    randomForest::importance(a$model[[1]]),
    randomForest::importance(b$model[[1]])
  )
})

test_that("different seeds give different fits", {
  d <- make_synthetic_topics()
  a <- fit_topic_forests(d, topics = 1, ntree = 50, seed = 1)
  b <- fit_topic_forests(d, topics = 1, ntree = 50, seed = 2)

  expect_false(isTRUE(all.equal(a$var_explained, b$var_explained)))
})

test_that("a missing topic column is an error, not a silent skip", {
  d <- make_synthetic_topics(n_topics = 2)
  expect_error(
    fit_topic_forests(d, topics = 1:5, ntree = 50),
    "missing expected columns"
  )
})

test_that("a prefix matching no predictors is an error", {
  d <- make_synthetic_topics()
  expect_error(
    fit_topic_forests(d, topics = 1, predictor_prefix = "nomatch", ntree = 50),
    "no predictor columns matched"
  )
})

test_that("topic_importance recovers the predictor carrying the signal", {
  d <- make_synthetic_topics()
  out <- fit_topic_forests(d, topics = 1, ntree = 200)
  imp <- topic_importance(out$model[[1]])

  expect_s3_class(imp, "tbl_df")
  expect_setequal(names(imp), c("variable", "importance"))
  expect_equal(imp$variable[1], "srl_anxiety")
  # Descending order
  expect_false(is.unsorted(rev(imp$importance)))
})

test_that("topic_importance honours n_features", {
  d <- make_synthetic_topics()
  out <- fit_topic_forests(d, topics = 1, ntree = 50)
  expect_equal(nrow(topic_importance(out$model[[1]], n_features = 3)), 3)
})

test_that("an unavailable importance metric is reported clearly", {
  d <- make_synthetic_topics()
  out <- fit_topic_forests(d, topics = 1, ntree = 50)
  expect_error(
    topic_importance(out$model[[1]], metric = "MeanDecreaseGini"),
    "not found; available"
  )
})

test_that("plot_topic_importance returns a ggplot with the expected data", {
  d <- make_synthetic_topics()
  out <- fit_topic_forests(d, topics = 1, ntree = 50)
  p <- plot_topic_importance(out$model[[1]], n_features = 4, title = "Topic 1")

  expect_s3_class(p, "ggplot")
  expect_equal(nrow(p$data), 4)
  expect_equal(p$labels$title, "Topic 1")
})

test_that("plot bars are ordered largest-first after the coord flip", {
  d <- make_synthetic_topics()
  out <- fit_topic_forests(d, topics = 1, ntree = 200)
  p <- plot_topic_importance(out$model[[1]], n_features = 5)

  # Factor levels are reversed so the largest lands at the top when flipped.
  expect_equal(as.character(rev(levels(p$data$variable)))[1], "srl_anxiety")
})

test_that("importance values match randomForest::importance exactly", {
  d <- make_synthetic_topics()
  out <- fit_topic_forests(d, topics = 1, ntree = 50)
  model <- out$model[[1]]

  expected <- randomForest::importance(model)[, "%IncMSE"]
  got <- topic_importance(model, n_features = length(expected))

  expect_equal(
    got$importance,
    unname(sort(expected, decreasing = TRUE))
  )
})
