#' Model formulas shared across the STM specifications.
#'
#' The prevalence formula was written out fifteen times in stm_models_final.rmd
#' before the K = 12 narrowing, and four times after it. Fifteen or four, a
#' revision to the covariate set had to be applied to every copy, and applying it
#' to all but one would produce models that differ in specification while
#' appearing to differ only in family.
#'
#' Held as formula objects rather than strings so the model functions receive
#' exactly what they received before.

# Prevalence: the demographic covariates plus a spline on age, with the
# gender-by-age interaction that the analyses notebook estimates separately.
PREVALENCE_FORMULA <- ~ gender + race + first_gen + s(age) + gender * s(age)

# Content: vocabulary is allowed to vary by gender. Used by the prevalence +
# content and content-only families.
CONTENT_FORMULA <- ~gender
