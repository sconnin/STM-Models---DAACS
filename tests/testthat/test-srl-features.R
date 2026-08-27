# Tests for R/srl_features.R

fake_institution_data <- function(n = 3, id_prefix = "id") {
  d <- data.frame(
    DAACS_ID = paste0(id_prefix, seq_len(n)),
    stringsAsFactors = FALSE
  )
  for (measure in SRL_MEASURES) { # nolint: object_usage_linter.
    d[[measure]] <- seq_len(n) + 0.5
  }
  d$unrelated_column <- "dropped"
  d
}

test_that("all fourteen SRL scales are named, in source order", {
  expect_length(SRL_MEASURES, 14)
  expect_equal(SRL_MEASURES[1], "srl_grit")
  expect_equal(SRL_MEASURES[2], "srl_strategies")
  expect_true(all(grepl("^srl_", SRL_MEASURES)))
  expect_false(anyDuplicated(SRL_MEASURES) > 0)
})

test_that("the subset carries the identifiers, the scales, and nothing else", {
  result <- srl_subset(fake_institution_data(), institution = "WG")

  expect_equal(names(result), c("doc_id", "institution", SRL_MEASURES))
  expect_false("unrelated_column" %in% names(result))
  expect_true(all(result$institution == "WG"))
})

test_that("every institution is stamped with its own code", {
  wg <- srl_subset(fake_institution_data(), institution = "WG")
  ec <- srl_subset(fake_institution_data(), institution = "EC")
  alb <- srl_subset(fake_institution_data(), institution = "Alb", unavailable = "srl_grit")

  expect_equal(unique(wg$institution), "WG")
  expect_equal(unique(ec$institution), "EC")
  expect_equal(unique(alb$institution), "Alb")
  # The three frames must be rbind-compatible; that is the whole point.
  expect_equal(names(wg), names(ec))
  expect_equal(names(wg), names(alb))
})

test_that("an unavailable measure is NA_real_, not dropped and not NaN", {
  # S1-1: Albany collects no grit measure. The column has to exist so the three
  # institutions stack, and it has to be honestly empty rather than carrying
  # NaN, which `%in% NaN` then failed to match.
  result <- srl_subset(
    fake_institution_data(),
    institution = "Alb",
    unavailable = "srl_grit"
  )

  expect_true("srl_grit" %in% names(result))
  expect_true(all(is.na(result$srl_grit)))
  expect_false(any(is.nan(result$srl_grit)))
  expect_type(result$srl_grit, "double")
  # Every other scale survives untouched.
  expect_false(any(is.na(result$srl_strategies)))
})

test_that("rows missing the required measure are dropped", {
  data <- fake_institution_data(n = 4)
  data$srl_strategies[c(2, 4)] <- NA

  result <- srl_subset(data, institution = "EC")

  expect_equal(nrow(result), 2)
  expect_false(any(is.na(result$srl_strategies)))
})

test_that("requiring a measure that is unavailable is an error, not an empty frame", {
  # Silently returning zero rows would remove an institution from every forest
  # downstream without anything failing.
  expect_error(
    srl_subset(
      fake_institution_data(),
      institution = "Alb",
      unavailable = "srl_strategies"
    ),
    "would drop every row"
  )
})

test_that("a measure name that is not an SRL scale is rejected", {
  expect_error(
    srl_subset(fake_institution_data(), institution = "WG", unavailable = "srl_gritt"),
    "not SRL scales|not an SRL|not SRL"
  )
})

test_that("missing source columns are named in the error", {
  data <- fake_institution_data()
  data$srl_mindset <- NULL

  expect_error(srl_subset(data, institution = "WG"), "srl_mindset")
})
