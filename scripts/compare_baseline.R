# Compare two baselines captured by scripts/capture_baseline.R.
#
#   Rscript scripts/compare_baseline.R before.rds after.rds
#
# Prints only what differs, and only as names and numbers. A refactor that was
# meant to preserve behaviour should produce an empty difference list; anything
# reported is either an intended change or a bug in the refactor.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("usage: Rscript scripts/compare_baseline.R before.rds after.rds", call. = FALSE)
}

before <- readRDS(args[1])
after <- readRDS(args[2])

say <- function(...) cat(..., "\n", sep = "")
differences <- 0L

report <- function(label, same, detail = NULL) {
  if (same) {
    say("  ok        ", label)
  } else {
    differences <<- differences + 1L
    say("  DIFFERS   ", label)
    if (!is.null(detail)) say("              ", detail)
  }
}

say("comparing:")
say("  before: ", args[1], "  (captured ", before$captured_at, ")")
say("  after:  ", args[2], "  (captured ", after$captured_at, ")")
say("")

# --- corpus ----------------------------------------------------------------
say("corpus")
for (field in c("n_documents", "n_vocab", "meta_names", "meta_classes")) {
  report(field, identical(before$corpus[[field]], after$corpus[[field]]))
}

# --- covariates ------------------------------------------------------------
say("")
say("covariate distributions")
for (nm in union(names(before$covariate_counts), names(after$covariate_counts))) {
  report(nm, identical(before$covariate_counts[[nm]], after$covariate_counts[[nm]]))
}

# --- models ----------------------------------------------------------------
say("")
say("models")
model_names <- union(names(before$models), names(after$models))
if (length(model_names) == 0) say("  (none captured)")

for (nm in model_names) {
  b <- before$models[[nm]]
  a <- after$models[[nm]]

  if (is.null(b) || is.null(a)) {
    report(nm, FALSE, if (is.null(b)) "absent in before" else "absent in after")
    next
  }

  for (field in c("k", "exclusivity", "coherence", "top_words", "topic_proportions")) {
    same <- isTRUE(all.equal(b[[field]], a[[field]]))

    comparable_numeric <- is.numeric(b[[field]]) &&
      is.numeric(a[[field]]) &&
      length(b[[field]]) == length(a[[field]])

    detail <- NULL
    if (!same && comparable_numeric) {
      delta <- max(abs(b[[field]] - a[[field]]))
      detail <- paste0("max abs delta = ", format(delta, digits = 4))
    }
    report(paste0(nm, " / ", field), same, detail)
  }
}

# --- effects ---------------------------------------------------------------
say("")
say("covariate effects")
if (is.null(before$effects) && is.null(after$effects)) {
  say("  (none captured)")
} else {
  for (nm in union(names(before$effects), names(after$effects))) {
    report(nm, isTRUE(all.equal(before$effects[[nm]], after$effects[[nm]])))
  }
}

say("")
say(strrep("-", 60))
if (differences == 0L) {
  say("RESULT: no differences. Behaviour preserved.")
} else {
  say("RESULT: ", differences, " difference(s). Each must be an intended change,")
  say("        or it is a bug in the refactor.")
}
