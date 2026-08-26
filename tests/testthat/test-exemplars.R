# Tests for R/exemplars.R
#
# The point of these is the two defects the three original copies shared: an
# unrestored setwd(), and a loop that used positions where topic numbers were
# meant. Both are testable without fitting an STM model, because the
# findThoughts/plotQuote calls are injectable.

test_that("exemplar_output_dir builds a path without touching the filesystem", {
  tmp <- tempfile()
  path <- exemplar_output_dir("Essay_Passages", "stm.model12", base_dir = tmp)

  expect_equal(path, file.path(tmp, "Essay_Passages", "stm.model12"))
  expect_false(dir.exists(path)) # pure construction, creates nothing
})

test_that("exemplar_output_dir rejects empty components", {
  expect_error(exemplar_output_dir("", "x"), "non-empty")
  expect_error(exemplar_output_dir("x", ""), "non-empty")
})

test_that("the working directory is unchanged after writing exemplars", {
  # The original setwd() had no restore, so every later chunk ran elsewhere.
  before <- getwd()
  tmp <- tempfile()
  dir.create(tmp)

  write_topic_exemplars(
    model = NULL, model_label = "m", topics = 1:2, texts = c("a", "b"),
    base_dir = tmp,
    find_thoughts = function(...) list(docs = list("text")),
    plot_quote = function(...) graphics::plot(1) # must draw: png() writes no file otherwise
  )

  expect_equal(getwd(), before)
})

test_that("topics are iterated by NUMBER, not by position", {
  # exemplars(model, n, c(3, 7)) previously rendered topics 1 and 2 while
  # labelling the output "Topic 1" and "Topic 2".
  seen <- integer(0)
  tmp <- tempfile()
  dir.create(tmp)

  write_topic_exemplars(
    model = NULL, model_label = "m", topics = c(3, 7), texts = "x",
    base_dir = tmp,
    find_thoughts = function(model, texts, topics, n) {
      seen <<- c(seen, topics)
      list(docs = list("text"))
    },
    plot_quote = function(...) graphics::plot(1) # must draw: png() writes no file otherwise
  )

  expect_equal(seen, c(3, 7))
})

test_that("output filenames use the topic number", {
  tmp <- tempfile()
  dir.create(tmp)

  written <- write_topic_exemplars(
    model = NULL, model_label = "m", topics = c(3, 7), texts = "x",
    base_dir = tmp,
    find_thoughts = function(...) list(docs = list("text")),
    plot_quote = function(...) graphics::plot(1) # must draw: png() writes no file otherwise
  )

  expect_equal(basename(written), c("Topic3.png", "Topic7.png"))
  expect_true(all(file.exists(written)))
})

test_that("findThoughts is called once per topic, not twice", {
  # The original called it twice with identical arguments and discarded the
  # second result.
  calls <- 0L
  tmp <- tempfile()
  dir.create(tmp)

  write_topic_exemplars(
    model = NULL, model_label = "m", topics = 1:3, texts = "x",
    base_dir = tmp,
    find_thoughts = function(...) {
      calls <<- calls + 1L
      list(docs = list("text"))
    },
    plot_quote = function(...) graphics::plot(1) # must draw: png() writes no file otherwise
  )

  expect_equal(calls, 3L)
})

test_that("write_top_essays writes plain essay text, one per line", {
  tmp <- tempfile()
  dir.create(tmp)

  topic_table <- data.frame(
    doc_id = 1:3, institution = "WG",
    Topic1 = c(0.1, 0.9, 0.5), Topic2 = c(0.7, 0.2, 0.3)
  )
  raw <- data.frame(
    doc_id = 1:3, institution = "WG",
    text = c("essay one", "essay two", "essay three")
  )

  written <- write_top_essays(
    topic_table,
    topics = 1, raw_data = raw,
    model_label = "m12", n = 2, base_dir = tmp
  )

  contents <- readLines(written[1])
  # Highest Topic1 first: doc 2 (0.9) then doc 3 (0.5).
  expect_equal(contents, c("essay two", "essay three"))
  # No quotes and no trailing frequency column, unlike the table() version.
  expect_false(any(grepl('"', contents)))
  expect_false(any(grepl("\t1$", contents)))
})

test_that("write_top_essays orders by the requested topic column", {
  tmp <- tempfile()
  dir.create(tmp)

  topic_table <- data.frame(
    doc_id = 1:3, institution = "WG",
    Topic1 = c(0.1, 0.9, 0.5), Topic2 = c(0.7, 0.2, 0.3)
  )
  raw <- data.frame(
    doc_id = 1:3, institution = "WG",
    text = c("essay one", "essay two", "essay three")
  )

  written <- write_top_essays(
    topic_table,
    topics = 2, raw_data = raw,
    model_label = "m12", n = 1, base_dir = tmp
  )

  # Highest Topic2 is doc 1 (0.7) -- a different answer than Topic1 gives.
  expect_equal(readLines(written[1]), "essay one")
})

test_that("a missing topic column is an error", {
  tmp <- tempfile()
  dir.create(tmp)
  topic_table <- data.frame(doc_id = 1L, institution = "WG", Topic1 = 0.5)
  raw <- data.frame(doc_id = 1L, institution = "WG", text = "x")

  expect_error(
    write_top_essays(topic_table,
      topics = 9, raw_data = raw,
      model_label = "m", base_dir = tmp
    ),
    "no column 'Topic9'"
  )
})
