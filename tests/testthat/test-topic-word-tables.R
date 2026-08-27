# Tests for R/topic_word_tables.R

# labelTopics() returns a list of matrices, one row per topic, one column per
# word, in the order prob, frex, lift, score.
fake_labels <- function(k = 3, n = 4) {
  make <- function(tag) {
    matrix(
      paste0(tag, "_w", seq_len(k * n)),
      nrow = k, ncol = n
    )
  }
  list(prob = make("p"), frex = make("f"), lift = make("l"), score = make("s"))
}

test_that("one row per topic, with the words collapsed into a single cell", {
  labels <- fake_labels(k = 3, n = 4)

  table <- topic_word_table(labels[1], "Probability")
  rendered <- as.character(table)

  expect_s3_class(table, "knitr_kable")
  # Three topic rows, and the words joined with ", ".
  expect_true(any(grepl("p_w1, p_w4, p_w7, p_w10", rendered, fixed = TRUE)))
})

test_that("the caption names the weighting and the model", {
  labels <- fake_labels()

  rendered <- as.character(topic_word_table(labels[2], "FREX", "STM Prevalence Model"))

  expect_true(any(grepl('Top Topic Words - "FREX": STM Prevalence Model', rendered, fixed = TRUE)))
})

test_that("all four weightings are returned, named and in labelTopics() order", {
  # Reading only prob and frex has already produced a wrong conclusion about
  # what a topic is about; lift and score carry the distinctive terms.
  tables <- topic_word_tables(fake_labels())

  expect_length(tables, 4)
  expect_equal(names(tables), c("prob", "frex", "lift", "score"))
  expect_true(all(vapply(tables, inherits, logical(1), "knitr_kable")))

  captions <- vapply(tables, function(x) paste(as.character(x), collapse = " "), character(1))
  expect_true(grepl("Probability", captions[["prob"]]))
  expect_true(grepl("FREX", captions[["frex"]]))
  expect_true(grepl("Lift", captions[["lift"]]))
  expect_true(grepl("Score", captions[["score"]]))
})

test_that("each weighting reads its own matrix, not the first one", {
  # The four blocks this replaces differed only in the index they read, which is
  # exactly the kind of copy that drifts into reading the same element twice.
  tables <- topic_word_tables(fake_labels())

  expect_true(grepl("p_w1", paste(as.character(tables$prob), collapse = " ")))
  expect_true(grepl("f_w1", paste(as.character(tables$frex), collapse = " ")))
  expect_true(grepl("l_w1", paste(as.character(tables$lift), collapse = " ")))
  expect_true(grepl("s_w1", paste(as.character(tables$score), collapse = " ")))
  expect_false(grepl("p_w1", paste(as.character(tables$score), collapse = " ")))
})
