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

# Order is significant: element i labels TopicI. Preserved exactly as written in
# the notebooks, including the "Appying" typo in element 11 -- correcting it here
# would change figure output, so it is left for a deliberate decision rather than
# folded into a refactor. See CODE_REVIEW.md.
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
  "Appying and Retaining Subject Matter",
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
