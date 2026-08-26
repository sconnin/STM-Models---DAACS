# Tests for R/topic_labels.R

test_that("there are exactly 12 labels, in topic order", {
  expect_length(TOPIC_LABELS_K12, 12)
  expect_type(TOPIC_LABELS_K12, "character")
  expect_equal(TOPIC_LABELS_K12[1], "Areas for Improvement")
  expect_equal(TOPIC_LABELS_K12[12], "Managing Distractions")
})

test_that("labels match the vector the notebooks used verbatim", {
  # Guards against a well-meaning edit silently relabelling published figures.
  expect_equal(
    TOPIC_LABELS_K12,
    c(
      "Areas for Improvement",
      "Developing Writing Skills",
      "Test Anxiety",
      "Returning Learners-Degree Completion",
      "Improving Math Skills",
      "Confirmation and Readiness",
      "Transferable Strategies & Academic Success",
      "Time Management",
      "Getting it Right Getting it Done",
      "Adjusting Ones Mindset",
      "Appying and Retaining Subject Matter",
      "Managing Distractions"
    )
  )
})

test_that("topic_labels() returns all labels by default", {
  expect_equal(topic_labels(), TOPIC_LABELS_K12)
  expect_equal(topic_labels(12), TOPIC_LABELS_K12)
})

test_that("topic_labels() selects a subset in the order requested", {
  expect_equal(topic_labels(12, c(3, 1)), c("Test Anxiety", "Areas for Improvement"))
})

test_that("any K other than 12 is refused rather than recycled", {
  # Silently recycling would mislabel a plot, which is worse than failing.
  for (k in c(6, 18, 24, 32)) {
    expect_error(topic_labels(k), "exist only for the K = 12 model")
  }
})

test_that("out-of-range topic numbers are refused", {
  expect_error(topic_labels(12, 0), "between 1 and 12")
  expect_error(topic_labels(12, 13), "between 1 and 12")
})

test_that("topic_rename_map is shaped for dplyr::rename", {
  m <- topic_rename_map()
  expect_length(m, 12)
  # rename() takes new_name = old_name, so names are labels and values TopicN.
  expect_equal(unname(m[1]), "Topic1")
  expect_equal(names(m)[1], "Areas for Improvement")
  expect_equal(unname(m), paste0("Topic", 1:12))
})

test_that("topic_rename_map actually renames a frame", {
  d <- as.data.frame(matrix(1, nrow = 1, ncol = 12))
  names(d) <- paste0("Topic", 1:12)
  renamed <- dplyr::rename(d, dplyr::all_of(topic_rename_map()))
  expect_equal(names(renamed), TOPIC_LABELS_K12)
})
