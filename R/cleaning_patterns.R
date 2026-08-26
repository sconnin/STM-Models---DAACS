#' Regex patterns used to strip essay-prompt boilerplate and normalise text.
#'
#' Replaces 21 hand-numbered globals (`pattern1` .. `pattern21`) defined inline
#' in preprocess_data.rmd. The strings are copied mechanically from that file and
#' are byte-identical to the originals; only their names and location change.
#'
#' ORDER IS LOAD-BEARING. The cleaning chain applies these in sequence and later
#' entries assume earlier ones have already run. Two overlaps make this concrete:
#'
#'   - `prompt_full_block` (was pattern3) is a superset that already contains the
#'     text of eight other entries: patterns 4, 5, 6, 7, 8, 9, 10 and 19. It runs
#'     first and removes the whole prompt as one unit; the narrower entries then
#'     catch fragments appearing alone in essays that quoted only part of it.
#'   - `prompt_refer_to_survey_results` (pattern5) and its `_duplicate` (pattern9)
#'     are byte-identical. The second application is a no-op on text the first
#'     already cleaned. Retained so the sequence stays faithful to the original;
#'     removing it is safe but is a behaviour change and belongs in its own commit.
#'
#' Reordering or de-duplicating this list changes which essays survive the
#' >= 50-unique-word filter downstream, and therefore changes the corpus.

ESSAY_CLEANING_PATTERNS <- list(
  # pattern1
  prompt_question_srl_results = "what do your self-regulated learning survey results and the feedback tell you about your learning skills",
  # pattern2
  prompt_use_results_to_support = "use results from the survey and the feedback to support your analysis",
  # pattern3
  prompt_full_block = "you received information about your learning skills after you took the self-regulated learning (srl) survey, as well as suggestions for becoming a more effective and efficient learner. now, in order to reflect on your learning skills and receive feedback on your writing, please use the results from your srl survey to do your best writing in a brief essay that answers the questions below.\n\nyou will need to refer to your srl survey results and feedback in your essay. we recommend reviewing them, taking notes, and then returning here to write.\n\nessays must be at least 350 words in order to be meaningfully scored. please aim to write a complete, well-developed essay in order to get accurate feedback about how ready you are for academic writing, and what you can do to strengthen your writing skills",
  # pattern4
  prompt_reflect_and_receive_feedback = "now, in order to reflect on your learning skills and receive feedback on your writing, please use the results from your srl survey to do your best writing in a brief essay that answers the questions below",
  # pattern5
  prompt_refer_to_survey_results = "you will need to refer to your srl survey results and feedback in your essay. we recommend reviewing them, taking notes, and then returning here to write.",
  # pattern6
  prompt_minimum_350_words = "essays must be at least 350 words in order to be meaningfully scored",
  # pattern7
  prompt_aim_for_complete_essay = "please aim to write a complete, well-developed essay in order to get accurate feedback about how ready you are for academic writing, and what you can do to strengthen your writing skills",
  # pattern8
  prompt_received_information_block = "you received information about your learning skills after you took the self-regulated learning (srl) survey, as well as suggestions for becoming a more effective and efficient learner. now, in order to reflect on your learning skills and receive feedback on your writing, please use the results from your srl survey to do your best writing in a brief essay that answers the questions below.",
  # pattern9
  prompt_refer_to_survey_results_duplicate = "you will need to refer to your srl survey results and feedback in your essay. we recommend reviewing them, taking notes, and then returning here to write.",
  # pattern10
  prompt_350_words_and_aim_combined = "essays must be at least 350 words in order to be meaningfully scored. please aim to write a complete, well-developed essay in order to get accurate feedback about how ready you are for academic writing, and what you can do to strengthen your writing skills.",
  # pattern11
  prompt_which_strategies_committed = "which suggested strategies from the feedback are you committed to using this term? explain why you are committed to using those strategies",
  # pattern12
  keep_if_first_person_pronoun = "\\b(i|me|we|my|mine|our|ours|us|myself|ourselves)\\b",
  # pattern13
  sentence_final_period = "[\\.\\s]",
  # pattern14
  punctuation_except_hyphen = "[\\p{P}\\p{S}--[-]]",
  # pattern15
  carriage_returns_and_tabs = "([\r\n]|\\\t)",
  # pattern16
  srl_domain_vocabulary = "self-regulated learning| self regulated learning|self -regulatedlearning|self-regulatedlearning|self-regulated|srl|\nsurvey|daacss|daacs|selfregulated learning|selfregulated|selfregulating learning|selfregulating|self regulated| self regulating learning|self-regulatedlearning|meta-cognition|metacognition|metacognitive|score|motivation|strategies|survey|results|learning skills|learning survey|wgu|western governors university|excelsior college|excelsior|albany|january| february|march|april|may|june|july|august|septempber|october|november|december",
  # pattern17
  single_character_words = "(\\b\\w\\s|\\s\\w\\s|\\s\\w)\\b",
  # pattern18
  drop_if_placeholder_text = "blah blah",
  # pattern19
  prompt_you_received_information = "you received information about your",
  # pattern20
  prompt_after_you_took = "after you took the",
  # pattern21
  prompt_as_well_as_suggestions = "as well as suggestions for becoming more effective and efficient learner"
)

#' Look up a cleaning pattern by name.
#'
#' @param name Entry name in `ESSAY_CLEANING_PATTERNS`.
#' @return The regex string.
cleaning_pattern <- function(name) {
  if (!name %in% names(ESSAY_CLEANING_PATTERNS)) {
    stop(
      "unknown cleaning pattern '", name, "'; available: ",
      paste(names(ESSAY_CLEANING_PATTERNS), collapse = ", "),
      call. = FALSE
    )
  }
  ESSAY_CLEANING_PATTERNS[[name]]
}
