# Tests for R/multiple_comparisons.R

# estimateEffect stores, per topic, a list of posterior draws each carrying an
# estimate and a covariance. pooled_estimates() reads only those fields plus
# $topics and $data, so a stub is enough.
stub_effect <- function(draws_per_topic, topics = 1, n_data = 100) {
  structure(
    list(
      parameters = draws_per_topic,
      topics = topics,
      data = data.frame(x = seq_len(n_data))
    ),
    class = "estimateEffect"
  )
}

one_draw <- function(est, vcov) list(list(est = est, vcov = vcov))

test_that("a single draw pools to itself", {
  est <- c("(Intercept)" = 1, genderM = 0.5)
  v <- diag(c(0.04, 0.01))
  fit <- stub_effect(list(one_draw(est, v)))

  pooled <- pooled_estimates(fit, topic = 1)

  expect_equal(pooled$est, est)
  # No between-draw variance to add. cov() of one row is NA, which would
  # propagate into every downstream test if it were not handled.
  expect_equal(pooled$vcov, v)
  expect_false(anyNA(pooled$vcov))
  expect_equal(pooled$rdf, 98) # 100 rows - 2 coefficients
})

test_that("pooling adds within-draw and between-draw variance", {
  # Two draws whose estimates differ: the mixture is wider than either draw.
  draws <- list(
    list(est = c(a = 0), vcov = matrix(1, 1, 1)),
    list(est = c(a = 2), vcov = matrix(1, 1, 1))
  )
  fit <- stub_effect(list(draws))

  pooled <- pooled_estimates(fit, topic = 1)

  expect_equal(unname(pooled$est), 1) # mean of 0 and 2
  # within = 1, between = var(c(0, 2)) = 2.
  expect_equal(unname(pooled$vcov[1, 1]), 3)
})

test_that("an absent topic is an error, not a silent wrong answer", {
  fit <- stub_effect(list(one_draw(c(a = 1), matrix(1, 1, 1))), topics = 1)
  expect_error(pooled_estimates(fit, topic = 7), "not present")
})

test_that("a one-term joint test reproduces the marginal t-test", {
  # This is the property that makes the joint test trustworthy: with q = 1 the
  # F statistic is the squared t, and the p-values agree exactly.
  est <- c("(Intercept)" = 0.2, genderM = 0.5)
  v <- diag(c(0.01, 0.04))
  fit <- stub_effect(list(one_draw(est, v)), n_data = 500)

  joint <- joint_effect_test(fit, "^gender", method = "none")

  t_stat <- 0.5 / sqrt(0.04)
  rdf <- 498
  expect_equal(joint$statistic, t_stat^2)
  expect_equal(joint$p.value, 2 * stats::pt(abs(t_stat), rdf, lower.tail = FALSE))
  expect_equal(joint$n_terms, 1)
})

test_that("the joint statistic is the Wald quadratic form over its rank", {
  # b = (1, 1), V = I: W = b' V^-1 b = 2, F = W / 2 = 1.
  est <- c("(Intercept)" = 0, `s(age)1` = 1, `s(age)2` = 1)
  v <- diag(c(1, 1, 1))
  fit <- stub_effect(list(one_draw(est, v)), n_data = 1000)

  joint <- joint_effect_test(fit, "^s\\(age\\)", method = "none")

  expect_equal(joint$n_terms, 2)
  expect_equal(joint$statistic, 1)
  expect_equal(joint$df1, 2)
  expect_equal(joint$df2, 997)
})

test_that("the intercept is never part of a joint test", {
  # A pattern loose enough to catch the intercept must not pull it in: the
  # question is whether a covariate matters, and the intercept is not one.
  est <- c("(Intercept)" = 5, genderM = 0.1)
  v <- diag(c(0.001, 1))
  fit <- stub_effect(list(one_draw(est, v)), n_data = 200)

  joint <- joint_effect_test(fit, ".", method = "none")

  expect_equal(joint$n_terms, 1)
})

test_that("a pattern that matches nothing names the available terms", {
  fit <- stub_effect(list(one_draw(c("(Intercept)" = 1, genderM = 1), diag(2))))
  expect_error(joint_effect_test(fit, "^race"), "genderM")
})

test_that("joint tests are adjusted across topics", {
  strong <- one_draw(c("(Intercept)" = 0, x = 1), diag(c(1, 0.0001)))
  weak <- one_draw(c("(Intercept)" = 0, x = 0.01), diag(c(1, 1)))
  fit <- stub_effect(list(strong, weak), topics = c(1, 2), n_data = 500)

  adjusted <- joint_effect_test(fit, "^x")
  unadjusted <- joint_effect_test(fit, "^x", method = "none")

  expect_equal(nrow(adjusted), 2)
  # BH never lowers a p-value, and leaves the largest one unchanged.
  expect_true(all(adjusted$p.adjusted >= unadjusted$p.value))
  expect_equal(max(adjusted$p.adjusted), max(unadjusted$p.value))
})

test_that("adjustment drops the intercept and orders by adjusted p", {
  local_mocked_bindings(
    tidy = function(x, ...) {
      tibble::tibble(
        topic = c(1L, 1L, 2L),
        term = c("(Intercept)", "genderM", "genderM"),
        p.value = c(0.001, 0.04, 0.001)
      )
    },
    .package = "tidytext"
  )

  out <- adjust_effects("fit")

  expect_false("(Intercept)" %in% out$term)
  expect_equal(nrow(out), 2)
  expect_true("p.adjusted" %in% names(out))
  expect_true(!is.unsorted(out$p.adjusted))
  # Two tests: BH scales the larger p by 2/2 = 1 and the smaller by 2/1.
  expect_equal(out$p.adjusted, c(0.002, 0.04))
})

test_that("only terms below the adjusted threshold survive", {
  local_mocked_bindings(
    tidy = function(x, ...) {
      tibble::tibble(
        topic = 1:20,
        term = rep("genderM", 20),
        p.value = c(0.0001, rep(0.4, 19))
      )
    },
    .package = "tidytext"
  )

  # Uncorrected, one term clears 0.05. Corrected, it still does -- 0.0001 * 20
  # is 0.002 -- while the 0.4s do not, which is the point.
  expect_equal(nrow(significant_effects_adjusted("fit")), 1)
})

test_that("the threshold must be a single probability", {
  expect_error(significant_effects_adjusted("fit", alpha = 0))
  expect_error(significant_effects_adjusted("fit", alpha = 1.5))
  expect_error(significant_effects_adjusted("fit", alpha = c(0.01, 0.05)))
})

test_that("the exploratory caveat names the method and the rate", {
  note <- exploratory_note(alpha = 0.05)

  expect_type(note, "character")
  expect_length(note, 1)
  expect_match(note, "exploratory")
  expect_match(note, "Benjamini-Hochberg")
  expect_match(note, "false discovery rate at 0.05")
  expect_match(note, "joint test")
})
