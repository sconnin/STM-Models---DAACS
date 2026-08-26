# Capture aggregate diagnostics as a reference point for refactoring.
#
# Run this BEFORE a refactor and again after. Values that should not have
# changed can then be compared instead of trusted. See scripts/compare_baseline.R.
#
#   Rscript scripts/capture_baseline.R [output.rds]
#
# ---------------------------------------------------------------------------
# IRB SAFETY
#
# This script loads IRB-protected data into R, but is written so that nothing
# it PRINTS or SAVES contains a student record:
#
#   - no essay text, and no character column from `meta`, is captured
#   - `meta` contributes only its dimensions, column names, and column classes
#   - covariates contribute only counts per level and numeric summaries
#   - topic-word tables are vocabulary terms, which are aggregate corpus output
#     and already appear in the published tables
#   - findThoughts()/plotQuote() are never called: those return essay text
#
# The saved .rds is still a derived artifact and is excluded by .gitignore.
# ---------------------------------------------------------------------------

suppressMessages({
  library(stm)
  library(dplyr)
  library(tidytext)
})

out_path <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(out_path)) out_path <- ".scratch/baseline.rds"
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)

say <- function(...) cat(..., "\n", sep = "")

# --- corpus ----------------------------------------------------------------

if (!file.exists("processed_corpus_final.Rdata")) {
  stop("processed_corpus_final.Rdata not found; run from the project root", call. = FALSE)
}
load("processed_corpus_final.Rdata")

baseline <- list()
baseline$captured_at <- as.character(Sys.time())
baseline$r_version <- as.character(getRversion())

baseline$corpus <- list(
  n_documents = length(documents),
  n_vocab = length(vocab),
  meta_dim = dim(meta),
  meta_names = names(meta),
  meta_classes = vapply(meta, function(x) class(x)[1], character(1))
)

say("corpus: ", baseline$corpus$n_documents, " documents, ",
    baseline$corpus$n_vocab, " vocabulary terms")

# Covariate distributions: counts and numeric summaries only, never raw values.
covariate_names <- c("institution", "gender", "race", "first_gen", "on_time_term1")
covariates <- intersect(covariate_names, names(meta))
baseline$covariate_counts <- lapply(covariates, function(v) as.data.frame(table(meta[[v]])))
names(baseline$covariate_counts) <- covariates
if ("age" %in% names(meta)) baseline$age_summary <- summary(meta$age)

say("covariates summarised: ", paste(covariates, collapse = ", "))

# --- models ----------------------------------------------------------------

model_files <- c(
  prevalence = "stm.prevalence.models.6_32.Rda",
  prevalence_content = "stm.prevalence.content.models.6_32.Rda",
  optimized_prevalence = "optimized.prevalence.models.6_32.Rda",
  optimized_prev_content = "optimized.prevalence.content.models.6_32.Rda",
  content = "stm.content.models.6_32.Rda"
)

present <- model_files[file.exists(model_files)]
missing <- setdiff(names(model_files), names(present))
for (f in present) load(f)

say("model files loaded: ", length(present), " of ", length(model_files))
if (length(missing)) say("  not present: ", paste(missing, collapse = ", "))
baseline$model_files_present <- names(present)

#' Aggregate diagnostics for one fitted model.
model_diagnostics <- function(model_name) {
  if (!exists(model_name)) return(NULL)
  model <- get(model_name)
  k <- model$settings$dim$K

  d <- list(k = k, theta_summary = summary(as.numeric(model$theta)))

  # Exclusivity and coherence are undefined for content-formula models.
  d$exclusivity <- tryCatch(exclusivity(model), error = function(e) NULL)
  # `documents` is introduced by load("processed_corpus_final.Rdata") above, so
  # lintr cannot see where it is bound.
  d$coherence <- tryCatch(
    semanticCoherence(model, documents), # nolint: object_usage_linter.
    error = function(e) NULL
  )

  # Vocabulary terms per topic -- aggregate corpus output, not student text.
  d$top_words <- tryCatch(
    {
      lab <- labelTopics(model, 1:k, n = 10)
      metric <- if (!is.null(lab$prob)) lab$prob else lab$topics
      apply(metric, 1, paste, collapse = ", ")
    },
    error = function(e) NULL
  )

  # Mean topic proportion across documents.
  d$topic_proportions <- colMeans(model$theta)
  d
}

wanted <- c(
  paste0("stm.p.", c(6, 12, 18, 24, 32)),
  paste0("stm.pc.", c(6, 12, 18, 24, 32)),
  paste0("stm.model.", c(6, 12, 18, 24, 32)),
  paste0("stm.c.", c(6, 12, 18, 24, 32))
)

baseline$models <- list()
for (nm in wanted) {
  d <- model_diagnostics(nm)
  if (!is.null(d)) {
    baseline$models[[nm]] <- d
    say("  ", nm, ": K=", d$k,
        ", mean theta=", format(mean(d$topic_proportions), digits = 6))
  }
}
say("models summarised: ", length(baseline$models))

# --- covariate effects -----------------------------------------------------

if (exists("stm.p.12")) {
  say("estimating covariate effects on stm.p.12 ...")
  effects <- list()
  formulas <- list(
    gender = 1:12 ~ gender,
    race = 1:12 ~ race,
    first_gen = 1:12 ~ first_gen,
    age = 1:12 ~ s(age)
  )
  for (nm in names(formulas)) {
    effects[[nm]] <- tryCatch(
      {
        fit <- estimateEffect(formulas[[nm]], stmobj = stm.p.12,
                              metadata = meta, uncertainty = "Global")
        as.data.frame(tidy(fit))
      },
      error = function(e) paste("ERROR:", conditionMessage(e))
    )
  }
  baseline$effects <- effects
  say("  effects captured: ", paste(names(effects), collapse = ", "))
}

# --- save ------------------------------------------------------------------

saveRDS(baseline, out_path)
say("")
say("baseline written to ", out_path)
say("sections: ", paste(names(baseline), collapse = ", "))
say("")
say("This file contains aggregates only -- no essay text, no student records.")
say("It is still derived data and is excluded by .gitignore.")
