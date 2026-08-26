# Answer the CODE_REVIEW.md findings marked "needs runtime confirmation".
#
#   Rscript scripts/diagnose_s1.R
#
# ---------------------------------------------------------------------------
# IRB SAFETY
#
# Loads the raw DAACS files, but reports only:
#   - counts of rows per category
#   - distinct category LABELS (e.g. "Female", "Two or More Races")
#   - NA / NaN counts
#
# No essay text, no doc_id, no row-level record is read or printed. The race
# recoding check is applied to the DISTINCT VALUES rather than to the data, so
# it shows the mapping without touching rows.
# ---------------------------------------------------------------------------

suppressMessages({
  library(dplyr)
  library(stringr)
  library(tidyr)
  library(janitor)
})

say <- function(...) cat(..., "\n", sep = "")
rule <- function() say(strrep("-", 72))

for (f in c("DAACS-WGU.rda", "DAACS-EC.rda", "DAACS-ualbany.rda")) {
  if (!file.exists(f)) stop("missing ", f, "; run from the project root", call. = FALSE)
  load(f)
}

sources <- list(WG = daacs.wgu, EC = daacs.ec, Alb = daacs.ualbany)

# ===========================================================================
say("")
say("S1-1  Is srl_grit entirely NA for Albany?")
rule()
say("  Finding under review: mutate(srl_grit = case_when(srl_grit %in% NaN ~ NA))")
say("  has no fallback branch, so every row should fall through to NA.")
say("")

for (inst in names(sources)) {
  d <- sources[[inst]]
  if (!"srl_grit" %in% names(d)) {
    say("  ", inst, ": no srl_grit column")
    next
  }
  raw <- d$srl_grit
  say(sprintf(
    "  %-4s rows=%-7d non-NA=%-7d NaN=%-6d  (before any recoding)",
    inst, length(raw), sum(!is.na(raw)), sum(is.nan(raw))
  ))
}

say("")
say("  After applying the line as written, to Albany only:")
alb_after <- daacs.ualbany %>%
  mutate(srl_grit_after = case_when(srl_grit %in% NaN ~ NA))
say(sprintf(
  "    non-NA before = %d   non-NA after = %d",
  sum(!is.na(daacs.ualbany$srl_grit)), sum(!is.na(alb_after$srl_grit_after))
))

# ===========================================================================
say("")
say("")
say("S1-6  Does any gender value exist that is neither Female nor Male?")
rule()
say("  Finding under review: ifelse(gender %in% c('Female','FEMALE'), 'F', 'M')")
say("  sends every other value, including unexpected categories, to 'M'.")
say("")

for (inst in names(sources)) {
  d <- sources[[inst]] %>% clean_names()
  if (!"gender" %in% names(d)) {
    say("  ", inst, ": no gender column")
    next
  }
  counts <- d %>% count(gender, sort = TRUE)
  say("  ", inst, ":")
  for (i in seq_len(nrow(counts))) {
    label <- counts$gender[i]
    shown <- if (is.na(label)) "<NA>" else as.character(label)
    would_become <- if (!is.na(label) && label %in% c("Female", "FEMALE")) "F" else "M"
    say(sprintf("    %-28s n=%-7d -> recoded as '%s'", shown, counts$n[i], would_become))
  }
}

# ===========================================================================
say("")
say("")
say("S1-7  Are race categories consistent across institutions after recoding?")
rule()
say("  Finding under review: str_replace(race, 'Black,', ...) needs a trailing")
say("  comma that Albany's upstream separate() has already stripped.")
say("")

race_columns <- c(WG = "ethnicity2", EC = "ethnicity", Alb = "race_ethnicity")

# Reproduce the recoding chain from preprocess_data.rmd, applied to DISTINCT
# VALUES rather than to rows.
recode_race <- function(values, split_on_comma) {
  x <- values
  if (split_on_comma) x <- sub(",.*$", "", x) # separate(extra='drop')
  x <- str_remove(x, " non-Hispanic")
  x <- str_replace(x, "Hispanic/Latino", "Latinx")
  x <- str_replace(x, "Hispanic", "Latinx")
  x <- str_replace(x, "Black,", "Black or African American")
  x <- str_replace(x, "Am. Indian or Alaskan Native", "American Indian or Alaska Native")
  x <- str_replace(x, "Multiple|Two or more races", "Two or More Races")
  x <- str_replace(x, "Native Hawaiian,", "Native Hawaiian or Other Pacific Islander")
  x
}

final_levels <- list()
for (inst in names(race_columns)) {
  d <- sources[[inst]] %>% clean_names()
  col <- race_columns[[inst]]
  if (!col %in% names(d)) {
    say("  ", inst, ": no column '", col, "'")
    next
  }
  distinct_values <- sort(unique(as.character(d[[col]])))
  distinct_values <- distinct_values[!is.na(distinct_values)]
  recoded <- recode_race(distinct_values, split_on_comma = (inst == "Alb"))

  say("  ", inst, "  (column: ", col, ")")
  for (i in seq_along(distinct_values)) {
    marker <- if (distinct_values[i] != recoded[i]) "->" else "  "
    say(sprintf("    %-42s %s %s", distinct_values[i], marker, recoded[i]))
  }
  say("")
  final_levels[[inst]] <- sort(unique(recoded))
}

say("  Resulting level sets, by institution:")
all_levels <- sort(unique(unlist(final_levels)))
for (lvl in all_levels) {
  present <- vapply(final_levels, function(x) lvl %in% x, logical(1))
  say(sprintf("    %-44s %s", lvl, paste(names(present)[present], collapse = ", ")))
}

say("")
say("  Does the level 'Black' exist (used as cov.value1 in three plots)?")
say("    ", if ("Black" %in% all_levels) "YES" else "NO - that contrast matches nothing")
say("  Does 'Black or African American' exist?")
say("    ", if ("Black or African American" %in% all_levels) "YES" else "NO")

# ===========================================================================
say("")
say("")
say("S1-8  Does the QA check do what its comment claims?")
rule()
say("  Finding under review: sum(n_distinct(clean_data$text) < 50) always")
say("  returns 0, because n_distinct() returns a single scalar.")
say("")
demo <- data.frame(text = c("a", "b", "c"))
say("  On a 3-row frame where every essay is 1 character:")
say("    n_distinct(text)            = ", n_distinct(demo$text))
say("    sum(n_distinct(text) < 50)  = ", sum(n_distinct(demo$text) < 50))
say("  A real check would count short essays individually:")
say("    sum(nchar(text) < 50)       = ", sum(nchar(demo$text) < 50))

say("")
rule()
say("Counts and category labels only. No essay text or row-level record read.")
