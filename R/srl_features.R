#' Self-regulated-learning (SRL) survey features, harmonised across institutions.
#'
#' Replaces three copies of the same fourteen-column `select()` chain in
#' stm.rforestmodels.final.Rmd -- one per institution -- that differed only in
#' the institution code and, for Albany, in one extra `mutate()`.
#'
#' The copies are why S1-1 was possible: Albany's branch carried
#' `case_when(srl_grit %in% NaN ~ NA)`, which has no fallback branch and uses
#' `%in% NaN`, a comparison that never matches because NaN does not compare equal
#' to itself. It destroyed nothing only because Albany's grit column was already
#' empty -- 3,941 rows, 0 non-NA -- and it would have emptied the column the
#' moment the measure started arriving. Stating a missing measure as missing,
#' once, is both correct and legible.

# The SRL scales, in the order the source datasets carry them.
SRL_MEASURES <- c(
  "srl_grit", "srl_strategies", "srl_motivation", "srl_metacognition",
  "srl_managing_time", "srl_managing_environment", "srl_anxiety", "srl_mindset",
  "srl_self_efficacy", "srl_evaluation", "srl_planning", "srl_help_seeking",
  "srl_understanding", "srl_mastery_orientation"
)

#' Subset one institution's SRL features.
#'
#' @param data One institution's raw DAACS data frame.
#' @param institution Institution code to stamp on every row: `"WG"`, `"EC"` or
#'   `"Alb"`.
#' @param unavailable Measures this institution does not collect. They are set
#'   to `NA_real_` explicitly rather than left to arrive as `NaN` or be dropped
#'   silently. Albany collects no grit measure.
#' @param require Measure that must be present for the row to be usable;
#'   rows missing it are dropped, as they were before extraction.
#' @return A tibble of `doc_id`, `institution`, and the fourteen SRL measures.
srl_subset <- function(data,
                       institution,
                       unavailable = character(),
                       require = "srl_strategies") {
  stopifnot(is.data.frame(data), is.character(institution), length(institution) == 1)

  unknown <- setdiff(unavailable, SRL_MEASURES)
  if (length(unknown) > 0) {
    stop(
      "unavailable names measures that are not SRL scales: ",
      paste(unknown, collapse = ", "),
      call. = FALSE
    )
  }
  if (require %in% unavailable) {
    stop(
      "`require` names a measure listed as unavailable (", require,
      "), which would drop every row of ", institution,
      call. = FALSE
    )
  }

  missing_cols <- setdiff(c("DAACS_ID", SRL_MEASURES), names(data))
  if (length(missing_cols) > 0) {
    stop(
      institution, " data is missing expected columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  subset <- data |>
    dplyr::select(dplyr::all_of(c("DAACS_ID", SRL_MEASURES))) |>
    dplyr::rename(doc_id = "DAACS_ID")

  for (measure in unavailable) {
    subset[[measure]] <- NA_real_
  }

  subset |>
    dplyr::mutate(institution = institution) |>
    dplyr::relocate("institution", .after = "doc_id") |>
    dplyr::filter(!is.na(.data[[require]])) # nolint: object_usage_linter.
}
