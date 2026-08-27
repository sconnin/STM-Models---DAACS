#' Hand-assigned topic labels for the K = 12 model.
#'
#' Replaces a 12-element character vector that appeared verbatim seven times --
#' six in stm_analyses_final.Rmd (as `custom.labels` and `vlabels`) and once in
#' stm.rforestmodels.final.Rmd (as `rename()` targets). All seven copies were
#' confirmed byte-identical before extraction.
#'
#' IMPORTANT -- these labels are specific to ONE fitted model.
#'
#' They were assigned by hand after inspecting `labelTopics()` output and
#' representative essays for the K = 12 prevalence model (`stm.p.12`). Topic
#' numbering is an artifact of a particular fit: it carries no meaning across
#' different values of K, and it is not guaranteed stable across refits of K = 12
#' either. `stm.p.12` was originally fitted without a seed (CODE_REVIEW.md S3-1),
#' so the model these labels describe cannot be regenerated exactly. Re-validate
#' the mapping against fresh `labelTopics()` output before reusing these labels
#' after any refit.
#'
#' Applying them to a model with a different K is a labelling error, not a
#' cosmetic one, which is why `topic_labels()` refuses rather than recycling.

# Order is significant: element i labels TopicI.
#
# THESE LABELS ARE TENTATIVE. They were assigned against an earlier fit and
# re-checked against the corrected one. Eleven hold; TOPIC 1 IS A KNOWN WEAK FIT
# -- across all four labelTopics() metrics it reads as self-monitoring and study
# strategy (self-monitor, self-evalu, brainstorm, assign, schoolwork) rather than
# "Areas for Improvement". It is retained pending review of its exemplar essays.
# See CODE_REVIEW.md S5-1 and README.md.
#
# Element 11 previously read "Appying" -- a typo carried verbatim from the
# notebooks. Corrected here, which also resolves the disagreement with the plot
# title at stm_analyses_final.Rmd (CODE_REVIEW.md X-1). Figure text changes
# accordingly.
TOPIC_LABELS_K12 <- c(
  "Areas for Improvement",
  "Developing Writing Skills",
  "Test Anxiety",
  "Returning Learners-Degree Completion",
  "Improving Math Skills",
  "Confirmation and Readiness",
  "Transferable Strategies & Academic Success",
  "Time Management",
  "Getting it Right Getting it Done",
  "Adjusting Ones Mindset",
  "Applying and Retaining Subject Matter",
  "Managing Distractions"
)

#' Topic labels for a given model size.
#'
#' @param k Number of topics. Only 12 is supported -- labels exist for no other K.
#' @param topics Optional integer vector selecting a subset, in the order given.
#' @return A character vector of labels.
topic_labels <- function(k = 12, topics = NULL) {
  if (!identical(as.integer(k), 12L)) {
    stop(
      "topic labels exist only for the K = 12 model; got K = ", k,
      ". Topic numbering does not carry across values of K, so reusing these ",
      "labels would mislabel the plot rather than merely inconvenience it.",
      call. = FALSE
    )
  }

  if (is.null(topics)) {
    return(TOPIC_LABELS_K12)
  }

  if (!is.numeric(topics) || any(topics < 1) || any(topics > length(TOPIC_LABELS_K12))) {
    stop(
      "topics must be numbers between 1 and ", length(TOPIC_LABELS_K12),
      call. = FALSE
    )
  }

  TOPIC_LABELS_K12[topics]
}

#' Named vector mapping `Topic1`..`Topic12` to their labels.
#'
#' Shaped for `dplyr::rename()`, which takes `new_name = old_name`.
#'
#' @param k Number of topics; only 12 is supported.
#' @return A named character vector: names are labels, values are `TopicN`.
topic_rename_map <- function(k = 12) {
  labels <- topic_labels(k)
  stats::setNames(paste0("Topic", seq_along(labels)), labels)
}
