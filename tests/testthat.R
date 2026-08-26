# Test runner.
#
# This project is a set of analysis notebooks rather than a package, so the
# helpers in R/ are sourced directly instead of loaded via library().
# Run with: Rscript tests/testthat.R

library(testthat)
library(randomForest)
library(ggplot2)

for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) {
  source(f)
}

test_dir("tests/testthat", stop_on_failure = TRUE)
