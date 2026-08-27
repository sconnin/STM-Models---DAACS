# Tests for R/topic_prevalence.R

# A minimal object that tidy.STM accepts: it reads $theta and nothing else.
stub_model <- function(theta) {
  structure(list(theta = theta), class = "STM")
}

test_that("proportions are the column sums of theta, as a percentage of n", {
  # Two documents, three topics. Column sums: 0.7, 0.7, 0.6.
  theta <- matrix(
    c(
      0.5, 0.3, 0.2,
      0.2, 0.4, 0.4
    ),
    nrow = 2, byrow = TRUE
  )

  result <- topic_proportions(stub_model(theta), n_documents = 2)

  expect_equal(nrow(result), 3)
  expect_setequal(as.integer(as.character(result$topic)), 1:3)
  # Hand-verified: 0.7 / 2 * 100 = 35, 0.6 / 2 * 100 = 30.
  expect_equal(sort(round(result$proportion, 10)), c(30, 35, 35))
})

test_that("proportions sum to 100 when the divisor is the document count", {
  # Every document's topic proportions sum to 1, so the percentages must total
  # 100. This is the invariant S1-5 broke: the divisor was hard-coded 8120
  # against a corpus of 8210, which inflated every proportion by ~1.1%.
  set.seed(1)
  raw <- matrix(runif(40), nrow = 10)
  theta <- raw / rowSums(raw)

  result <- topic_proportions(stub_model(theta), n_documents = 10)

  expect_equal(sum(result$proportion), 100)
})

test_that("a wrong divisor is visible rather than silent", {
  set.seed(2)
  raw <- matrix(runif(40), nrow = 10)
  theta <- raw / rowSums(raw)

  understated <- topic_proportions(stub_model(theta), n_documents = 11)

  expect_false(isTRUE(all.equal(sum(understated$proportion), 100)))
})

test_that("NA gamma values are excluded, not counted", {
  # S1-4: the original wrote `sum(., is.na(.), 0)`. sum() is variadic, so that
  # added the COUNT of NAs to the total instead of removing them -- one whole
  # unit of probability mass per missing value.
  # Topic 1 holds 0.5 and one NA; topic 2 holds 0.5 and 1.0.
  theta <- matrix(c(0.5, 0.5, NA, 1.0), nrow = 2, byrow = TRUE)

  result <- topic_proportions(stub_model(theta), n_documents = 2)

  topic1 <- result$proportion[as.character(result$topic) == "1"]
  # 0.5 / 2 * 100 = 25. The old arithmetic gave (0.5 + 1) / 2 * 100 = 75,
  # because the 1 was the NA count rather than a gamma value.
  expect_equal(topic1, 25)
})

test_that("topics are ordered by ascending proportion for the flipped axis", {
  theta <- matrix(c(0.1, 0.6, 0.3), nrow = 1)

  result <- topic_proportions(stub_model(theta), n_documents = 1)

  expect_s3_class(result$topic, "factor")
  # Smallest first, so coord_flip() puts the largest topic at the top.
  expect_equal(levels(result$topic), c("1", "3", "2"))
})

test_that("the divisor must be a single positive number", {
  theta <- matrix(c(0.5, 0.5), nrow = 1)

  expect_error(topic_proportions(stub_model(theta), n_documents = 0))
  expect_error(topic_proportions(stub_model(theta), n_documents = -5))
  expect_error(topic_proportions(stub_model(theta), n_documents = c(10, 20)))
  expect_error(topic_proportions(stub_model(theta), n_documents = "8210"))
})

test_that("the plot carries the title and subtitle it was given", {
  theta <- matrix(c(0.4, 0.6), nrow = 1)
  proportions <- topic_proportions(stub_model(theta), n_documents = 1)

  p <- plot_topic_proportions(
    proportions,
    title = "Topic Prevalence: K = 12",
    subtitle = "Prevalence: stm()"
  )

  expect_s3_class(p, "ggplot")
  expect_equal(p$labels$title, "Topic Prevalence: K = 12")
  expect_equal(p$labels$subtitle, "Prevalence: stm()")
  expect_equal(p$labels$y, "Proportion (%)")
  expect_equal(p$labels$x, "Topic")
})

test_that("plotting rejects a frame that is not proportions", {
  expect_error(plot_topic_proportions(data.frame(a = 1), "t", "s"))
})
