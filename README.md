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

The repository hosts the following files:

1. preprocess_data - contains code for cleaning and wrangling student essays and other variables of interest.
2. contaminant removal - code to identify and remove contaminant essays based on visual inspection of early model results and representative essays. This file was used in combination with preprocess_data to iteratively remove essays that did not represent legitimate submissions. 
3. stm_models_final - contains code for a range of optimized and non-optimized stm models (K = 6-32)
4. essay_examples_final - code to identify representative essays based on model results and automate file save to a local directory. 
5. stm.rforestmodels.final - initial randomforest and vip assessment of relationships between topic proportions and srl component scores/feedback views. 
6. stm_analyses_final - model diagnostics, topic labeling, covariate effect estimates, and the topic correlation network. 

Note: the trained models are not included here. Beyond their size, fitted STM objects retain
per-document topic proportions and the covariate design matrix, so they fall under the same data
policy as the corpus itself.

