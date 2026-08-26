# Tests for R/covariate_levels.R
#
# These cover the two most consequential fixes in the review: the gender
# recoding that relabelled every Albany woman as male (S1-6), and the race
# recoding that split two groups across two levels by institution (S1-7).
#
# The encodings asserted below are the ones actually observed in the DAACS
# sources, taken from scripts/diagnose_s1.R output. No data is read here.

# --- gender ---------------------------------------------------------------

test_that("every observed gender encoding maps correctly", {
  expect_equal(recode_gender(c("Female", "FEMALE", "F")), c("F", "F", "F"))
  expect_equal(recode_gender(c("Male", "MALE", "M")), c("M", "M", "M"))
})

test_that("Albany's single-letter F is female, not male", {
  # The original bug: "F" is not in c("Female", "FEMALE"), so the unconditional
  # else branch sent all 2,088 Albany women to "M".
  expect_equal(recode_gender("F"), "F")
  expect_false(identical(recode_gender("F"), "M"))
})

test_that("the original expression really did produce the wrong answer", {
  # Pins the defect so the regression is unmistakable if anyone reinstates it.
  original <- function(g) ifelse(g %in% c("Female", "FEMALE"), "F", "M")
  expect_equal(original("F"), "M") # wrong
  expect_equal(recode_gender("F"), "F") # right
})

test_that("an unrecognised gender value is an error, not a silent default", {
  expect_error(recode_gender("Non-binary"), "unrecognised gender value")
  expect_error(recode_gender("Prefer not to say"), "unrecognised gender value")
  expect_error(recode_gender(""), "unrecognised gender value")
})

test_that("the error names the offending values", {
  expect_error(recode_gender(c("Female", "Woman")), "'Woman'")
})

test_that("NA passes through rather than becoming a category", {
  expect_true(is.na(recode_gender(NA_character_)))
})

# --- race -----------------------------------------------------------------

test_that("WGU's Black merges with the other institutions' label", {
  # The substantive S1-7 fix: WGU wrote "Black", the others
  # "Black or African American", so one group occupied two levels.
  expect_equal(recode_race("Black"), "Black or African American")
  expect_equal(recode_race("Black or African American"), "Black or African American")
})

test_that("Native Hawaiian merges the same way", {
  expect_equal(
    recode_race("Native Hawaiian"),
    "Native Hawaiian or Other Pacific Islander"
  )
  expect_equal(
    recode_race("Native Hawaiian or Other Pacific Islander"),
    "Native Hawaiian or Other Pacific Islander"
  )
})

test_that("every encoding observed in the three sources maps to a canonical level", {
  wgu <- c("Am. Indian or Alaskan Native", "Asian", "Black", "Hispanic",
           "Multiple", "Native Hawaiian", "White")
  ec <- c("American Indian or Alaska Native", "Asian", "Black or African American",
          "Hispanic", "Native Hawaiian or Other Pacific Islander",
          "Two or more races", "White")
  alb <- c("Asian, non-Hispanic", "Black or African American, non-Hispanic",
           "Hispanic/Latino", "Two or more races, non-Hispanic", "White, non-Hispanic")

  for (v in c(wgu, ec, alb)) {
    expect_true(recode_race(v) %in% RACE_LEVELS, info = v)
  }
})

test_that("the three institutions agree on levels after recoding", {
  # This is the whole point of the fix: the same student should land on the same
  # level regardless of which institution recorded them.
  expect_equal(recode_race("Black"), recode_race("Black or African American"))
  expect_equal(
    recode_race("Black or African American, non-Hispanic"),
    recode_race("Black")
  )
  expect_equal(recode_race("Hispanic"), recode_race("Hispanic/Latino"))
  expect_equal(recode_race("Multiple"), recode_race("Two or more races"))
  expect_equal(recode_race("White, non-Hispanic"), recode_race("White"))
})

test_that("Albany's non-Hispanic qualifier is stripped", {
  expect_equal(recode_race("Asian, non-Hispanic"), "Asian")
  expect_equal(recode_race("White, non-Hispanic"), "White")
})

test_that("the old str_replace never fired, which is why the split persisted", {
  # Pins the reason the original fix was ineffective: it required a trailing
  # comma that no institution's value carries at that point in the chain.
  expect_equal(stringr::str_replace("Black", "Black,", "Black or African American"), "Black")
  expect_equal(
    stringr::str_replace("Black or African American", "Black,", "X"),
    "Black or African American"
  )
})

test_that("an unrecognised race value is an error", {
  expect_error(recode_race("Martian"), "unrecognised race value")
  expect_error(recode_race("Martian"), "EXCLUDED_RACE_VALUES")
})

test_that("excluded values are not silently recoded", {
  # They must be filtered upstream; reaching recode_race() is a mistake.
  for (v in EXCLUDED_RACE_VALUES) {
    expect_error(recode_race(v), "unrecognised race value")
  }
})

test_that("race_base_value strips an institution's trailing qualifier", {
  expect_equal(race_base_value("Asian, non-Hispanic"), "Asian")
  expect_equal(race_base_value("Asian"), "Asian")
  expect_equal(race_base_value("Two or more races, non-Hispanic"), "Two or more races")
  expect_equal(race_base_value(c("White, non-Hispanic", "Black")), c("White", "Black"))
})

test_that("a qualified excluded value is caught by the exclusion filter", {
  # The regression this guards: filtering the RAW value lets Albany's
  # "Unknown, non-Hispanic" through, because it matches no EXCLUDED_RACE_VALUES
  # entry -- and it then halts recode_race(). The original code avoided this by
  # splitting on the comma before filtering.
  qualified <- paste0(EXCLUDED_RACE_VALUES, ", non-Hispanic")

  expect_false(any(qualified %in% EXCLUDED_RACE_VALUES))
  expect_true(all(race_base_value(qualified) %in% EXCLUDED_RACE_VALUES))
})

test_that("RACE_LEVELS has no duplicates and covers the lookup targets", {
  expect_equal(anyDuplicated(RACE_LEVELS), 0)
  expect_true(all(unname(RACE_LOOKUP) %in% RACE_LEVELS))
})

test_that("recoding is idempotent", {
  # Running it twice must not change the answer.
  for (lvl in RACE_LEVELS) {
    expect_equal(recode_race(lvl), lvl, info = lvl)
  }
})
