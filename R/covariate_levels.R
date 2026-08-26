#' Canonical gender and race encodings, harmonised across institutions.
#'
#' The three DAACS sources encode these differently, and the original recoding
#' handled the differences with chained `str_replace()` calls plus an `ifelse()`
#' whose else-branch was unconditional. Both silently mishandled values they did
#' not anticipate. See CODE_REVIEW.md S1-6 and S1-7.
#'
#' The functions here fail loudly on an unrecognised value instead of quietly
#' assigning one. That is the point: a new encoding appearing in a future data
#' drop should stop the pipeline, not slip into the models mislabelled.

# --- gender ---------------------------------------------------------------

#' Every gender encoding observed across the three institutions.
#'
#' WGU writes "Female"/"Male", Excelsior "FEMALE"/"MALE", Albany "F"/"M". The
#' original `ifelse(gender %in% c("Female", "FEMALE"), "F", "M")` matched the
#' first two and sent everything else to "M" -- which relabelled all 2,088
#' Albany women as men.
GENDER_LOOKUP <- c(
  "Female" = "F", "FEMALE" = "F", "F" = "F",
  "Male"   = "M", "MALE"   = "M", "M" = "M"
)

#' Recode gender to F/M, failing on anything unrecognised.
#'
#' @param x Character vector of raw gender values.
#' @return Character vector of "F"/"M".
recode_gender <- function(x) {
  x <- as.character(x)
  out <- unname(GENDER_LOOKUP[x])

  unmapped <- unique(x[is.na(out) & !is.na(x)])
  if (length(unmapped) > 0) {
    stop(
      "unrecognised gender value(s): ", paste(shQuote(unmapped), collapse = ", "),
      ". Add them to GENDER_LOOKUP rather than letting them default -- an ",
      "unhandled encoding is how every Albany woman came to be recoded as male.",
      call. = FALSE
    )
  }
  out
}

# --- race -----------------------------------------------------------------

#' Race values excluded from modelling, as in the original.
EXCLUDED_RACE_VALUES <- c("Unknown", "Unknown/Other", "Non-Resident Alien")

#' The canonical race levels, after harmonisation.
RACE_LEVELS <- c(
  "American Indian or Alaska Native",
  "Asian",
  "Black or African American",
  "Latinx",
  "Native Hawaiian or Other Pacific Islander",
  "Two or More Races",
  "White"
)

#' Every race encoding observed across the three institutions, mapped to a
#' canonical level.
#'
#' Two entries are the substantive fix. WGU writes "Black" where the others
#' write "Black or African American", and "Native Hawaiian" where Excelsior
#' writes "Native Hawaiian or Other Pacific Islander". The original chain
#' attempted this with `str_replace(race, "Black,", ...)`, which requires a
#' trailing comma that no institution's value actually has -- WGU has none,
#' Excelsior is already expanded, and Albany's is stripped upstream. The line
#' never fired, so each group stayed split across two levels by institution.
RACE_LOOKUP <- c(
  "Am. Indian or Alaskan Native"              = "American Indian or Alaska Native",
  "American Indian or Alaska Native"          = "American Indian or Alaska Native",
  "Asian"                                     = "Asian",
  "Black"                                     = "Black or African American",
  "Black or African American"                 = "Black or African American",
  "Hispanic"                                  = "Latinx",
  "Hispanic/Latino"                           = "Latinx",
  "Latinx"                                    = "Latinx",
  "Native Hawaiian"                           = "Native Hawaiian or Other Pacific Islander",
  "Native Hawaiian or Other Pacific Islander" = "Native Hawaiian or Other Pacific Islander",
  "Multiple"                                  = "Two or More Races",
  "Two or more races"                         = "Two or More Races",
  "Two or More Races"                         = "Two or More Races",
  "White"                                     = "White"
)

#' Recode race to a canonical level, failing on anything unrecognised.
#'
#' Strips any ", non-Hispanic"-style qualifier first, so the function behaves
#' the same whether or not Albany's values have already been split on the comma
#' upstream.
#'
#' @param x Character vector of raw race values.
#' @return Character vector drawn from `RACE_LEVELS`.
recode_race <- function(x) {
  x <- as.character(x)
  # Albany qualifies values as e.g. "Asian, non-Hispanic". Drop the qualifier.
  base_value <- sub(",.*$", "", x)

  out <- unname(RACE_LOOKUP[base_value])

  unmapped <- unique(base_value[is.na(out) & !is.na(base_value)])
  if (length(unmapped) > 0) {
    stop(
      "unrecognised race value(s): ", paste(shQuote(unmapped), collapse = ", "),
      ". Add them to RACE_LOOKUP, or to EXCLUDED_RACE_VALUES if they should be ",
      "filtered before this point.",
      call. = FALSE
    )
  }

  stopifnot(all(out %in% RACE_LEVELS))
  out
}
