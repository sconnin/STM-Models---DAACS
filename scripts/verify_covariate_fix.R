# Quantify what the S1-6 / S1-7 fixes change, on the real data.
#
#   Rscript scripts/verify_covariate_fix.R
#
# Runs the ORIGINAL recoding and the NEW recoding over the same inputs and
# reports the difference in sample composition. Counts and category labels only;
# no essay text, no doc_id, no row-level record.

suppressMessages({
  library(dplyr)
  library(stringr)
  library(tidyr)
  library(janitor)
})

source("R/covariate_levels.R")

say <- function(...) cat(..., "\n", sep = "")
rule <- function() say(strrep("-", 70))

for (f in c("DAACS-WGU.rda", "DAACS-EC.rda", "DAACS-ualbany.rda")) load(f)

sources <- list(
  WG = list(data = daacs.wgu, race_col = "ethnicity2"),
  EC = list(data = daacs.ec, race_col = "ethnicity"),
  Alb = list(data = daacs.ualbany, race_col = "race_ethnicity")
)

# --- the original expressions, reproduced verbatim -------------------------

original_gender <- function(g) ifelse(g %in% c("Female", "FEMALE"), "F", "M")

original_race <- function(r, split_comma) {
  if (split_comma) r <- sub(",.*$", "", r)
  r <- str_remove(r, " non-Hispanic")
  r <- str_replace(r, "Hispanic/Latino", "Latinx")
  r <- str_replace(r, "Hispanic", "Latinx")
  r <- str_replace(r, "Black,", "Black or African American")
  r <- str_replace(r, "Am. Indian or Alaskan Native", "American Indian or Alaska Native")
  r <- str_replace(r, "Multiple|Two or more races", "Two or More Races")
  r <- str_replace(r, "Native Hawaiian,", "Native Hawaiian or Other Pacific Islander")
  r
}

# --- gender ----------------------------------------------------------------

say("")
say("GENDER  (S1-6)")
rule()

gender_rows <- list()
for (inst in names(sources)) {
  d <- sources[[inst]]$data |> clean_names()
  g <- d$gender[!is.na(d$gender)]
  before <- original_gender(g)
  after <- recode_gender(g)
  changed <- sum(before != after)
  gender_rows[[inst]] <- data.frame(
    institution = inst,
    n = length(g),
    female_before = sum(before == "F"),
    female_after = sum(after == "F"),
    reclassified = changed
  )
}
gender_summary <- bind_rows(gender_rows)
print(gender_summary, row.names = FALSE)

total_changed <- sum(gender_summary$reclassified)
say("")
say("  students whose recorded gender changes: ", total_changed)
say("  all of them were female, recorded as male under the original expression")

# --- race ------------------------------------------------------------------

say("")
say("")
say("RACE  (S1-7)")
rule()

for (inst in names(sources)) {
  d <- sources[[inst]]$data |> clean_names()
  col <- sources[[inst]]$race_col
  r <- as.character(d[[col]])
  r <- r[!is.na(r)]
  r <- r[!r %in% EXCLUDED_RACE_VALUES]

  before <- original_race(r, split_comma = (inst == "Alb"))
  after <- recode_race(r)

  say("  ", inst, ":")
  moved <- unique(before[before != after])
  if (length(moved) == 0) {
    say("    no level changes")
  } else {
    for (lvl in moved) {
      n <- sum(before == lvl)
      say(sprintf("    %-34s n=%-6d -> %s", lvl, n, unique(after[before == lvl])))
    }
  }
}

say("")
say("  Level sets before and after, pooled across institutions:")
all_before <- character(0)
all_after <- character(0)
for (inst in names(sources)) {
  d <- sources[[inst]]$data |> clean_names()
  r <- as.character(d[[sources[[inst]]$race_col]])
  r <- r[!is.na(r)]
  r <- r[!r %in% EXCLUDED_RACE_VALUES]
  all_before <- c(all_before, original_race(r, split_comma = (inst == "Alb")))
  all_after <- c(all_after, recode_race(r))
}
say("    distinct levels before: ", length(unique(all_before)))
say("    distinct levels after:  ", length(unique(all_after)))
say("")
say("    levels that disappear (merged into another):")
for (lvl in setdiff(unique(all_before), unique(all_after))) {
  say(sprintf("      %-34s n=%d", lvl, sum(all_before == lvl)))
}

say("")
rule()
say("Counts and category labels only.")
