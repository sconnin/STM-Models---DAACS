# STM-Models---DAACS
Structural Topic Model files for DAACS student essays

This repository contains the results of a structural topic model analysis of student essays collected as part of the DAACS (https://daacs.net/) project for college student assessment and support. Institutions represented in this dataset currently include: Western Governors University, Excelsior College, and the University of Albany. 

## Data availability

**No DAACS data is included in this repository, and none may be committed to it.**

The dataset is IRB-protected human-subjects data: student essay text joined to demographic
covariates. This applies to derived and "processed" artifacts as well as raw files — the STM
`meta` object carries the essay text and the demographics through every stage of the pipeline, so
a partitioned corpus is not de-identified simply by virtue of being processed.

## ⚠️ Topic labels are tentative

The twelve topic labels in `R/topic_labels.R` — "Test Anxiety", "Time Management", and so on — are
**working names, not settled findings.** They were assigned by hand by inspecting representative
essays and `labelTopics()` output for one fitted model, and they should be treated as provisional in
any write-up that cites them.

Two things make them provisional:

- **Topic numbering is an artifact of a particular fit.** It carries no meaning across different
  values of K, and is not guaranteed stable across re-fits of K = 12 either. Any change to the
  corpus or the model can reorder or reshape topics.
- **Topic 1 is a known weak fit.** **Decision (2026-08-27): the label is retained for now**, by the
  project owner, and should be regarded as the least reliable of the twelve. See `CODE_REVIEW.md`
  S5-1.

The other eleven were re-validated against the corrected model and hold up; several are strongly
supported (topics 3, 10, 11, 12). Labels are defined once in `R/topic_labels.R` and derived
everywhere they appear, so revising one propagates to every figure automatically.

## Results

Preliminary results are written to `results/RESULTS.md` by `Rscript scripts/build_results.R`, which
reads the fitted models. **That document is kept locally, is not published from this repository, and
is marked preliminary — it is not for publication or circulation outside the project.** Regenerate
it rather than editing it by hand.

Everything it contains is aggregate — corpus and covariate counts, topic-word tables, effect
estimates, variance explained. No essay text and no row-level record reaches the document or its
figures.

### Multiple comparisons

Every covariate is tested against all twelve topics, which is 228 hypotheses in the main-effects set
alone. `R/multiple_comparisons.R` implements three responses, used together rather than chosen
between: results are reported as exploratory; p-values are Benjamini-Hochberg adjusted within each
covariate family to control the false discovery rate; and multi-term covariates — race across seven
levels, age as a ten-term spline — are assessed with one joint Wald test per topic rather than one
test per coefficient. The joint test reproduces the marginal t-test exactly when a covariate has a
single term, which is what makes the rows comparable.

## Model selection: why K = 12

**K = 12 was settled by best professional judgement, informed by semantic coherence and exclusivity
diagnostics rather than determined by them.** The diagnostics narrowed the range; the choice came
from reviewing what the clusterings actually contained — reading representative essays per topic and
asking at which K the topics were substantively distinct and interpretable. Note that the pipeline
computes *exclusivity* and *semantic coherence*; perplexity was not part of the comparison.

### What was explored before the choice

| Stage | What was run |
|---|---|
| Contamination screening | An early K = 6–28 run whose high-probability documents were read by hand, producing `remove.csv` — the list of non-substantive submissions excluded from every later fit |
| K sweep | K = 6, 12, 18, 24, 32 |
| Optimised prevalence | `manyTopics()`, 10 candidate runs per K, spectral initialisation, best model retained per K |
| Optimised prevalence + content | `selectModel()`, 10 candidate runs per K, `max.em.its = 75` |
| Unoptimised comparisons | plain `stm()` at each K in three specifications — prevalence + content, prevalence only, content only |
| Diagnostics | exclusivity and semantic coherence per topic, compared across K for the optimised prevalence family |

## Repository contents

1. preprocess_data - contains code for cleaning and wrangling student essays and other variables of interest.
2. contaminant removal - code to identify and remove contaminant essays based on visual inspection of early model results and representative essays. This file was used in combination with preprocess_data to iteratively remove essays that did not represent legitimate submissions. It reads an artifact no longer produced by this repository and is retained as a historical record; its output, `remove.csv`, is an irreplaceable primary input.
3. stm_models_final - fits five STM specifications at K = 12. K was settled by review of the clustering results across candidate models; the original K = 6-32 sweep is retained, commented, in each block.
4. essay_examples_final - code to identify representative essays based on model results and automate file save to a local directory. 
5. stm.rforestmodels.final - initial randomforest assessment of relationships between topic proportions and srl component scores/feedback views. 
6. stm_analyses_final - model diagnostics, topic labeling, covariate effect estimates, and the topic correlation network. 

Shared helpers live in `R/`, tests in `tests/` (`Rscript tests/testthat.R`), and a severity-ranked
review of known defects in `CODE_REVIEW.md`. Every computation the notebooks repeat across model
families is defined once there and called from the notebooks:

| File | Provides |
|---|---|
| `cleaning_patterns.R` | the 21 essay-prompt regex patterns, in the order they must be applied |
| `covariate_levels.R` | gender and race harmonisation across the three institutions |
| `covariate_effects.R` | `estimateEffect()` fits, the significance filter, and the effect plots |
| `exemplars.R` | representative-passage selection and the top-essay files |
| `model_formulas.R` | the prevalence and content formulas the five families are fitted with |
| `multiple_comparisons.R` | FDR adjustment, joint tests for multi-term covariates, and the exploratory caveat |
| `rf_topic_importance.R` | one random forest per topic, and variable-importance plots |
| `srl_features.R` | the fourteen SRL scales, subset per institution |
| `topic_labels.R` | the twelve topic labels and the `TopicN` rename map |
| `topic_prevalence.R` | mean topic proportions and the prevalence bar charts |
| `topic_word_tables.R` | top-words tables for all four `labelTopics()` weightings |

Note: the trained models are not included here. Beyond their size, fitted STM objects retain
per-document topic proportions and the covariate design matrix, so they fall under the same data
policy as the corpus itself.

