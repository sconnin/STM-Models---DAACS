# Tests for R/model_formulas.R

test_that("the prevalence formula is the one every model family was fitted with", {
  # Pinning this matters more than it looks: the formula was written out
  # verbatim in four places, and a model fitted with a different covariate set
  # would still load, plot, and report -- it would simply be a different model
  # than the one the results describe.
  expect_equal(
    deparse1(PREVALENCE_FORMULA),
    "~gender + race + first_gen + s(age) + gender * s(age)"
  )
})

test_that("the content formula lets vocabulary vary by gender only", {
  expect_equal(deparse1(CONTENT_FORMULA), "~gender")
})

test_that("both are one-sided formulas, as the stm() arguments require", {
  expect_s3_class(PREVALENCE_FORMULA, "formula")
  expect_s3_class(CONTENT_FORMULA, "formula")
  expect_length(PREVALENCE_FORMULA, 2)
  expect_length(CONTENT_FORMULA, 2)
})

test_that("the prevalence terms are exactly the covariates the analyses report", {
  terms <- attr(stats::terms(PREVALENCE_FORMULA), "term.labels")

  expect_setequal(
    terms,
    c("gender", "race", "first_gen", "s(age)", "gender:s(age)")
  )
})
