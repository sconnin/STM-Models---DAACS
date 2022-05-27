# STM-Models---DAACS
Structural Topic Model files for DAACS student essays

This repository contains the results of a structural topic model analysis of student essays collected as part of the DAACS (https://daacs.net/) project for college student assessment and support. Institutions represented in this dataset currently include: Western Governors University, Excelsior College, and the University of Albany. 

The raw data are not included here. 

The repository hosts the following files:

1. preprocess_data - contains code for cleaning and wrangling student essays and other variables of interest.
2. processed_corpus - the stm partitioned data 
3. contaminant removal - code to identify and remove contaminant essays based on visual inspection of early model results and representative essays. This file was used in combination with preprocess_data to iteratively remove essays that did not represent legitimate submissions. 
4. stm_models_final - contains code for a range of optimized and non-optimized stm models (K = 6-32)
5. essay_examples_final - code to identify representative essays based on model results and automate file save to a local directory. 
6. stm.rforestmodels.final - initial randomforest and vip assessment of relationships between topic proportions and srl component scores/feedback views. 

Note: due to size limits, the trained models are not included here. 
