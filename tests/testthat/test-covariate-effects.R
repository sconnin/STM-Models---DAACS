# Tests for R/covariate_effects.R
#
# The helpers in R/ are sourced into the global environment rather than loaded
# from a package namespace, so an unqualified call to plot() resolves through
# the search path. local_mocked_bindings() patches namespaces and cannot
# intercept that; stubbing the name in the global environment can.
local_stub_global <- function(name, value, env = parent.frame()) {
  existed <- exists(name, envir = globalenv(), inherits = FALSE)
  old <- if (existed) get(name, envir = globalenv()) else NULL
  assign(name, value, envir = globalenv())
  withr::defer(
    {
      if (existed) {
        assign(name, old, envir = globalenv())
      } else {
        rm(list = name, envir = globalenv())
      }
    },
    envir = env
  )
}

# `estimateEffect` objects cannot be built by hand -- tidy.estimateEffect calls
# summary() on a fitted model -- so the package boundaries are mocked and what is
# tested here is this file's own logic: which formulas are estimated, which terms
# survive the significance filter, and which arguments the plots pass through.

test_that("one fit is returned per named formula, in that order", {
  called <- list()
  local_mocked_bindings(
    estimateEffect = function(formula, stmobj, metadata, uncertainty) {
      called[[length(called) + 1]] <<- list(formula = formula, uncertainty = uncertainty)
      structure(list(formula = formula), class = "estimateEffect")
    },
    .package = "stm"
  )

  fits <- estimate_effects(
    model = "model",
    metadata = data.frame(gender = "F"),
    formulas = list(gender = 1:12 ~ gender, race = 1:12 ~ race)
  )

  expect_equal(names(fits), c("gender", "race"))
  expect_length(called, 2)
  expect_equal(deparse1(called[[1]]$formula), "1:12 ~ gender")
  expect_equal(deparse1(called[[2]]$formula), "1:12 ~ race")
})

test_that("uncertainty defaults to Global and is passed through", {
  # "Global" propagates topic-proportion uncertainty into the standard errors.
  # Silently dropping to the default would narrow every interval reported.
  seen <- NULL
  local_mocked_bindings(
    estimateEffect = function(formula, stmobj, metadata, uncertainty) {
      seen <<- uncertainty
      NULL
    },
    .package = "stm"
  )

  estimate_effects("model", data.frame(x = 1), list(a = 1:2 ~ x))
  expect_equal(seen, "Global")

  estimate_effects("model", data.frame(x = 1), list(a = 1:2 ~ x), uncertainty = "None")
  expect_equal(seen, "None")
})

test_that("an unnamed or empty formula list is refused", {
  expect_error(estimate_effects("m", data.frame(x = 1), list()))
  expect_error(estimate_effects("m", data.frame(x = 1), list(1:2 ~ x)))
})

test_that("the intercept is dropped and the threshold is applied", {
  local_mocked_bindings(
    tidy = function(x, ...) {
      tibble::tibble(
        topic = c(1L, 1L, 2L, 2L),
        term = c("(Intercept)", "genderM", "genderM", "genderM"),
        p.value = c(0.0001, 0.01, 0.049, 0.2)
      )
    },
    .package = "tidytext"
  )

  result <- significant_effects("fit")

  expect_equal(nrow(result), 2)
  expect_false("(Intercept)" %in% result$term)
  expect_true(all(result$p.value < 0.05))
})

test_that("a looser threshold admits the terms it should", {
  # The gender-by-age interaction is reported at 0.10, not 0.05.
  local_mocked_bindings(
    tidy = function(x, ...) {
      tibble::tibble(
        topic = c(1L, 2L),
        term = c("genderM:age", "genderM:age"),
        p.value = c(0.08, 0.2)
      )
    },
    .package = "tidytext"
  )

  expect_equal(nrow(significant_effects("fit", alpha = 0.10)), 1)
  expect_equal(nrow(significant_effects("fit", alpha = 0.05)), 0)
})

test_that("the threshold must be a single probability", {
  expect_error(significant_effects("fit", alpha = 0))
  expect_error(significant_effects("fit", alpha = 1))
  expect_error(significant_effects("fit", alpha = c(0.05, 0.1)))
})

test_that("difference plots pass the shared arguments every copy repeated", {
  args <- NULL
  local_stub_global("plot", function(x, ...) {
    args <<- list(...)
    invisible(NULL)
  })

  plot_difference_effect(
    effect = "fit",
    covariate = "race",
    value1 = "Black or African American",
    value2 = "White",
    xlab = "More White ... More Black or African American",
    main = "Effect of Race: K=12",
    xlim = c(-.05, .05),
    model = "stm.p.12"
  )

  expect_equal(args$method, "difference")
  expect_equal(args$cov.value1, "Black or African American")
  expect_equal(args$cov.value2, "White")
  expect_equal(args$topics, 1:12)
  expect_equal(args$labeltype, "custom")
  expect_equal(args$custom.labels, topic_labels())
  # `cex`, lower-case. One copy carried `Text.cex`, which is not a graphical
  # parameter, so it was ignored and warned six times per plot (S2-9).
  expect_equal(args$cex, .25)
  expect_false("Text.cex" %in% names(args))
})

test_that("continuous effects draw one figure per topic, titled with the topic", {
  titles <- character()
  local_stub_global("plot", function(x, ...) {
    dots <- list(...)
    titles <<- c(titles, as.character(dots$main))
    invisible(NULL)
  })

  plot_continuous_effect("fit", "age", topics = c(3, 7), model = "stm.p.12")

  expect_length(titles, 2)
  expect_match(titles[1], "Topic 3$")
  expect_match(titles[2], "Topic 7$")
})

test_that("the interaction plot draws both genders and one legend", {
  calls <- list()
  legends <- list()
  local_stub_global("plot", function(x, ...) {
    calls[[length(calls) + 1]] <<- list(...)
    invisible(NULL)
  })
  local_stub_global("legend", function(x, y, legend, ...) {
    legends[[length(legends) + 1]] <<- list(x = x, y = y, legend = legend)
    invisible(NULL)
  })

  plot_gender_age_interaction("fit", "model", topic = 4, ylim = c(.04, .18))

  expect_length(calls, 2)
  expect_equal(calls[[1]]$moderator.value, "M")
  expect_equal(calls[[2]]$moderator.value, "F")
  # Only the second call overlays; the first establishes the axes.
  expect_null(calls[[1]]$add)
  expect_true(calls[[2]]$add)
  expect_equal(calls[[1]]$ylim, c(.04, .18))

  expect_length(legends, 1)
  expect_equal(legends[[1]]$legend, c("Male", "Female"))
  # The legend sits at the top of whatever y range the topic needed.
  expect_equal(legends[[1]]$y, .18)
})

test_that("the interaction title carries the topic's label", {
  titles <- character()
  local_stub_global("plot", function(x, ...) {
    dots <- list(...)
    if (!is.null(dots$main)) titles <<- c(titles, dots$main)
    invisible(NULL)
  })
  local_stub_global("legend", function(...) invisible(NULL))

  plot_gender_age_interaction("fit", "model", topic = 2, ylim = c(0, .1))

  expect_equal(titles, paste0("Topic 2: ", topic_labels(topics = 2), " (P < 0.10)"))
})

test_that("ylim must be a pair of numbers", {
  expect_error(plot_gender_age_interaction("fit", "model", 2, ylim = 0.1))
  expect_error(plot_gender_age_interaction("fit", "model", 2, ylim = c("0", "1")))
})
