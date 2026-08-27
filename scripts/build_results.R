# Build the preliminary results document.
#
#   Rscript scripts/build_results.R
#
# Writes results/RESULTS.md and results/figures/*.png from the fitted models.
# Nothing else in the pipeline writes a results file, so this is the one place
# the corrected numbers are recorded.
#
# ---------------------------------------------------------------------------
# IRB SAFETY
#
# Everything written here is aggregate: corpus counts, covariate counts, model
# diagnostics, topic-word tables (vocabulary, not student text), effect
# estimates, and variance explained. findThoughts() and plotQuote() are never
# called -- those return essay text. No row-level record reaches the document or
# any figure.
# ---------------------------------------------------------------------------

suppressMessages({
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(purrr)
  library(readr)
  library(stringr)
  library(ggplot2)
  library(stm)
  library(tidytext)
  library(igraph)
  library(huge)
  library(patchwork)
  library(janitor)
  library(randomForest)
  library(magrittr)
})

for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)

# estimateEffect(uncertainty = "Global") draws posterior samples, and
# summary.estimateEffect() simulates on top of those draws, so every number in
# section 4 is stochastic. Unseeded, the F statistics move materially between
# runs -- one topic's gender statistic was observed at 150 and 181 on two builds
# of this document. Seeding once here makes the whole document regenerate
# exactly; the value matches the seed used for the random forests.
RESULTS_SEED <- 20220527
set.seed(RESULTS_SEED)

FIG_DIR <- "results/figures"
OUT <- "results/RESULTS.md"
dir.create(FIG_DIR, showWarnings = FALSE, recursive = TRUE)

# The document accumulates into an environment rather than a global, so the
# writer functions have one explicit place to append to.
doc <- new.env(parent = emptyenv())
doc$lines <- character()
add <- function(...) doc$lines <- c(doc$lines, paste0(...))
blank <- function() doc$lines <- c(doc$lines, "")

#' Render a data frame as a GitHub markdown table.
md_table <- function(df, digits = 3) {
  df <- as.data.frame(df)
  # Format per element: `scientific` takes one value, not a vector, and very
  # small p-values are unreadable in fixed notation.
  format_number <- function(v) {
    if (is.na(v)) {
      ""
    } else if (v != 0 && abs(v) < 1e-4) {
      formatC(v, format = "e", digits = 2)
    } else {
      format(signif(v, digits), scientific = FALSE, trim = TRUE)
    }
  }
  numeric_cols <- vapply(df, is.numeric, logical(1))
  df[numeric_cols] <- lapply(df[numeric_cols], function(x) {
    vapply(x, format_number, character(1))
  })
  header <- paste0("| ", paste(names(df), collapse = " | "), " |")
  rule <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  body <- apply(df, 1, function(r) paste0("| ", paste(trimws(r), collapse = " | "), " |"))
  c(header, rule, body)
}
add_table <- function(df, digits = 3) doc$lines <- c(doc$lines, md_table(df, digits), "")

#' Save a base-graphics figure and return its markdown link.
save_base_plot <- function(file, expr, width = 1000, height = 800) {
  path <- file.path(FIG_DIR, file)
  grDevices::png(path, width = width, height = height, res = 120)
  on.exit(invisible(grDevices::dev.off()), add = TRUE)
  force(expr)
  invisible(path)
}
fig <- function(file, caption) {
  add("![", caption, "](figures/", file, ")")
  blank()
  add("*", caption, "*")
  blank()
}

say <- function(...) cat(..., "\n", sep = "")

# ---------------------------------------------------------------------------
# Load corpus and models
# ---------------------------------------------------------------------------
say("loading corpus and models ...")
load("processed_corpus_final.Rdata")
load("stm.prevalence.model.k12.Rda")
load("stm.content.model.k12.Rda")
load("optimized.prevalence.model.k12.Rda")

n_documents <- length(documents)
stopifnot(n_documents == 8210)

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
add("# Preliminary Results — STM of DAACS Self-Reflection Essays")
blank()
add("**Generated:** ", format(Sys.Date()), " by `scripts/build_results.R`. ",
    "Regenerate rather than edit by hand.")
blank()
add("> ## ⚠️ Preliminary — not for publication")
add(">")
add("> These results are a working record of what the corrected pipeline produces. ",
    "They have not been through statistical review, replication, or the ",
    "interpretive work that turns model output into findings. Several inputs are ",
    "still provisional — the topic labels most of all. **Do not cite, circulate ",
    "outside the project, or treat any number here as a finding.**")
add(">")
add("> ", exploratory_note(alpha = 0.05))
blank()

# ---------------------------------------------------------------------------
# Corpus
# ---------------------------------------------------------------------------
say("summarising corpus ...")
add("## 1. Corpus")
blank()
add("Student self-reflection essays collected through DAACS at three institutions, ",
    "cleaned of essay-prompt boilerplate and filtered to submissions carrying at ",
    "least 50 unique words.")
blank()
add_table(tibble(
  Quantity = c("Documents", "Vocabulary terms", "Topics (K)"),
  Value = c(n_documents, length(vocab), 12)
))

add("### Composition")
blank()
for (v in c("institution", "gender", "race", "first_gen")) {
  if (!v %in% names(meta)) next
  counts <- meta |>
    count(.data[[v]], name = "documents") |>
    arrange(desc(documents)) |>
    mutate(percent = round(100 * documents / sum(documents), 1))
  names(counts)[1] <- v
  add("**", v, "**")
  blank()
  add_table(counts)
}
# first_gen carries an UNKNOWN level, and it is not distributed evenly. Showing
# the crosstab here is what makes section 4.2's split reading legible.
if (all(c("first_gen", "institution") %in% names(meta))) {
  crosstab <- as.data.frame.matrix(table(meta$institution, meta$first_gen))
  crosstab <- tibble::rownames_to_column(crosstab, var = "institution")
  add("**first_gen by institution**")
  blank()
  add_table(crosstab)
  add("`UNKNOWN` is almost entirely one institution — ",
      sum(meta$first_gen == "UNKNOWN" & meta$institution == "EC"), " of ",
      sum(meta$first_gen == "UNKNOWN"), " such documents. Institution is **not** ",
      "in the prevalence formula, so a contrast against `UNKNOWN` is close to an ",
      "institution indicator. Section 4.2 reports it separately for that reason.")
  blank()
}

if ("age" %in% names(meta)) {
  age_summary <- summary(meta$age)
  add_table(tibble(
    Statistic = names(age_summary),
    Age = as.numeric(age_summary)
  ), digits = 4)
}

# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------
add("## 2. Models")
blank()
add("Five specifications were fitted at K = 12. Results below come from ",
    "`stm.p.12`, the prevalence-only `stm()` model, which is the model every ",
    "covariate analysis and the topic network use. The content model ",
    "(`stm.c.12`) supplies the per-gender vocabulary comparisons.")
blank()
add_table(tibble(
  Object = c("stm.model.12", "content_prev.model.k12", "stm.pc.12", "stm.p.12", "stm.c.12"),
  Fitted_by = c("manyTopics()", "selectModel()", "stm()", "stm()", "stm()"),
  Specification = c("prevalence", "prevalence + content", "prevalence + content",
                    "prevalence", "content")
))
add("Prevalence formula: `", deparse1(PREVALENCE_FORMULA), "` · ",
    "content formula: `", deparse1(CONTENT_FORMULA), "`")
blank()
add("Every fit is seeded; see `stm_models_final.rmd` for the seed per family.")
blank()

# ---------------------------------------------------------------------------
# Topics
# ---------------------------------------------------------------------------
say("labelling topics ...")
add("## 3. Topics")
blank()
add("Labels are **working names**, assigned by hand from `labelTopics()` output ",
    "and exemplar essays. Topic numbering is an artifact of this particular fit ",
    "and carries no meaning across values of K or across re-fits.")
blank()

labels12 <- labelTopics(stm.p.12, 1:12, n = 10)
proportions <- topic_proportions(stm.p.12, n_documents)
prop_table <- proportions |>
  mutate(topic_number = as.integer(as.character(topic))) |>
  arrange(desc(proportion)) |>
  transmute(
    Topic = topic_number,
    Label = topic_labels(topics = topic_number),
    `Mean prevalence (%)` = round(proportion, 2)
  )
add_table(prop_table)

p <- plot_topic_proportions(
  proportions,
  title = "Mean topic prevalence, K = 12",
  subtitle = "Prevalence-only stm() model"
)
ggsave(file.path(FIG_DIR, "topic_prevalence.png"), p, width = 7, height = 5, dpi = 150)
fig("topic_prevalence.png", "Mean topic prevalence across the corpus")

add("### Top words by weighting")
blank()
add("All four weightings are shown deliberately. `prob` and `frex` favour frequent ",
    "terms; `lift` and `score` surface the low-frequency, distinctive terms that ",
    "identify a topic's subject. Reading only the first two has already produced ",
    "one wrong conclusion in this project.")
blank()
metrics <- c(prob = "Probability", frex = "FREX", lift = "Lift", score = "Score")
for (i in seq_along(metrics)) {
  words <- apply(labels12[[i]], 1, paste, collapse = ", ")
  add("**", metrics[[i]], "**")
  blank()
  add_table(tibble(
    Topic = seq_along(words),
    Label = topic_labels(topics = seq_along(words)),
    `Top 10 words` = unname(words)
  ))
}

# ---------------------------------------------------------------------------
# Covariate effects
# ---------------------------------------------------------------------------
say("estimating covariate effects ...")
add("## 4. Covariate effects on topic prevalence")
blank()
add("Estimated with `estimateEffect(uncertainty = \"Global\")` against `stm.p.12`.")
blank()

effects <- estimate_effects(
  model = stm.p.12,
  metadata = meta,
  formulas = list(
    gender = 1:12 ~ gender,
    race = 1:12 ~ race,
    first_gen = 1:12 ~ first_gen,
    age = 1:12 ~ s(age)
  )
)

add("### 4.1 How many tests, and how many survive adjustment")
blank()

test_counts <- map_dfr(names(effects), function(nm) {
  raw <- tidy(effects[[nm]]) |> filter(term != "(Intercept)")
  adj <- adjust_effects(effects[[nm]])
  tibble(
    Covariate = nm,
    `Terms tested` = nrow(raw),
    `p < 0.05 uncorrected` = sum(raw$p.value < 0.05),
    `FDR < 0.05` = sum(adj$p.adjusted < 0.05),
    `Expected by chance` = round(0.05 * nrow(raw), 1)
  )
})

# Stated from the table rather than hard-coded: a covariate gaining a level
# changes this count, and a number typed into prose would not follow.
total_terms <- sum(test_counts$`Terms tested`)
add("Counted the way the code filters them, the main-effects set is **",
    total_terms, " hypotheses** — ",
    paste(sprintf("%d for %s", test_counts$`Terms tested`, test_counts$Covariate),
          collapse = ", "),
    ". Race and first-generation status contribute one term per contrast against ",
    "their reference level, and age contributes ten because `s(age)` expands to a ",
    "spline. At an uncorrected 0.05 roughly ", round(0.05 * total_terms),
    " terms would clear the bar from noise alone.")
blank()
add_table(test_counts)

add("**Everything in section 4 is stochastic, and is seeded so that it is not.** ",
    "`estimateEffect(uncertainty = \"Global\")` draws posterior samples, and ",
    "`summary.estimateEffect()` -- which `tidy()` calls -- simulates 500 more per ",
    "draw. Unseeded, these numbers move between runs: on two builds of this ",
    "document one topic's gender statistic came out at 150 and at 181, and the ",
    "count of terms clearing an uncorrected 0.05 changed. This document sets ",
    "`set.seed(", RESULTS_SEED, ")` once at the top, so re-running ",
    "`scripts/build_results.R` reproduces it exactly. Anything computed the same ",
    "way without a seed will not reproduce.")
blank()

add("### 4.2 Joint tests — one question per topic")
blank()
add("Race enters as six contrasts and age as a ten-term spline, so a term-level ",
    "filter asks the wrong question ten or six times over. A joint Wald test asks ",
    "it once per topic. For a single-term covariate the joint test reproduces the ",
    "marginal t-test exactly, which is what makes it comparable across rows.")
blank()

# first-generation status is split deliberately. Pooling TRUE and UNKNOWN into
# one joint test would report a first-generation effect that is partly an
# institution effect, since UNKNOWN is almost entirely Excelsior and institution
# is not a covariate in these models.
joint_specs <- list(
  list(name = "gender", effect = effects$gender, pattern = "^gender",
       note = NULL),
  list(name = "race", effect = effects$race, pattern = "^race",
       note = NULL),
  list(name = "first_gen (TRUE vs FALSE)", effect = effects$first_gen,
       pattern = "^first_genTRUE",
       note = "The substantive contrast: first-generation students against those known not to be."),
  list(name = "first_gen (UNKNOWN vs FALSE)", effect = effects$first_gen,
       pattern = "^first_genUNKNOWN",
       note = paste(
         "**Not an effect of first-generation status.** UNKNOWN is a missingness",
         "category concentrated in one institution, so this row measures how that",
         "institution's essays differ. Reported for transparency, not as a finding."
       )),
  list(name = "age", effect = effects$age, pattern = "^s\\(age\\)",
       note = NULL)
)

joint_all <- map_dfr(joint_specs, function(spec) {
  joint_effect_test(spec$effect, spec$pattern) |>
    mutate(Covariate = spec$name, .before = 1)
})

for (spec in joint_specs) {
  block <- joint_all |>
    filter(Covariate == spec$name) |>
    arrange(p.adjusted) |>
    transmute(
      Topic = topic,
      Label = topic_labels(topics = topic),
      Terms = n_terms,
      `F` = round(statistic, 2),
      `p` = p.value,
      `p (BH)` = p.adjusted,
      `FDR < 0.05` = ifelse(p.adjusted < 0.05, "yes", "no")
    )
  add("**", spec$name, "** — ", sum(block$`FDR < 0.05` == "yes"),
      " of 12 topics survive at FDR 0.05")
  blank()
  if (!is.null(spec$note)) {
    add(spec$note)
    blank()
  }
  add_table(block)
}

add("**On the adjustment itself.** Benjamini-Hochberg controls the false ",
    "discovery rate under independence or positive dependence. Topic ",
    "proportions are compositional -- each document's twelve proportions sum to ",
    "1 -- so tests across topics carry some negative dependence, which this ",
    "procedure does not formally cover. Benjamini-Yekutieli holds under arbitrary ",
    "dependence and is the conservative alternative; `adjust_effects(method = ",
    "\"BY\")` and `joint_effect_test(method = \"BY\")` will produce it. BH is ",
    "reported here as the conventional choice, not because the dependence ",
    "structure has been verified.")
blank()

add("**Read 4.1 and 4.2 together.** For race the two disagree, instructively: no ",
    "individual contrast survives term-level adjustment, yet several topics ",
    "survive the joint test. That is not a contradiction. The joint test asks ",
    "whether race matters *at all* for a topic, pooling the evidence across all ",
    "six contrasts, and pays the multiplicity cost once rather than six times. ",
    "Where the two disagree, the joint test is the one that matches the question ",
    "being asked; the term-level table is the one that says which contrast is ",
    "driving it, and for race no single contrast is.")
blank()

add("### 4.3 Direction of effect")
blank()
add("Difference plots contrast two levels across all twelve topics. They show ",
    "direction and magnitude; significance is the tables above, after adjustment.")
blank()

save_base_plot("effect_gender.png", {
  plot_difference_effect(effects$gender,
    covariate = "gender", value1 = "F", value2 = "M",
    xlab = "More Male ... More Female",
    main = "Effect of gender on topic prevalence",
    xlim = c(-.06, .04), model = stm.p.12
  )
})
fig("effect_gender.png", "Gender: female minus male topic prevalence")

race_levels <- levels(as.factor(meta$race))
for (group in intersect(c("Black or African American", "Asian", "Latinx"), race_levels)) {
  file <- paste0("effect_race_", gsub("[^A-Za-z]", "", group), ".png")
  save_base_plot(file, {
    plot_difference_effect(effects$race,
      covariate = "race", value1 = group, value2 = "White",
      xlab = paste("More White ... More", group),
      main = paste0("Effect of race: ", group, " vs White"),
      xlim = c(-.05, .05), model = stm.p.12
    )
  })
  fig(file, paste0("Race: ", group, " minus White topic prevalence"))
}

save_base_plot("effect_first_gen.png", {
  plot_difference_effect(effects$first_gen,
    covariate = "first_gen", value1 = "FALSE", value2 = "TRUE",
    xlab = "More First Generation ... Less First Generation",
    main = "Effect of first-generation status",
    xlim = c(-.04, .02), model = stm.p.12
  )
})
fig("effect_first_gen.png", "First-generation status: non-first-gen minus first-gen")

add("### 4.4 Age")
blank()
top_age <- joint_all |> filter(Covariate == "age") |> arrange(p.adjusted) |> head(3)
add("Age is jointly significant for ",
    sum(joint_all$Covariate == "age" & joint_all$p.adjusted < 0.05),
    " of 12 topics. Read that as a statement about detectability, not importance: ",
    "with ", n_documents, " documents a ten-degree-of-freedom test has enough ",
    "power that significance is a weak bar, and a near-universal result is what ",
    "high power looks like. The curves below carry the magnitude, and the ",
    "relationship is a spline, so direction varies across the age range rather ",
    "than being a single slope. The three strongest are shown.")
blank()
for (k in top_age$topic) {
  file <- paste0("effect_age_topic", k, ".png")
  save_base_plot(file, {
    plot_continuous_effect(effects$age, "age", topics = k, model = stm.p.12)
  }, width = 800, height = 600)
  fig(file, paste0("Topic ", k, " (", topic_labels(topics = k), ") prevalence by age"))
}

# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------
say("estimating gender x age interaction ...")
add("### 4.5 Gender x age interaction")
blank()
interaction_fit <- estimateEffect(
  formula = 1:12 ~ gender * age,
  stmobj = stm.p.12, metadata = meta, uncertainty = "Global"
)
interaction_joint <- joint_effect_test(interaction_fit, "^gender[A-Za-z]*:age")
add("Joint test on the interaction terms only, one per topic, BH-adjusted across topics.")
blank()
add_table(
  interaction_joint |>
    arrange(p.adjusted) |>
    transmute(
      Topic = topic,
      Label = topic_labels(topics = topic),
      `F` = round(statistic, 2),
      `p` = p.value,
      `p (BH)` = p.adjusted,
      `FDR < 0.05` = ifelse(p.adjusted < 0.05, "yes", "no")
    )
)

interaction_topics <- interaction_joint |>
  arrange(p.adjusted) |>
  head(3) |>
  pull(topic)

for (k in interaction_topics) {
  topic_effect <- estimateEffect(
    formula = stats::as.formula(paste0("c(", k, ") ~ gender * age")),
    stmobj = stm.p.12, metadata = meta, uncertainty = "Global"
  )
  theta_range <- range(stm.p.12$theta[, k])
  ylim <- c(max(0, theta_range[1]), theta_range[2] * 0.6)
  file <- paste0("interaction_topic", k, ".png")
  save_base_plot(file, {
    plot_gender_age_interaction(
      topic_effect, model = interaction_fit, topic = k,
      ylim = ylim, alpha_label = "joint BH-adjusted"
    )
  }, width = 800, height = 600)
  fig(file, paste0("Topic ", k, " (", topic_labels(topics = k), "): age curve by gender"))
}

# ---------------------------------------------------------------------------
# Topic correlation
# ---------------------------------------------------------------------------
say("building topic network ...")
add("## 5. Topic correlation network")
blank()
add("Topics that co-occur within documents above a simple correlation cutoff of 0.05.")
blank()
topic_corr <- topicCorr(stm.p.12, method = "simple", cutoff = .05)
save_base_plot("topic_network.png", {
  plot(topic_corr,
    main = "K = 12 topic network (correlation > 0.05)",
    vlabels = topic_labels(), vertex.label.cex = 0.75,
    label.color = "darkred", vertex.color = "lightblue"
  )
})
fig("topic_network.png", "Topic correlation network")

# ---------------------------------------------------------------------------
# Random forests
# ---------------------------------------------------------------------------
say("loading SRL features ...")
add("## 6. Self-regulated learning and topic prevalence")
blank()
add("One random forest per topic, predicting that topic's document prevalence ",
    "from the fourteen SRL scale scores. Variance explained is the forest's own ",
    "out-of-bag R-squared, so it is an estimate of predictive signal, not a ",
    "significance test.")
blank()
add("**This section covers two institutions, not three.** Albany collects no grit ",
    "measure, so `srl_grit` is empty for all of its documents, and the listwise ",
    "deletion inside each forest drops every Albany row -- 490 of them, the whole ",
    "institution -- because one of fourteen predictors is missing. The forests are ",
    "fitted on WGU and Excelsior only. Dropping `srl_grit` from the predictor set ",
    "would restore Albany at the cost of that scale; that is a modelling decision ",
    "and has not been taken. See `CODE_REVIEW.md` S1-1.")
blank()

load("DAACS-WGU.rda")
load("DAACS-EC.rda")
load("DAACS-ualbany.rda")

srl_features <- rbind(
  srl_subset(daacs.wgu, institution = "WG"),
  srl_subset(daacs.ec, institution = "EC"),
  srl_subset(daacs.ualbany, institution = "Alb", unavailable = "srl_grit")
) |>
  mutate(across(where(is.numeric), \(x) round(x, 2)))

table_meta <- meta |> select(doc_id, institution)
topic_table_12 <- make.dt(stm.p.12, meta = table_meta) |>
  relocate(c(doc_id, institution), .after = docnum) |>
  select(!docnum)

srl_topics_12 <- left_join(srl_features, topic_table_12, by = c("doc_id", "institution"))

say("fitting topic forests (this is the slow step) ...")
topic_forests <- fit_topic_forests(srl_topics_12, topics = 1:12, ntree = 1000)

rf_table <- topic_forests |>
  transmute(
    Topic = topic,
    Label = topic_labels(topics = topic),
    `Documents` = n_obs,
    `Variance explained (%)` = round(var_explained, 2)
  ) |>
  arrange(desc(`Variance explained (%)`))
add_table(rf_table)

add("**Reading this table.** Out-of-bag R-squared can be negative: it means the ",
    "forest predicts worse than the mean, which is what a model with no signal ",
    "looks like. Values near zero should be read as *no detectable relationship*, ",
    "not as a weak one.")
blank()

importance_plots <- map2(
  topic_forests$model, topic_forests$topic,
  ~ plot_topic_importance(.x, title = paste0("Topic ", .y, ": ", topic_labels(topics = .y)))
)
combined <- patchwork::wrap_plots(importance_plots, ncol = 3)
ggsave(file.path(FIG_DIR, "rf_topic_importance.png"), combined,
       width = 16, height = 18, dpi = 110, limitsize = FALSE)
fig("rf_topic_importance.png", "SRL predictor importance, one panel per topic")

say("fitting feedback-views forest ...")
add("### 6.1 Feedback views (WGU only)")
blank()
add("The same approach with the direction reversed: topic proportions as ",
    "predictors, the number of times a student viewed their DAACS feedback as the ",
    "response. WGU is the only institution carrying this measure.")
blank()

wgu_views <- daacs.wgu |>
  clean_names() |>
  select(daacs_id, feedback_views) |>
  rename(doc_id = daacs_id) |>
  mutate(institution = "WG") |>
  relocate(institution, .after = doc_id) |>
  filter(!is.na(feedback_views))

feedback_views_12 <- left_join(wgu_views, topic_table_12, by = c("doc_id", "institution"))

views_12 <- feedback_views_12 |>
  select(feedback_views, starts_with("topic")) |>
  na.omit() |>
  rename(all_of(topic_rename_map())) |>
  clean_names()

set.seed(20220527)
views_model_12 <- randomForest(feedback_views ~ ., data = views_12, ntree = 1000, importance = TRUE)

add_table(tibble(
  Quantity = c("Documents", "Variance explained (%)"),
  Value = c(nrow(views_12), round(max(views_model_12$rsq) * 100, 2))
))

p <- plot_topic_importance(views_model_12, n_features = 12,
                           title = "Feedback views: topic importance")
ggsave(file.path(FIG_DIR, "rf_feedback_views.png"), p, width = 8, height = 6, dpi = 150)
fig("rf_feedback_views.png", "Topic importance for predicting feedback views")

# ---------------------------------------------------------------------------
# Caveats
# ---------------------------------------------------------------------------
# Provenance moved here out of README.md: it belongs with the results it
# qualifies, and the README is a public-facing file while this document is not.
add("## 7. Provenance and analytic record")
blank()
add("### Obtaining the data")
blank()
add("No DAACS data is included in the repository. Running the pipeline requires ",
    "obtaining the source data through the appropriate channels and placing it in ",
    "the working directory locally. `.gitignore` excludes `*.Rdata`, `*.Rda`, ",
    "`*.rda`, `*.csv` and knitted HTML as a backstop, but check `git status` ",
    "before staging regardless.")
blank()

add("### Why K = 12, and what preceded it")
blank()
add("K = 12 was settled by best professional judgement, informed by semantic ",
    "coherence and exclusivity diagnostics rather than determined by them. That ",
    "review is complete and the decision is final for this analysis, so ",
    "`stm_models_final.rmd` fits K = 12 only. The full K = 6/12/18/24/32 sweep is ",
    "retained, commented, with its seeds reserved, and the ",
    "exclusivity-versus-coherence chunk in `stm_analyses_final.Rmd` is marked ",
    "`eval = FALSE`; the two are a pair and must be restored together.")
blank()
add("**Two limits on that record.** The original models were fitted without seeds, ",
    "so the exact objects behind the K comparison cannot be regenerated — seeds ",
    "were added when the corrected models were re-fit. And the review itself was ",
    "interpretive: no written record survives of which essays were read, or of ",
    "what distinguished K = 12 from its neighbours. If K needs to be defended in a ",
    "write-up, that reasoning should be reconstructed and written down while it is ",
    "still recoverable.")
blank()

add("### Topic 1")
blank()
add("Topic 1 is labelled \"Areas for Improvement\" and is the weakest of the ",
    "twelve. Across all four `labelTopics()` metrics it reads as *self-monitoring ",
    "and study strategy* — its distinctive terms are `self-monitor`, ",
    "`self-evalu`, `brainstorm`, `assign`, `schoolwork`. The label is retained by ",
    "decision of the project owner (2026-08-27) pending review of its exemplar ",
    "essays, and should be treated as the least reliable label in this document.")
blank()

add("## 8. Caveats and open items")
blank()
add("- **Topic labels are provisional.** Topic 1 is a known weak fit and is ",
    "retained pending review of its exemplar essays. See `README.md`.")
add("- **K = 12 was chosen by professional judgement**, informed by coherence and ",
    "exclusivity diagnostics rather than determined by them. See `README.md`.")
add("- **The essay filter has a known gap.** One submission below the ",
    "50-unique-word floor remains in the corpus by explicit decision; see ",
    "`CODE_REVIEW.md` S1-9.")
add("- **No causal claim is supported.** These are associations between topic ",
    "prevalence and covariates in observational data from three institutions ",
    "with different intake populations.")
add("- **Institution is not in the prevalence formula**, and it is confounded with ",
    "at least one covariate level: `first_gen == UNKNOWN` is almost entirely one ",
    "institution. Any covariate level that tracks institution will absorb ",
    "institution differences. Adding institution as a covariate would require ",
    "re-fitting the models.")
add("- **Random forest variance explained is not a hypothesis test** and carries ",
    "no p-value. Treat small values as absence of signal.")
add("- **The random forest section excludes Albany entirely**, through listwise ",
    "deletion on a scale that institution does not collect. See section 6.")
add("- **The FDR adjustment assumes a dependence structure that has not been ",
    "checked.** Topic proportions are compositional; see the note in 4.2.")
add("- **Uncorrected p-values appear nowhere in this document except the count ",
    "table in 4.1**, which exists to show what adjustment changes.")
add("- **Section 4 is reproducible only because it is seeded.** The estimation ",
    "and its summary are both stochastic; see the note in 4.1.")
blank()
add("Generated from commit `", system("git rev-parse --short HEAD", intern = TRUE),
    "` with `set.seed(", RESULTS_SEED, ")`.")
blank()

writeLines(doc$lines, OUT)
say("")
say("wrote ", OUT, " (", length(doc$lines), " lines)")
say("figures in ", FIG_DIR, ": ", length(list.files(FIG_DIR)))
say("")
say("Aggregates only -- no essay text, no student records.")
