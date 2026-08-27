# STM-Models---DAACS
Structural Topic Model files for DAACS student essays

This repository contains the results of a structural topic model analysis of student essays collected as part of the DAACS (https://daacs.net/) project for college student assessment and support. Institutions represented in this dataset currently include: Western Governors University, Excelsior College, and the University of Albany. 

## Data availability

**No DAACS data is included in this repository, and none may be committed to it.**

The dataset is IRB-protected human-subjects data: student essay text joined to demographic
covariates. This applies to derived and "processed" artifacts as well as raw files — the STM
`meta` object carries the essay text and the demographics through every stage of the pipeline, so
a partitioned corpus is not de-identified simply by virtue of being processed.

Running this pipeline requires obtaining the source data through the appropriate channels and
placing it in the working directory locally. `.gitignore` excludes `*.Rdata`/`*.Rda`/`*.rda`/`*.csv`
and knitted HTML as a backstop, but check `git status` before staging regardless.

## ⚠️ Topic labels are tentative

The twelve topic labels in `R/topic_labels.R` — "Test Anxiety", "Time Management", and so on — are
**working names, not settled findings.** They were assigned by hand by inspecting representative
essays and `labelTopics()` output for one fitted model, and they should be treated as provisional in
any write-up that cites them.

Two things make them provisional:

- **Topic numbering is an artifact of a particular fit.** It carries no meaning across different
  values of K, and is not guaranteed stable across re-fits of K = 12 either. Any change to the
  corpus or the model can reorder or reshape topics.
- **Topic 1 is a known weak fit.** It is currently labelled "Areas for Improvement", but across all
  four `labelTopics()` metrics it reads as *self-monitoring and study strategy* — its distinctive
  terms are `self-monitor`, `self-evalu`, `brainstorm`, `assign`, `schoolwork`. The label is
  retained for now pending review of its exemplar essays, and should be regarded as the least
  reliable of the twelve. See `CODE_REVIEW.md` S5-1.

The other eleven were re-validated against the corrected model and hold up; several are strongly
supported (topics 3, 10, 11, 12). Labels are defined once in `R/topic_labels.R` and derived
everywhere they appear, so revising one propagates to every figure automatically.

## Repository contents

1. preprocess_data - contains code for cleaning and wrangling student essays and other variables of interest.
2. contaminant removal - code to identify and remove contaminant essays based on visual inspection of early model results and representative essays. This file was used in combination with preprocess_data to iteratively remove essays that did not represent legitimate submissions. It reads an artifact no longer produced by this repository and is retained as a historical record; its output, `remove.csv`, is an irreplaceable primary input.
3. stm_models_final - fits five STM specifications at K = 12. K was settled by review of the clustering results across candidate models; the original K = 6-32 sweep is retained, commented, in each block.
4. essay_examples_final - code to identify representative essays based on model results and automate file save to a local directory. 
5. stm.rforestmodels.final - initial randomforest assessment of relationships between topic proportions and srl component scores/feedback views. 
6. stm_analyses_final - model diagnostics, topic labeling, covariate effect estimates, and the topic correlation network. 

Shared helpers live in `R/`, tests in `tests/` (`Rscript tests/testthat.R`), and a severity-ranked
review of known defects in `CODE_REVIEW.md`.

Note: the trained models are not included here. Beyond their size, fitted STM objects retain
per-document topic proportions and the covariate design matrix, so they fall under the same data
policy as the corpus itself.

