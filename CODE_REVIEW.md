# Code Review — DAACS STM Pipeline

**Reviewed:** 2026-08-26 · **Scope:** all six `.Rmd` files at repo root (1,858 lines) ·
**Method:** static reading. No code was executed — R is not installed on the review machine, and the
DAACS data is IRB-protected and was deliberately not opened.

Because nothing was run, findings are stated as **what the code does when read literally**. Items
marked _needs runtime confirmation_ depend on data values that cannot be inspected without violating
the IRB constraint; confirm those locally before acting.

One exception: the corpus **schema** was inspected (column names, dimensions, and classes only — no
row-level content). That confirmed S1-5 and is noted there.

---

## How to use this document

Findings are grouped by severity, and the severity determines the workflow:

| Severity | Meaning | Handling |
|---|---|---|
| **S1 — Correctness** | Produces a wrong number or silently corrupts data | Do **not** fix during formatting. Each needs sign-off + a pipeline re-run, because each changes published results. |
| **S2 — Broken reference** | Code cannot execute as written | Safe to fix — these paths don't currently run, so fixing them breaks nothing that works today. |
| **S3 — Reproducibility** | Runs, but results can't be regenerated | Fixing changes results (the originals came from unseeded runs and are unrecoverable). Accept and re-run. |
| **S4 — Style / deprecation / duplication** | No behavior change | Mechanical. Safe to batch into the style and extraction passes. |

Counts: **8 S1 · 5 S2 · 4 S3 · ~9 recurring S4 patterns.**

---

## S1 — Correctness

### S1-1 · Entire `srl_grit` column set to `NA` for Albany
`stm.rforestmodels.final.Rmd:82`

```r
mutate(srl_grit = case_when(srl_grit %in% NaN ~ NA))
```

Two defects in one line. `case_when()` returns `NA` for any row matching **no** branch, and there is
no `.default`/`TRUE` branch here — so every row where the condition is false also becomes `NA`.
Separately, `%in% NaN` is not a NaN test: `%in%` uses `match()`, which compares on equality, and
`NaN` does not compare equal to itself. The condition is therefore false for every row, including
genuine `NaN`s.

**CORRECTION — this finding overstated its impact.** Checked against the data:

```
WG   rows=13196  non-NA=6386  NaN=0
EC   rows=10380  non-NA=2966  NaN=54
Alb  rows=3941   non-NA=0     NaN=490
```

Albany has **zero** usable `srl_grit` values *before this line runs*. The column is already empty, so
the buggy `case_when()` destroys nothing. The conclusion stands — Albany contributes nothing to
`srl_grit`, and every forest using it is fitted on WGU + Excelsior only — but the cause is missing
source data, not this line.

The line remains wrong and should still be fixed: it has no fallback branch, and `%in% NaN` cannot
match anything (`NaN` does not compare equal to itself). It would silently null the column the moment
Albany data did arrive.

**Recommendation** — say what is actually true. Albany has no grit measure; write that down rather
than expressing it as a transformation that appears to do something:

```r
# Albany collects no grit measure; the column is present but empty.
mutate(srl_grit = NA_real_)
```

Downgraded from a correctness bug to a latent one: no current impact, guaranteed impact if the data
changes.

**RESOLVED** — replaced with `mutate(srl_grit = NA_real_)`, which states the fact directly. No result
change: the column was already empty.

---

### S1-2 · K=12 topic-2 forest is fitted on the K=32 table
`stm.rforestmodels.final.Rmd:147`

```r
t2.12 <- srl.topics.32 %>% select(Topic2, starts_with('srl')) %>% na.omit()
```

Every other block in this section (L141–211) reads `srl.topics.12`. This one reads `srl.topics.32`
(defined L131). `Topic2` means a different latent topic in the K=32 model than in the K=12 model, so
`rf.t2.12` and the reported `var.t2.12` (`# max var explained -3.2`) do not describe what they are
labeled as describing.

**Recommendation** — change to `srl.topics.12`. This is subsumed by the Phase 4 rewrite of the block
into a single `map()` over topics, which makes the class of error impossible.

**RESOLVED** — `fit_topic_forests()` in `R/rf_topic_importance.R` iterates over topics against one
table, so the error cannot recur. **This changes the reported topic-2 figure**, which described a
different latent topic than its label claimed.

---

### S1-3 · Three of four feedback-view frames are duplicates
`stm.rforestmodels.final.Rmd:243-246`

```r
feedback.views.12 <- left_join(wgu.views, t.12, by = c('doc_id', 'institution'))
feedback.views.18 <- left_join(wgu.views, t.12, ...)   # should be t.18
feedback.views.24 <- left_join(wgu.views, t.12, ...)   # should be t.24
feedback.views.32 <- left_join(wgu.views, t.12, ...)   # should be t.32
```

`.18`, `.24`, and `.32` are byte-identical to `.12`. Currently latent — only `feedback.views.12` is
consumed downstream (L258) — but the objects exist and are named as though they hold K=18/24/32 data,
so any future use silently gets K=12.

**Recommendation** — fix the joins, or delete the three unused objects. Don't leave them mislabeled.

**RESOLVED** — the three unused variants were deleted. Nothing downstream consumed them, so no result
changes; recreate them against `t.18`/`t.24`/`t.32` if those K values are ever genuinely wanted.

---

### S1-4 · Topic-prevalence sums add the NA count to the total
`stm_analyses_final.Rmd:184, 200, 216, 232, 248`

```r
summarise(across(everything(), ~ sum(., is.na(.), 0)))
```

`sum()` is variadic — it adds **all** its arguments. `is.na(.)` is a logical vector, which `sum()`
coerces to 0/1. So this computes `sum(gamma) + (number of NAs) + 0`, not a sum with NAs removed. The
trailing `0` does nothing.

Every topic-prevalence proportion computed in this file is inflated by the count of missing values in
that group. If `gamma` has no NAs the result is coincidentally correct — which is likely why it went
unnoticed — but the code does not express that assumption, and it is fragile to it changing.

**Recommendation** — `~ sum(.x, na.rm = TRUE)`. If NAs are genuinely impossible here, assert it
(`stopifnot(!anyNA(gamma))`) rather than relying on it silently.

**RESOLVED** — the five blocks now use `summarise(gamma = sum(gamma, na.rm = TRUE))`. Whether any
proportion actually moves depends on whether `gamma` contains NAs, which the re-fit will show; either
way the code no longer depends on an unstated assumption.

---

### S1-5 · Proportion divisor contradicts the recorded corpus size
`stm_analyses_final.Rmd:185, 201, 217, 233, 249`

```r
mutate(proportion = (gamma / 8120) * 100)
```

`stm_models_final.rmd:59` records the corpus as **8210** documents, and this same file labels a plot
`"Topic Proportions By Document (n=8210)"` at L414. The divisor is `8120` — the same digits
transposed. One of the two is wrong; a transposition typo is the more likely explanation.

**CONFIRMED.** Loading the corpus and checking `length(documents)` returns **8210**. The divisor
`8120` is wrong. Every topic-prevalence proportion in these five plots is overstated by a factor of
8210/8120 — approximately **1.1%** relative.

**Recommendation** — never hardcode N. Derive it:

```r
n_docs <- n_distinct(tidy_gamma$document)
mutate(proportion = (gamma / n_docs) * 100)
```

**RESOLVED** — the divisor is now `n_documents <- length(documents)`, asserted equal to 8210. Every
proportion in these five plots moves by a factor of 8210/8120, roughly **1.1% downward**.

**Related, same file:** `stm_models_final.rmd` recorded `#corpus now has 8210 documents, 12440 words`.
The document count is right; the corpus actually holds **1,254** vocabulary terms. **RESOLVED** — the
comment is replaced by code that prints the real dimensions, so it cannot go stale again.

---

### S1-6 · Every non-`Female` gender value becomes `"M"`
`preprocess_data.rmd:221`

```r
mutate(gender = ifelse(gender %in% c('Female','FEMALE'), 'F', 'M'))
```

**CONFIRMED, and materially worse than described. This is the most serious finding in the review.**

The three institutions do not encode gender the same way:

| Institution | Values | n | Recoded to |
|---|---|---|---|
| WGU | `Female` | 7,632 | `F` ✓ |
| | `Male` | 5,556 | `M` ✓ |
| | `NA` | 8 | `M` |
| Excelsior | `FEMALE` | 4,210 | `F` ✓ |
| | `MALE` | 6,170 | `M` ✓ |
| **Albany** | **`F`** | **2,088** | **`M`** ✗ |
| | `M` | 1,853 | `M` ✓ |

**Albany encodes gender as single letters.** `"F"` is not in `c("Female", "FEMALE")`, so the
unconditional `else` branch sends it to `"M"`.

**Every woman at the University at Albany — 2,088 students, 53% of that institution's sample — is
recoded as male.** They are not dropped or flagged; they are silently relabelled and then modelled as
men.

`gender` is a prevalence covariate in every model, the content covariate in the `stm.c.*` family, and
half of the `gender*s(age)` interaction. It is also the covariate behind the `cov.value1 = "F",
cov.value2 = "M"` contrast plotted as "Effect of Gender". Every gender result in this analysis is
computed on data where one institution's women are labelled men.

**Recommendation** — enumerate every encoding actually present, and fail loudly on anything else:

```r
mutate(gender = case_when(
  gender %in% c("Female", "FEMALE", "F") ~ "F",
  gender %in% c("Male",   "MALE",   "M") ~ "M",
  .default = NA_character_
))
stopifnot(!anyNA(gender))  # fail rather than silently reassign
```

**RESOLVED** in `R/covariate_levels.R`, and the effect measured on the real data:

| Institution | n | Recorded female before | After | Reclassified |
|---|---|---|---|---|
| WGU | 13,188 | 7,632 | 7,632 | 0 |
| Excelsior | 10,380 | 4,210 | 4,210 | 0 |
| **Albany** | 3,941 | **0** | **2,088** | **2,088** |

The fix is surgical — WGU and Excelsior are untouched. Albany goes from zero recorded women to 2,088.

**These counts are for the raw institution files. The effect on the modelling sample is much
smaller**, and the distinction matters for judging how far published results move. Most Albany rows
never reach the models: they are dropped by the essay-length filter, the contaminant list, or the
covariate join. After running the corrected pipeline, `stm_data_final.csv` holds 8,210 documents:

| Institution | n | F | M |
|---|---:|---:|---:|
| WGU | 6,175 | 3,573 | 2,602 |
| Excelsior | 1,817 | 705 | 1,112 |
| **Albany** | **218** | **134** | **84** |
| **Total** | **8,210** | **4,412** | **3,798** |

So the correction moves **134 students** from `M` to `F` in the data the models actually see — 1.6% of
the corpus — not 2,088. That is still a real change to the gender covariate in every model, and it
still needs a re-fit, but it is a small shift rather than a wholesale one. Cite the 134 figure when
describing the impact on results, and the 2,088 figure only when describing the defect itself.

**Recommendation** — enumerate the mapping and fail loudly on anything unexpected:

```r
mutate(gender = case_when(
  gender %in% c("Female", "FEMALE") ~ "F",
  gender %in% c("Male",   "MALE")   ~ "M",
  .default = NA_character_
))
# then decide explicitly what happens to the NAs, and record how many there were
```

**Verify:** `count(wg_covariates, gender)` on each institution before recoding — this reveals whether
any third category actually exists in the data. _Needs runtime confirmation._

---

### S1-7 · Race recoding is order-dependent and institution-inconsistent
`preprocess_data.rmd:222-228`, consumed at `stm_analyses_final.Rmd:530, 539, 548`

```r
mutate(race = str_remove(race, ' non-Hispanic')) %>%
mutate(across(race, str_replace, 'Hispanic/Latino', 'Latinx')) %>%
mutate(race = str_replace(race, 'Hispanic', 'Latinx')) %>%
mutate(race = str_replace(race, 'Black,', 'Black or African American')) %>%
```

Two problems.

**Order dependence.** L223 and L224 both target "Hispanic"; L224 only behaves correctly because L223
already consumed the `Hispanic/Latino` case. The chain is correct only in this exact sequence, and
nothing records that.

**The `'Black,'` pattern requires a trailing comma.** For Albany, `separate(..., sep = ',',
extra = 'drop')` at L214 has already truncated the value at the first comma — so the comma is gone
and this replacement cannot match. WGU and Excelsior use different source columns (`ethnicity2`,
`ethnicity`) and don't go through that `separate()`. The result is plausibly `"Black"` for some
institutions and `"Black or African American"` for others: two factor levels for one group,
splitting the sample.

This connects directly to `stm_analyses_final.Rmd:530`, which contrasts `cov.value1 = "Black"`. If
the recode succeeded, that level doesn't exist and the contrast is invalid; if it failed, it works
but only for a subset of institutions.

**CONFIRMED.** Running the recoding chain over each institution's distinct values gives these level
sets:

| Level after recoding | Present for |
|---|---|
| American Indian or Alaska Native | WG, EC |
| Asian | WG, EC, Alb |
| **Black** | **WG only** |
| **Black or African American** | **EC, Alb** |
| Latinx | WG, EC, Alb |
| **Native Hawaiian** | **WG only** |
| **Native Hawaiian or Other Pacific Islander** | **EC only** |
| Two or More Races | WG, EC, Alb |
| White | WG, EC, Alb |

**Two groups are split across two labels by institution.** Black students appear as `"Black"` if they
attend WGU and `"Black or African American"` otherwise. The same split affects Native Hawaiian
students.

The consequence for `stm_analyses_final.Rmd`: `cov.value1 = "Black"` **does** match a level, so the
plot renders without error — but it contrasts *WGU Black students only* against White students from
all three institutions. Institution is confounded with race in that comparison, and nothing on the
plot says so.

The `str_replace(race, "Black,", ...)` line that was presumably meant to prevent this **never fires
for any institution**: WGU's value is `"Black"` with no comma, Excelsior's is already
`"Black or African American"`, and Albany's comma is stripped by the upstream `separate()` before the
replacement runs. It is dead code that looks like a fix.

**Recommendation** — apply one explicit lookup after all institution-specific parsing, and assert the
resulting level set so a new encoding fails loudly instead of silently adding a level:

```r
stopifnot(all(unique(race) %in% RACE_LEVELS))
```

**RESOLVED** in `R/covariate_levels.R`, and the effect measured on the real data:

| Institution | Level merged | n |
|---|---|---|
| WGU | `Black` → `Black or African American` | **1,442** |
| WGU | `Native Hawaiian` → `Native Hawaiian or Other Pacific Islander` | **87** |
| Excelsior | no change | — |
| Albany | no change | — |

Distinct race levels drop from **9 to 7**. The 1,442 WGU Black students previously sat in a level of
their own, separate from Black students at the other two institutions — which is what made the
`cov.value1 = "Black"` contrast a WGU-only comparison.

Merging changes the composition of the race covariate and therefore every race result. The three race
contrast plots should be re-checked afterwards.

**Re-checked after running the pipeline.** The merge broke `stm_analyses_final.Rmd:534`, which is now
also fixed. The modelling sample carries seven race levels:

| Level | n |
|---|---:|
| White | 6,004 |
| Black or African American | 1,012 |
| Latinx | 472 |
| Two or More Races | 334 |
| Asian | 263 |
| American Indian or Alaska Native | 69 |
| Native Hawaiian or Other Pacific Islander | 56 |

`"Black"` is no longer among them. The contrast at L534 passed that literal to `estimateEffect()`, so
after harmonisation it referenced a level that does not exist — the fix to the recoding broke the plot
that consumed it. It now passes `"Black or African American"`, and a `stopifnot()` above the block
checks every contrast value against `levels(meta$race)` so this cannot recur silently.

---

### S1-8 · QA check does not perform the check its comment describes
`preprocess_data.rmd:270-272`

```r
# text with < 50 distinct vals
sum(n_distinct(clean_data$text) < 50)
```

`n_distinct()` on a column returns a **single scalar** (the number of distinct essays, ~8,000).
Comparing that to 50 gives one logical; `sum()` of one logical is 0 or 1.

**CONFIRMED, with a small correction to the original wording.** The expression does not return `0`
unconditionally — it returns `1` when the corpus holds fewer than 50 distinct essays and `0`
otherwise. On this corpus it is `0`. Either way it never counts short essays, so it cannot detect the
condition its comment describes, and would report "pass" if every essay were a single character.

The intended check — that no essay has fewer than 50 unique words — is already enforced upstream at
L136-138 inside `cleaner()`. This block is dead code presenting as verification, which is worse than
no check: it reads like passing evidence.

**RESOLVED** — replaced with a real count. See S1-9 for why it reports rather than asserts.

---

### S1-9 · The junk-submission filter can be defeated by boilerplate padding
`preprocess_data.rmd:161-168`

Found while running the pipeline for the first time, when the `stopifnot()` added under S1-8 failed.

**Purpose of this check, stated by the project owner:** the 50-*unique*-word floor exists to catch
junk entries — students who submitted repeated filler or near-nothing rather than a genuine essay.
Counting unique words (not total length) is what makes it a repetition/substance detector rather than
a length check.

**The gap.** `cleaner()` counts unique words and drops short essays at L161-162 — but **four more
substitutions run afterwards**, stripping essay-prompt boilerplate and instructional text:

```r
mutate(count = lengths(map(strsplit(text, split = " "), unique))) %>%
filter(!count < 50) %>%          # <- floor enforced HERE, against boilerplate-inflated text
select(!count) %>%
mutate(text = str_replace_all(text, pattern17, " ")) %>%
filter(!str_detect(text, pattern = pattern18)) %>%
mutate(text = str_replace_all(text, pattern19, "")) %>%
mutate(text = str_replace_all(text, pattern20, "")) %>%
mutate(text = str_replace_all(text, pattern21, ""))   # <- boilerplate removed HERE, after the check
```

Prompt/instructional boilerplate is lexically varied, so it can push an essay's unique-word count
*above* 50 at check time even when the student's own contribution is minimal. The check runs before
that boilerplate is stripped, so an essay can be counted, and cleared, on the strength of text that
isn't the student's — the exact failure mode the filter exists to catch.

**CONFIRMED against the real corpus.** 3 of 8,265 essays finish below the floor in the final text:

| Mid-chain unique words (what the check saw) | Final unique words | Words removed by patterns 17/19/20/21 |
|---:|---:|---:|
| 52 | 38 | 14 |
| 67 | 48 | 19 |
| 50 | 48 | 2 |

The boilerplate contribution here is modest (4–19 words), not the dramatic "essay is mostly prompt
text" scenario the mechanism suggests is possible — but it is real, and in the same direction the
concern predicts.

**Checked against the hand-curated contamination list (`remove.csv`).** 2 of the 3 are already
flagged there by the manual visual-inspection process in `contaminant_removal_final.Rmd` — so they
are already excluded from modelling by a different mechanism. **1 of the 3 is not caught by any
existing process** and currently sits in the modelling corpus.

**DOCUMENTED, NOT FIXED.** Moving the count to the end of the chain would drop the 1 uncaught essay
(the other 2 are already excluded via `remove.csv`) and change the corpus from 8,210 documents — a
modelling decision, not a QA fix, and one that would invalidate the `n_documents == 8210` assertion
and every published proportion. The QA block reports the count and the minimum instead of asserting
zero.

### Decision — 2026-08-27: the essay stays, the corpus remains 8,210

**Decided by the project owner.** The one uncaught essay is retained. It holds 48 unique words
against a 50-word floor, and is 0.012% of an 8,210-document corpus; correcting for it would
invalidate the `n_documents == 8210` assertion and every published proportion, and require a re-fit,
to remove two words' worth of shortfall from one document.

Options considered and rejected:

- **Move the unique-word count to the end of `cleaner()`.** The principled fix — it makes the filter
  measure what it claims to measure — but it changes the corpus and forces a re-fit.
- **Add the `doc_id` to `remove.csv`.** Same corpus effect and same re-fit, and it would blur the
  provenance of that file: `remove.csv` records human visual inspection, not mechanical detection.

**If a re-fit is ever undertaken for another reason, fold the first option in then.** Until that
happens the QA block reports rather than asserts, which is the correct behaviour: a non-zero count
here is expected, not a failure, and this section records why.

---

### S1-10 · Essay join on `doc_id` alone matches across institutions
`stm_analyses_final.Rmd`

```r
original <- left_join(filter_id, preclean, by = "doc_id")
```

**`doc_id` is unique only within an institution.** The three sources reuse the same numeric ids, so
joining on `doc_id` alone matches a student at one institution to essays at another.

Measured on the real data:

| | rows |
|---|---:|
| corpus (`meta`) | 8,210 |
| join by `doc_id` only, as written | **10,224** |
| join by `doc_id` + `institution` | 8,210 |
| spurious rows | **2,014** |

**All 2,014 extra rows pair a student with another institution's essay text.** The result is also
row-misaligned with the model, which matters because `findThoughts()` indexes `texts` *positionally*
against document number — so exemplar lookups would return unrelated essays, not merely extra ones.

**No published result is affected.** `original` is assigned in this notebook and never read — verified
by reference check. But the comment above it advertises the object "for use in topic exemplar review",
which is precisely the use that would have been wrong, and `essay_examples_final.Rmd` already joins on
both keys. The inconsistency between the two files is what makes this a trap rather than dead weight.

**RESOLVED** — joins on both keys, with `stopifnot(nrow(original) == nrow(meta))` so any future
regression fails loudly rather than silently inflating. Note that the per-institution joins in
`preprocess_data.rmd` are correct as written: they join one institution's covariates to that same
institution's essays, where `doc_id` *is* unique.

Surfaced by a dplyr many-to-many warning when the notebook was first run — not by inspection.

---

## S2 — Broken references

These prevent execution. Fixing them changes no working behavior.

> **RESOLVED** on branch `fix/broken-model-references`. All six are fixed and every model reference
> and `load()` filename now resolves. Note that `lintr` cannot catch this class of defect at all —
> `object_usage_linter` is blind to names introduced by `load()` — so the fix is verified by a
> dedicated cross-file check that builds the set of names `stm_models_final.Rmd` actually creates and
> confirms each downstream reference against it. The resolution chosen for each site is recorded below.

### S2-1 · Loads two `.Rda` files that are never written
`essay_examples_final.Rmd:46, 50`

| Loaded | Actually saved by `stm_models_final.rmd` |
|---|---|
| `content.prevalence.models.6_32.Rda` | `optimized.prevalence.content.models.6_32.Rda` (L142) |
| `basic.stm.models.6_32.Rda` | `stm.prevalence.content.models.6_32.Rda` (L186) |

Neither filename exists. Both `load()` calls error.

### S2-2 · `stm.model12` — missing dot
`essay_examples_final.Rmd:121` · The object created at `stm_models_final.rmd:92` is `stm.model.12`.

### S2-3 · `stm.model.k*` objects are never created anywhere
`essay_examples_final.Rmd:204, 259-263` · `stm_analyses_final.Rmd:229, 285, 293, 588`

Nine references across two files to `stm.model.k6` / `k12` / `k18` / `k24` / `k32`. No such objects
are assigned in any file. The nearest real families are `stm.pc.*` (prevalence + content,
`stm_models_final.rmd:159-177`) and `stm.p.*` (prevalence only, L192-205).

**This one needed a decision, not just a rename**, and the sites do not all resolve the same way.
Each was settled from surrounding evidence rather than by pattern-matching the name:

| Site | Resolved to | Evidence |
|---|---|---|
| `stm_analyses_final.Rmd` — `tidy(...)` for plot `m4` | `stm.pc.12` | The plot's own subtitle reads `"Prevalence & Content: stm()"`, which names the `stm.pc.*` family exactly |
| `stm_analyses_final.Rmd` — `sageLabels()` | `stm.pc.12` | Sits in a four-call enumeration of the model families; `stm.pc.*` is the one missing |
| `stm_analyses_final.Rmd` — commented `labelTopics()` | `stm.pc.12` | Comment says "printing lift", and lift is what a content-formula model prints |
| `stm_analyses_final.Rmd` — `plot_age(age.pred, ...)` | **`stm.p.12`** | Differs from the rest: `age.pred` was built with `stmobj = stm.p.12`, and `plot.estimateEffect` must receive the same model the effect was estimated from. Passing `stm.pc.12` here would silently misrender every age effect |
| `essay_examples_final.Rmd` — `exemplars()`, `top.essays()` (6 calls) | `stm.pc.6`…`stm.pc.32` | Prose above the block: "the essays extracted here come from the basic stm models — which include prevalence and content formula" |

The fourth row is the trap: four sites share a name, and one of them needs a different object than the
other three.

### S2-4 · `model = interact` — undefined object
`stm_analyses_final.Rmd:621, 625, 634, 638, 647, 651` · The object is `interact.signf` (L600). Six
call sites.

### S2-5 · `CE6_28` referenced, object is `CE6_32`
`stm_analyses_final.Rmd:133` · Inside a commented-out `save()`. Harmless today; would fail if
uncommented. Symptom of a K-range change (6–28 → 6–32) that wasn't propagated.

### S2-6 · Empty argument passed via a doubled comma
`stm_analyses_final.Rmd:497` (was L518 pre-style-pass)

```r
plot(stm.c.12, "perspectives", topics = c(12), n = 25, text.cex = 1, , main = "...")
```

Note `1, , main`. R parses this — an empty argument is syntactically legal and becomes the *missing*
value — so it survives `parse()` and was not caught by any linter. It reaches `plot.STM()`'s `...`,
where it errors as soon as anything forces it.

Found while verifying the style pass; only the last of the nine `"perspectives"` calls in that block
has it, so it looks like a stray keystroke rather than intent.

**Recommendation** — delete the extra comma. Mechanical and safe, but listed under S2 rather than S4
because it is a defect rather than a style choice.

---

### S2-7 · `topics` passed positionally into `n` in two `plot.STM()` calls
`stm_analyses_final.Rmd` — the two `"hist"` plots

```r
plot(stm.model.12, "hist", c(1:12), main = "Frequency Distribution of Topics: ...")
```

`plot.STM()`'s signature is `(x, type, n, topics, ...)`. The **third positional argument is `n`**, not
`topics` — so `c(1:12)` was passed as `n`, and `labelTopics()` then evaluated `if (n < 1)` against a
length-12 vector.

Under R < 4.2 that was a warning and R silently used the first element; **from R 4.2 it is an error**,
which is how this surfaced. The plots were therefore never doing what they appeared to do even when
they "worked" — they used `n = 1`.

**RESOLVED** — `topics` is now named in both calls. Found by running the notebook, not by inspection:
every reference resolved, so no static check would have caught it.

---

### S2-8 · A `"perspectives"` plot that could not have produced its own title
`stm_analyses_final.Rmd`

```r
plot(stm.p.12, "perspectives", topics = (1:12), n = 12, text.cex = 1,
     main = "Gender-Based Vocabulary: Test Anxiety")
```

Wrong three independent ways:

- **`stm.p.12` has no content covariate.** Verified against the fitted object: one beta group, no
  per-gender vocabulary. A perspectives plot on it cannot show gender-based word use at all.
- **`topics = 1:12` is invalid for this plot type**, which contrasts one or two topics. This is what
  made it error rather than merely mislead.
- **The title names one topic** ("Test Anxiety", topic 3) while twelve were passed.

**RESOLVED — removed.** The block immediately below does this correctly, using `stm.c.12` (the content
model), one topic per plot, and already includes topic 3. Nothing was lost.

---

### S2-9 · `Text.cex` is not a graphical parameter
`stm_analyses_final.Rmd` — the first-generation effect plot

`Text.cex = .25` (capital T) is not a parameter of anything in the call chain. It was passed through
`...` into base graphics, ignored, and warned about six times per plot. Every sibling
`estimateEffect` plot uses `cex = .25`.

**RESOLVED** — corrected to `cex`. The notebook now runs warning-free.

---

## S3 — Reproducibility

### S3-1 · Ten models fitted without a seed
`stm_models_final.rmd:192-205` (`stm.p.*`), `216-229` (`stm.c.*`)

Every other model family in the file passes an explicit `seed=` (L86, L117-133, L161-177). These ten
don't. `stm()` with `init.type = "Spectral"` plus EM is not deterministic without one, so these
models cannot be regenerated.

This matters more than the count suggests: **`stm.p.12` is the model that most of
`stm_analyses_final.Rmd` is built on** — the covariate effects (L440-446), the perspective plots, the
topic network (L665), and the hand-assigned topic labels all derive from it. The labels
("Test Anxiety", "Time Management", …) were assigned by inspecting a specific fitted model that
cannot now be reproduced exactly.

**Recommendation** — add seeds, then re-fit and re-verify that the K=12 topics still match the
assigned labels before reusing them. Treat label re-validation as part of the fix, not an optional
follow-up.

**RESOLVED.** `stm.p.12` (seed 784658) and `stm.c.12` (seed 784663) now pass explicit seeds, with
seeds reserved for the other K values in the retained sweep code. Because the previous run was
unseeded, its exact fit was unrecoverable regardless — so adding seeds cost nothing and makes the
re-fit that carries every correction reproducible.

Label re-validation remains open and is the user's call: see S5-1.

### S3-2 · No `set.seed()` before any random forest
`stm.rforestmodels.final.Rmd:141-211, 271`

Thirteen `randomForest()` calls, no seed. The variance-explained figures recorded in comments
(`# max var explained 8.38`, etc.) and in the prose at L136 and L251 are not reproducible. With
`ntree = 1000` the run-to-run variation is small but nonzero — and several reported values are near
zero or negative (`-3.2`, `-1.54`, `-1.04`, `-3.08`), where the sign itself may not be stable.

**RESOLVED** — `fit_topic_forests()` seeds each model as `seed + topic`, so every fit is
independently reproducible. **This changes all reported variance-explained figures**: the originals
came from unseeded runs that cannot be recovered.

### S3-6 · `estimateEffect()` is unseeded, and it is stochastic
`stm_analyses_final.Rmd` — every covariate effect

Found while building `results/RESULTS.md`. `estimateEffect(uncertainty = "Global")` draws posterior
samples of the topic proportions, and `summary.estimateEffect()` — which `tidy()` calls — simulates
500 further draws per sample to get standard errors. Neither was seeded, so no covariate result in
this analysis could be regenerated.

**Measured across two builds of the results document.** One topic's gender F statistic came out at
150 and at 181; term-level p-values moved by up to 0.016, changing how many terms clear an
uncorrected 0.05 (8 versus 7 for race, 47 versus 49 for age).

This is the same defect as S3-1 in a different place: a stochastic procedure reported as if it were
deterministic. It is worse in one respect — the model fits at least produced a saved artifact,
whereas these estimates are recomputed on every run.

**RESOLVED** — `set.seed(20220527)` before the estimation in both
`stm_analyses_final.Rmd` and `scripts/build_results.R`, verified: two runs under the seed produce
bit-identical joint tests and term-level p-values. The joint tests in `R/multiple_comparisons.R`
pool the posterior draws analytically rather than by simulation, so they are additionally stable
against the `summary()` layer.

---

### S3-3 · Frequency thresholds hardcoded as absolute counts
`stm_models_final.rmd:57`

```r
partition <- prepDocuments(..., lower.thresh = 82, upper.thresh = 8128)
```

The prose at L55 describes these as "words that occur in <= 1% of docs and >= 99% of docs". They are
absolute document counts that happen to equal ~1% and ~99% of 8,210. They stop meaning that the
moment the corpus size changes — which it does every time `remove.csv` is regenerated by the
contaminant-removal loop.

**Recommendation** — derive them: `n <- length(processed$documents); lower.thresh = ceiling(0.01 * n)`.

**DELIBERATELY NOT CHANGED.** Deriving them would alter the vocabulary and therefore every fitted
model — a larger change than the correctness batch warrants, and one that would confound attribution
when the models are re-fitted for S1-6/S1-7. The code now prints what percentages 82 and 8128 actually
represent, so the drift is visible. Converting them is a separate decision.

**Measured on the re-fit: the drift has not occurred.** The corrected corpus still holds 8,210
documents, so the reported percentages are 1.00% and 99.00% — exactly what the prose claims. The
concern was that these values *would* drift silently, not that they already had; that remains true
of any future change to `remove.csv` or the cleaning filters, and the printed report will now catch
it. Corpus after `prepDocuments()`: **8,210 documents, 1,254 vocabulary terms** (11,186 of 12,440
terms dropped by the frequency filter).

This also settles a stale comment noted under S1-5: the old text claimed "8210 documents, 12440
words". 12,440 was the vocabulary *before* frequency filtering; the corpus the models actually see
holds 1,254 terms.

### S3-4 · Results recorded in comments rather than captured
`stm.rforestmodels.final.Rmd:143, 149, 155, 161, 167, 173, 180, 187, 193, 199, 205, 211`

```r
var.t1.12 <- summary(rf.t1.12$rsq * 100)  # max var explained 8.38
```

The `var.t*` objects are assigned and never used; the actual findings live in trailing comments. They
can't be sorted, plotted, tabled, or diffed against a re-run, and nothing keeps them in sync with the
code.

**Recommendation** — collect into a data frame and print it. Falls out naturally from the Phase 4
`map()` rewrite.

**RESOLVED** — `fit_topic_forests()` returns a tibble of `topic`, `n_obs`, `var_explained` and the
fitted model, which the notebook prints sorted. No result change; the numbers were always computed,
just never captured.

---

### S3-5 · `vip` has been archived from CRAN
`stm.rforestmodels.final.Rmd` — `library(vip)` plus 13 `vip()` calls

Found while building the `renv` environment. `vip` is absent from the current CRAN index:

```
vip in current CRAN index: FALSE
archived tarballs found: 14
most recent archived: vip_0.4.6.tar.gz
```

`install.packages("vip")` therefore fails for anyone attempting to reproduce this analysis —
including the original author on a new machine. This is a reproducibility defect in the pipeline, not
a local environment quirk.

The saving grace is that `vip()` computes nothing for a `randomForest` object: it reads
`randomForest::importance()` and draws it. The values are available without the package.

**RESOLVED** — replaced with a ggplot2 rendering in `R/rf_topic_importance.R`, reading the same
`randomForest::importance()` values. The dependency is removed rather than pinned, so nothing has to
be fetched from the CRAN archive. Figures change in appearance; the numbers do not.

`tuneR` was removed at the same time — an audio-processing package, declared but never called,
almost certainly a mistaken autocomplete for `tune`.

---

## S4 — Style, deprecation, duplication

Mechanical. Safe for the formatting and extraction passes.

**Status after the style pass** (branch `style/tidyverse-style-pass`): lint findings went 2312 → 662.
Resolved there: all whitespace/formatting classes, the four deprecated calls, the 13 direct
`plot.STM()` invocations, the `T`/`F` symbols, and the two YAML header typos.

Still open, and why:

| Remaining | Count | Held because |
|---|---|---|
| `object_name_linter` (dot.case) | 133 | `save()`/`load()` couple object names across files — see below |
| `pipe_consistency_linter` | 239 | `%>%` vs `\|>` is a one-time convention decision; pairs naturally with removing `%<>%` |
| `object_usage_linter` | 172 → **6 real** | 166 are noise: the analysis packages are not installed on the linting machine, so lintr cannot resolve `findThoughts`, `make.dt`, or any dplyr NSE variable and reports them as undefined. The 6 genuine findings are the dead `index`/`examples` assignments in the three `exemplars()` copies, removed by the Phase 4 extraction. |
| `line_length_linter` | 90 | Mostly the 21 regex patterns and the repeated 12-element label vector; resolved by the Phase 4 extraction |
| `commented_code_linter` | 14 | Judgment call per site — some are documentation, some are dead code |
| `assignment_linter` | 10 | The `%<>%` sites; decide alongside pipe consistency |
| `undesirable_function_linter` | 4 | The three unrestored `setwd()` calls in `exemplars()` plus one more; fixed by the Phase 4 extraction |

### Deprecated / superseded

| Call | Locations | Replacement |
|---|---|---|
| `add_rownames()` | `stm_analyses_final.Rmd:299, 306, 313, 320` | `tibble::rownames_to_column()` — deprecated since dplyr 1.0 |
| `across(race, str_replace, 'x', 'y')` | `preprocess_data.rmd:223` | Passing `...` to `across()` is deprecated in dplyr 1.1; use `across(race, \(x) str_replace(x, "x", "y"))` |
| `geom_histogram(stat = "identity")` | `stm_analyses_final.Rmd:190, 206, 222, 238, 254` | `geom_col()` |
| `mutate_if(is.numeric, round, 2)` | `stm.rforestmodels.final.Rmd:92` | `mutate(across(where(is.numeric), \(x) round(x, 2)))` |

### Calling S3 methods directly
`plot.STM(...)` at `stm_analyses_final.Rmd:337, 339, 343, 345, 422, 424, 499, 510-518` — 13 call
sites. Call the generic, `plot()`. Directly invoking a method bypasses dispatch and breaks if the
package reorganizes its S3 registration.

### `setwd()` inside a function, with no restore
`essay_examples_final.Rmd:103, 145, 185`

```r
setwd(file.path(mainDir, fname, paste0('Passages_stm.model', number)))
```

The function never restores the working directory. Every subsequent chunk in the notebook runs
somewhere else, and a mid-loop error strands the session in a subdirectory. Each of the three
`exemplars()` definitions repeats it.

**Fix** — build full paths with `file.path()` and pass them to the output device; no directory change
is needed at all. If one genuinely were, `withr::with_dir()` restores on exit.

### Loop indexes positions when it means values
`essay_examples_final.Rmd:105, 147, 187, 236`

```r
for (i in seq_along(topic)) { ... findThoughts(model, topics = i, ...) }
```

`i` is a **position**, then used as a **topic number**. Correct only because every current caller
passes `c(1:K)`, where position equals value. `exemplars(model, 6, c(3, 7))` would silently analyze
topics 1 and 2 while labeling the output "Topic 1"/"Topic 2". Use `for (i in topic)`.

### Shadowing base functions
`essay_examples_final.Rmd:233` assigns `table <- make.dt(...)`, masking `base::table()`. Then L248
calls `table()` on a data frame of essay text:

```r
raw.essays <- inner_join(...) %>% select(text) %>% table()
```

Given the masked name and that the result feeds `write.table()`, this is very likely not the intended
operation — worth checking whether it was meant to be `as.data.frame()` or nothing at all.
_Needs runtime confirmation._

### Dead assignments
- `index <- findThoughts(...)` — `essay_examples_final.Rmd:110, 152, 192`. A second call identical to
  the line above it, discarded. Also doubles the work.
- `examples <- plotQuote(...)` — L111, 153, 193. Assigned, never used.
- Bare object names as statements — `stm.rforestmodels.final.Rmd:46-50`. Five no-ops.
- `filter %>%` with no arguments — `preprocess_data.rmd:95, 118`. Pipes the frame through `filter(.)`,
  which returns it unchanged.
- `var.t*` — see S3-4.

### Naming — and why it cannot be fixed in a style pass
Three conventions coexist: dot.case (`stm.model.6`, `remove.id2`), snake_case (`clean_data`,
`first.gen.levels` — itself mixed), and inconsistent numbering (`vip.1` vs `vip2`…`vip12`,
`essay_examples_final.Rmd`). The Tidyverse Style Guide specifies snake_case throughout. Dot.case is
actively worth removing in R because it collides with S3 method dispatch naming.

**But renaming is not a behavior-preserving change here**, which is not obvious and is the reason
`object_name_linter`'s 133 findings were left open by the style pass.

`save()` serializes objects *by name*, and `load()` restores those exact names into the global
environment. So `stm.p.12` is not a local variable — it is a contract between files, mediated
through a `.Rda` on disk:

```r
# stm_models_final.rmd:209  — writes the name
save(stm.p.6, stm.p.12, stm.p.18, stm.p.24, stm.p.32,
     file = "stm.prevalence.models.6_32.Rda")

# stm.rforestmodels.final.Rmd:42  — reads the name back
load("stm.prevalence.models.6_32.Rda")
```

Rename `stm.p.12` → `stm_p_12` in the fitting notebook and the `.Rda` files already on disk still
contain `stm.p.12`. Every downstream `load()` would restore the old name while the code referenced
the new one — a failure that appears only at runtime, in a different file from the edit.

Making the rename real requires re-fitting and re-saving every model. **Phase 5 forces that anyway**
to fix the missing seeds (S3-1), so the rename belongs there, bundled with the re-fit — not in a
formatting pass that is supposed to change nothing.

### Assignment pipe
`%<>%` is used throughout `preprocess_data.rmd` (L169, 175, 180, 188, 196, 202, 210) and
`stm.rforestmodels.final.Rmd` (L91, 262, 267). The style guide favors explicit `x <- x |> ...`.
Pick one convention and apply it uniformly.

### Unused dependencies
- `httr` — `preprocess_data.rmd:28`, `essay_examples_final.Rmd:28`. No HTTP call anywhere.
- `tuneR` — `stm.rforestmodels.final.Rmd:30`. An **audio processing** package. Almost certainly a
  mistaken autocomplete for `tune`; nothing from it is called.

### YAML header defects
- `preprocess_data.rmd:4` — `data: "05/27/22"` should be `date:`.
- `essay_examples_final.Rmd:4` — `date:: '05/17/22'` has a doubled colon.
- All six files carry an identical 14-line `output:` block → extract to a shared `_output.yml`.

### File extension inconsistency
`preprocess_data.rmd` and `stm_models_final.rmd` are lowercase; the other four are `.Rmd`.

---

## R — Reproducibility of the pipeline as a whole

The most serious class of finding, and the last to surface: **the committed analysis cannot be
regenerated from the committed code.** Three files are read that nothing in the repository produces.

### R-1 · The write that three notebooks depend on was commented out
`preprocess_data.rmd:107`

```r
# write_csv(preclean_text, 'preclean_text.csv') # write to file for analyses.Rmd
```

`preclean_text.csv` is read by `contaminant_removal_final.Rmd`, `essay_examples_final.Rmd` and
`stm_analyses_final.Rmd`. With the only write disabled, none of them runs from a clean checkout.

**RESOLVED** — re-enabled. `preclean_text` is computed either way, so persisting it changes no value
used downstream; it only stops the pipeline depending on a file nothing produces.

### R-2 · `contaminant_removal_final.Rmd` depends on an artifact nothing produces
`contaminant_removal_final.Rmd:36` — `load("topic.prob6_28.Rdata")`

That file is the output of an early K = 6–28 modelling run. It is not saved by `stm_models_final.Rmd`
and is not in the repository. The notebook cannot run.

Its sole output is `remove.csv`, the contaminant exclusion list that `preprocess_data.rmd` reads. The
dependency is also circular: `preprocess` needs `remove.csv` → produced by `contaminant_removal` →
which needs `preclean_text.csv` → written by `preprocess`.

**`remove.csv` is effectively irreplaceable.** The selections in this notebook are hand-picked row
indices (`slice(c(1, 5, 16, 17, ...))`) with no recorded criterion beyond "visual inspection", and
those indices are meaningless against any other model fit. If `remove.csv` is lost, the exclusion list
cannot be reconstructed — it would require re-fitting an early model and re-making every judgement by
hand. It should be treated as a primary input and backed up accordingly, not as a derived artifact.

**MITIGATED, not resolved** — the notebook now fails immediately with an explanation rather than a
cryptic missing-file error, and the constraint is documented at the top. The underlying problem
(unreproducible exclusion list) cannot be fixed after the fact.

### R-3 · Fitted models are absent and expensive to regenerate

None of the five model `.Rda` files is in the repository (correctly — they contain per-document topic
proportions and the covariate design matrix). Regenerating all five is measured in hours:
`stm_models_final.Rmd:80` records `manyTopics` alone at **2286 seconds**, and that is one of five
families.

For verification purposes only `stm.p.*` and `stm.pc.*` are needed — they drive
`stm_analyses_final.Rmd`, the random forest section, and the exemplars. The `manyTopics` and
`selectModel` families feed comparison plots only.

---

## Findings surfaced during extraction

Three defects that static reading missed. All three were found by writing tests against the extracted
helpers — none is visible without either running the code or comparing copies mechanically.

### X-1 · Topic labels disagree with themselves inside one document
`stm_analyses_final.Rmd` — the canonical 12-element vector vs. nine single-topic plot titles

The vector appeared verbatim seven times and all seven were byte-identical. But nine *separate* plot
titles of the form `main = "Topic N = <label>"` name the same topics, and three of them disagree:

| Topic | Plot title | Canonical vector |
|---|---|---|
| 7 | Transferable Strategies **-** Academic Success | Transferable Strategies **&** Academic Success |
| 9 | Getting Right Getting it Done | Getting **it** Right Getting it Done |
| 11 | **Applying** and Retaining Subject Matter | **Appying** and Retaining Subject Matter |

Topic 11 is the awkward one: the plot title is spelled correctly and **the canonical vector carries a
typo**, so the misspelling is the version that appears in six figures and the topic-correlation
network while the correct spelling appears in one.

**RESOLVED** — the correct spelling won. `TOPIC_LABELS_K12[11]` is now "Applying and Retaining
Subject Matter", with a test pinning it. The three drifted plot titles were not corrected by hand:
all nine perspective titles and the three interaction titles now derive from `topic_labels()` rather
than being retyped, so this class of disagreement cannot recur and a label revision propagates to
every figure automatically. That matters while the labels remain provisional (S5-1). Figure text
changes accordingly; no value does.

### X-2 · Top-essay files were written with a spurious frequency column
`essay_examples_final.Rmd` — inside the former `top.essays()`

```r
raw.essays <- inner_join(...) %>% select(text) %>% table()
write.table(raw.essays, file = essay.filename, sep = "\t", row.names = FALSE, col.names = FALSE)
```

`base::table()` counts occurrences of each distinct essay. Essays are unique, so every count is 1,
and each line was written as:

```
"first essay text"	1
```

— quoted, with a meaningless `1` appended. (The local variable also named `table` did not shadow the
function: R skips non-function bindings when a name is used in call position.) Verified by running
both versions against synthetic essays.

**RESOLVED** — `write_top_essays()` uses `writeLines()`. **This changes the contents of every
top-essay file**, which are described in `essay_examples_final.Rmd` as feeding downstream analysis
and writeup.

### X-3 · One cleaning pattern only works under ICU, not base R
`preprocess_data.rmd` — `pattern14`, now `punctuation_except_hyphen`

```r
"[\\p{P}\\p{S}--[-]]"
```

The `--` is ICU character-class subtraction. `stringr` uses ICU, so the pipeline works. Base R's TRE
engine does not merely warn — it **errors**:

```
invalid regular expression '[\p{P}\p{S}--[-]]', reason 'Invalid character range'
```

Harmless today because every application goes through `str_replace_all()`. It becomes a defect the
moment anyone reaches for `grepl()`, `gsub()`, or `sub()` on this pattern, which is an easy and
invisible mistake to make.

**Documented, not changed** — the constraint is recorded in `R/cleaning_patterns.R` and asserted by a
test, so it cannot be quietly forgotten.

---

## Duplication inventory

Drove the Phase 4 extraction. Ordered by payoff. Every row is now extracted or
deliberately left, with the reason.

| Duplicated construct | Occurrences | Location | Status |
|---|---|---|---|
| `randomForest` + `select` + `na.omit` block | **12** | `stm.rforestmodels.final.Rmd:141-211` | `R/rf_topic_importance.R` |
| `vip()` call | **12** | `stm.rforestmodels.final.Rmd:216-227` | `R/rf_topic_importance.R`, ggplot2 rendering |
| Prevalence formula `~ gender + race + first_gen + s(age) + gender*s(age)` | **15** verbatim | `stm_models_final.rmd` throughout | `PREVALENCE_FORMULA` in `R/model_formulas.R` |
| 12-element `custom.labels` topic vector | **6** verbatim | `stm_analyses_final.Rmd:493, 534, 543, 552, 569, 667` (+ as rename targets `stm.rforestmodels.final.Rmd:263`) | `R/topic_labels.R` |
| `exemplars()` function definition | **3** near-identical | `essay_examples_final.Rmd:91, 133, 173` | `R/exemplars.R` |
| tidy→group→summarise→ggplot prevalence block | **5** | `stm_analyses_final.Rmd:181-259` | `R/topic_prevalence.R` |
| `cbind` + `as.numeric(as.character())` diagnostics block | **5** | `stm_analyses_final.Rmd:112-129` | **Left.** Inside the `eval = FALSE` K-sweep chunk, which is a pair with the commented sweep in `stm_models_final.rmd`. Extracting code that cannot run would obscure the record it exists to keep. Revisit if the sweep is ever restored. |
| 14-column SRL `select()` | **3** | `stm.rforestmodels.final.Rmd:65-85` | `R/srl_features.R` |
| `make.dt()` + `relocate()` block | **5** | `stm.rforestmodels.final.Rmd:114-118` | **Left.** Four of the five built `t.6/18/24/32`, which were never read; they were deleted with the K = 12 narrowing. One occurrence is not duplication. |
| `left_join` topic/SRL block | **5** | `stm.rforestmodels.final.Rmd:127-131` | **Left.** Same cause: reduced to the K = 12 join plus the feedback-view join, which differ in what they join. |
| `kable()` top-words block | **4** | `stm_analyses_final.Rmd:298-324` | `R/topic_word_tables.R` |
| `estimateEffect()` call | **4** | `stm_analyses_final.Rmd:440-446` | `R/covariate_effects.R` |
| Hand-numbered regex globals `pattern1`…`pattern21` | **21** | `preprocess_data.rmd:64-85` | `R/cleaning_patterns.R` |

Three further constructs were extracted that this inventory did not list, all in
`stm_analyses_final.Rmd`: six `plot(..., method = "difference")` calls repeating the same six
arguments, the per-topic continuous age plots, and three gender-by-age interaction triplets. All
three are in `R/covariate_effects.R`.

Two notes on the regex set, for whoever does the extraction:

- `pattern5` and `pattern9` are **byte-identical**.
- `pattern3` is a superset that already contains the full text of `pattern4`, `pattern5`, `pattern6`,
  and `pattern7`. Since `pattern3` is applied first (L122), the four that follow are partly redundant
  — but only partly, because `pattern3` matches the whole block as a unit and the others match
  fragments that may appear alone. **The order is load-bearing; preserve it and document why.**

---

## Scope decision — the re-fit covers K = 12 only

**Decided by the project owner; recorded here because it changes what
`stm_models_final.rmd` produces and what three downstream notebooks can reference.**

The original file fitted five families across K = 6/12/18/24/32 — 21 model calls, two of which
(`manyTopics`, `selectModel`) run 10 internal candidates each. The re-fit that carries the S1
corrections fits **K = 12 only**, still across all five families.

### Why this is sound

**K was not chosen by exclusivity and coherence.** It was settled by professional review of the
clustering results across the candidate models. That review is complete and K = 12 is final, so
re-fitting the other four K values would regenerate inputs to a decision already made — at the
majority of the compute cost, since the large-K fits dominate the sweep.

**The corrections do not bear on the choice of K.** The gender fix moves 134 of 8,210 documents
(1.6%); the race fix merges level labels without changing which essays are present; the S1-4 and
S1-5 fixes are arithmetic applied downstream of the model. None plausibly changes what a human
reviewing exemplar essays judged to be the most coherent topic count. *This is a judgement, not a
verified claim* — it is the project owner's call, and they have made it.

**Every published analysis already used K = 12 exclusively.** Verified by reference check, not
assumption: every plot, effect estimate, and label in `stm_analyses_final.Rmd` touches K = 12
objects only. The sole exception was the exclusivity-vs-coherence comparison, which is precisely the
method that did not drive the decision.

### What changed

| File | Change |
|---|---|
| `stm_models_final.rmd` | Fits K = 12 per family. K-sweep code **retained, commented**, with seeds reserved. Corpus `save()` re-enabled. |
| `stm_analyses_final.Rmd` | Exclusivity/coherence chunk marked `eval = FALSE` — it is a pair with the sweep; restore both together. |
| `essay_examples_final.Rmd` | Exemplars and top essays now loop over the five K = 12 specifications instead of K = 6/32 and five `stm.pc.*`. |
| `stm.rforestmodels.final.Rmd` | Dead `t.6/18/24/32` and `srl.topics.6/18/24/32` removed — assigned but never read, dead before this decision. |
| `scripts/capture_baseline.R` | Baseline covers the five K = 12 objects; `selectModel` output summarised via `$runout[[1]]`. |

Artifact filenames were renamed from `*.6_32.Rda` to `*.k12.Rda` so the names describe the contents.
Every S2 finding in this document was a name that did not match what it referenced; keeping a file
called `6_32` holding only K = 12 would have added another.

### Open item

**S5-1 · Topic labels need re-validation against the new fit.** `TOPIC_LABELS_K12` was assigned by
hand against the old, uncorrected model. The corrected corpus may shift what the twelve topics
contain. Compare `labelTopics()` output against the assigned labels before reusing them in any
write-up — a judgement call for the project owner, not a mechanical check.

**The re-fit has now run. Eleven of twelve labels hold; one warrants review.**

> **Correction.** An earlier version of this section claimed topic 5 had "no mathematics vocabulary
> at all" and that topics 1 and 5 appeared transposed. **That was wrong**, and the error was
> methodological: it read only the `prob` and `frex` metrics. `labelTopics()` returns four, and the
> other two — `lift` and `score` — surface low-frequency but highly distinctive terms, which is
> precisely what identifies a topic's subject matter. Both show mathematics vocabulary in topic 5.
> **Always read all four metrics before judging a topic.**

### Topic 5 — "Improving Math Skills" is supported

| Metric | Terms |
|---|---|
| prob | area, improv, assess, weak, strength, skill, need, strong, see, well |
| frex | area, weak, assess, strength, improv, identifi, surpris, strong, recommend, tool |
| **lift** | **mathemat, equat**, weaker, weakest, area, link, weak, **retak**, strength, **calcul** |
| **score** | **mathemat**, area, assess, improv, weak, strength, identifi, surpris, **equat**, recommend |

On the model's word-topic weights, `mathemat` loads highest on topic 5 (0.0027) and is essentially
absent elsewhere; `equat` likewise (0.0020). The topic reads as *students discussing their
mathematics assessment results* — weakest areas, retaking, equations, calculations. The label stands.

### Topic 2 — "Developing Writing Skills" is supported

`lift`: writer, english, paper, essay, word, write, written, reader, languag, paragraph. Unambiguous.
The colloquial `math` does appear in topic 2's `prob` terms and loads higher there (0.0146) than in
topic 5 — students name reading, writing and mathematics together when describing their assessments —
but the formal mathematics stems belong to topic 5.

### Topic 1 — "Areas for Improvement" is the weak fit

| Metric | Terms |
|---|---|
| prob | learn, evalu, improv, assign, plan, use, can, ask, monitor, help |
| frex | assign, evalu, ask, monitor, approach, suggest, list, learn, way, best |
| lift | frequenc, brainstorm, **self-monitor**, suppos, assign, approach, list, **self-evalu**, react, schoolwork |
| score | frequenc, learn, assign, monitor, evalu, improv, ask, approach, suggest, plan |

Across all four metrics this reads as **self-monitoring and study strategy** — `self-monitor`,
`self-evalu`, `brainstorm`, `assign`, `schoolwork` — rather than "areas for improvement", which is
closer to what topic 5 expresses. It has the best semantic coherence of any topic (-17.49) and the
third-largest share (11.37%), so it is a well-formed topic that is simply named imprecisely.

**Recommendation:** review topic 1 against its exemplars in
`Essay_Passages/stm.p.12/Topic1.png` and consider a name closer to
"Self-Monitoring and Study Strategies". Leave the other eleven as they are.

The remaining labels hold up, several strikingly: 3 (test, anxieti, relax, exam, worri, stress),
10 (growth, intellig, mindset, fix, mistak), 11 (materi, subject, concept, retain, comprehend),
12 (phone, procrastin, distract, interrupt, quiet).

Because the labels feed six plots in `stm_analyses_final.Rmd` and the rename map in
`stm.rforestmodels.final.Rmd`, any change propagates into every figure and the random-forest variable
names — so make the decision once, in `R/topic_labels.R`, rather than at the call sites.

Mean topic proportions from the corrected fit, for reference:

| Topic | Proportion | Topic | Proportion |
|---|---:|---|---:|
| 9 | 16.10% | 12 | 7.79% |
| 8 | 12.54% | 11 | 7.43% |
| 1 | 11.37% | 6 | 6.79% |
| 7 | 10.02% | 5 | 5.64% |
| 4 | 8.65% | 3 | 5.48% |
| | | 10 | 4.17% |
| | | 2 | 4.03% |

---

## Suggested review process going forward

1. One branch and PR per concern, `chore/` → `docs/` → `style/` → `refactor/` → `fix/`.
2. Formatting PRs must produce **bit-identical** diagnostics (see the baseline capture in the plan).
   A diff means the "formatting" change wasn't one.
3. Behavior-changing PRs state up front which reported numbers they invalidate.
4. `lintr::lint_dir()` clean, or the exception waived in `.lintr` with a comment saying why.
5. No data artifact reaches a commit — `.gitignore` is the backstop, but check `git status` before
   staging regardless.
