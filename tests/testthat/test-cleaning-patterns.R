# Tests for R/cleaning_patterns.R
#
# R/cleaning_patterns.R is currently a STAGED extraction: preprocess_data.rmd
# still defines pattern1..pattern21 inline and has not been wired to use it,
# because that file is upstream of the whole pipeline. So the patterns exist in
# two places for now.
#
# The first test below is what makes that safe: it parses the definitions still
# in preprocess_data.rmd and asserts the extracted copy is byte-identical. If
# anyone edits one and not the other, this fails.

# testthat runs with the working directory set to tests/testthat, so resolve the
# notebook relative to that rather than assuming the project root.
inline_notebook_path <- function() {
  testthat::test_path("..", "..", "preprocess_data.rmd")
}

parse_inline_patterns <- function(path = inline_notebook_path()) {
  lines <- readLines(path, warn = FALSE)
  starts <- grep("^```\\{[rR][ ,}]", lines)
  ends <- grep("^```\\s*$", lines)
  code <- character()
  for (s in starts) {
    e <- ends[ends > s][1]
    if (!is.na(e) && e > s + 1) code <- c(code, lines[(s + 1):(e - 1)])
  }

  is_pattern_assignment <- function(expr) {
    is.call(expr) &&
      identical(as.character(expr[[1]]), "<-") &&
      is.name(expr[[2]]) &&
      grepl("^pattern[0-9]+$", as.character(expr[[2]]))
  }

  values <- list()
  env <- new.env()
  for (expr in parse(text = code, keep.source = FALSE)) {
    if (is_pattern_assignment(expr)) {
      values[[as.character(expr[[2]])]] <- eval(expr[[3]], envir = env)
    }
  }
  values[order(as.integer(sub("pattern", "", names(values))))]
}

test_that("the extracted patterns are byte-identical to the inline originals", {
  # Must actually run: it is the guard that keeps the extracted copy and the
  # still-inline originals from silently diverging.
  expect_true(file.exists(inline_notebook_path()))

  inline <- parse_inline_patterns()
  expect_length(inline, 21)
  expect_length(ESSAY_CLEANING_PATTERNS, 21)

  for (i in seq_along(inline)) {
    expect_identical(
      ESSAY_CLEANING_PATTERNS[[i]], inline[[i]],
      info = paste("mismatch at", names(inline)[i], "->", names(ESSAY_CLEANING_PATTERNS)[i])
    )
  }
})

test_that("every pattern has a descriptive name and no name repeats", {
  nms <- names(ESSAY_CLEANING_PATTERNS)
  expect_length(nms, 21)
  expect_true(all(nzchar(nms)))
  expect_false(any(grepl("^pattern[0-9]+$", nms)))
  expect_equal(anyDuplicated(nms), 0)
})

test_that("the documented duplicate pair really is a duplicate", {
  # pattern5 and pattern9 were byte-identical in the original.
  expect_identical(
    ESSAY_CLEANING_PATTERNS$prompt_refer_to_survey_results,
    ESSAY_CLEANING_PATTERNS$prompt_refer_to_survey_results_duplicate
  )
})

test_that("the full prompt block really does contain the narrower fragments", {
  # Documented as the reason order is load-bearing; assert it rather than
  # trusting the comment.
  full <- ESSAY_CLEANING_PATTERNS$prompt_full_block
  contained <- c(
    "prompt_reflect_and_receive_feedback",
    "prompt_refer_to_survey_results",
    "prompt_minimum_350_words",
    "prompt_aim_for_complete_essay"
  )
  for (nm in contained) {
    expect_true(
      grepl(ESSAY_CLEANING_PATTERNS[[nm]], full, fixed = TRUE),
      info = paste(nm, "should be a substring of prompt_full_block")
    )
  }
})

test_that("every pattern compiles under the engine that actually applies it", {
  # These are applied with stringr (ICU), not base grepl (TRE), and that
  # distinction is not cosmetic: `punctuation_except_hyphen` uses ICU character
  # class subtraction, `[\\p{P}\\p{S}--[-]]`, which TRE rejects outright with
  # "Invalid character range". Checking with grepl() would report a false
  # failure; checking with str_detect() reflects real use.
  for (nm in names(ESSAY_CLEANING_PATTERNS)) {
    expect_silent(stringr::str_detect("harmless probe text", ESSAY_CLEANING_PATTERNS[[nm]]))
  }
})

test_that("the ICU-only pattern is genuinely unusable with base regex", {
  # Documents the constraint so it cannot be quietly forgotten. base R does not
  # merely warn here -- it warns and then errors, so this pattern is strictly
  # ICU-only and must be applied through stringr.
  expect_error(
    suppressWarnings(grepl(ESSAY_CLEANING_PATTERNS$punctuation_except_hyphen, "probe")),
    "invalid regular expression"
  )
  # ...and works fine through the engine the pipeline actually uses.
  expect_false(stringr::str_detect("probe", ESSAY_CLEANING_PATTERNS$punctuation_except_hyphen))
  expect_true(stringr::str_detect("probe!", ESSAY_CLEANING_PATTERNS$punctuation_except_hyphen))
})

test_that("cleaning_pattern() looks patterns up by name", {
  expect_identical(
    cleaning_pattern("srl_domain_vocabulary"),
    ESSAY_CLEANING_PATTERNS$srl_domain_vocabulary
  )
})

test_that("an unknown pattern name is refused with the available names listed", {
  expect_error(cleaning_pattern("nope"), "unknown cleaning pattern")
  expect_error(cleaning_pattern("nope"), "prompt_full_block")
})

test_that("applying the patterns in order strips prompt boilerplate", {
  # Behavioural smoke test on synthetic essay text -- no DAACS data.
  essay <- paste(
    "you received information about your learning skills after you took the",
    "self-regulated learning (srl) survey, as well as suggestions for becoming a",
    "more effective and efficient learner.",
    "i think my time management is my weakest area and i plan to improve it."
  )

  cleaned <- essay
  for (nm in c(
    "prompt_full_block", "prompt_received_information_block",
    "prompt_you_received_information", "prompt_after_you_took"
  )) {
    cleaned <- gsub(ESSAY_CLEANING_PATTERNS[[nm]], "", cleaned, fixed = FALSE)
  }

  # The student's own sentence survives; prompt fragments are reduced.
  expect_true(grepl("time management is my weakest area", cleaned))
  expect_lt(nchar(cleaned), nchar(essay))
})

test_that("the first-person filter matches pronouns and not their substrings", {
  p <- ESSAY_CLEANING_PATTERNS$keep_if_first_person_pronoun
  expect_true(grepl(p, "i think this is fine"))
  expect_true(grepl(p, "this is my essay"))
  # Word-boundaried: a word merely CONTAINING a pronoun does not match.
  # ("mine field" would match, correctly -- "mine" is a standalone word there.)
  expect_false(grepl(p, "the field was misleading and italic"))
  expect_false(grepl(p, "ourselves" |> sub(pattern = "ourselves", replacement = "outsourced")))
})
