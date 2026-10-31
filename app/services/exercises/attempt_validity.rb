module Exercises
  class AttemptValidity
    class BlankResponse < StandardError; end

    def self.ensure_response!(exercise:, answer:)
      return if response_complete?(exercise:, answer:)

      raise BlankResponse, "Preencha todas as respostas obrigatórias antes de enviar a atividade."
    end

    def self.valid_attempt?(attempt)
      return false unless attempt&.persisted? && attempt.score.is_a?(Integer) && attempt.correct.present?

      exercise = attempt.activity_exercise.exercise
      return false unless ExerciseContentValidator.call(
        exercise_type: exercise.exercise_type,
        object: exercise.object,
        attached_image_blob_ids: exercise.memory_images_attachments.map(&:blob_id)
      ).success?

      answer = stringify(attempt.answer)
      correct = stringify(attempt.correct)
      return false unless answer.is_a?(Hash) && correct.is_a?(Hash)

      if exercise.memory_game?
        valid_memory_game_attempt?(attempt, answer, correct)
      else
        response_complete?(exercise:, answer:) && valid_grading_snapshot?(exercise, correct)
      end
    rescue ActiveRecord::RecordNotFound, TypeError, ArgumentError
      false
    end

    def self.response_complete?(exercise:, answer:)
      object = stringify(exercise.object)
      submitted = stringify(answer)
      return false unless object.is_a?(Hash) && submitted.is_a?(Hash)

      case exercise.exercise_type
      when "quiz"
        quiz_response_complete?(object, submitted)
      when "fill_blanks"
        fill_blanks_response_complete?(object, submitted)
      when "ordering"
        if object["format"] == ExerciseContentValidator::MULTIPLE_SENTENCES_FORMAT
          multiple_sentence_ordering_response_complete?(object, submitted)
        else
          ordering_response_complete?(object, submitted)
        end
      when "crossword"
        crossword_response_complete?(object, submitted)
      else
        false
      end
    end

    def self.stringify(value)
      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
      case value
      when Hash
        value.each_with_object({}) { |(key, nested), result| result[key.to_s] = stringify(nested) }
      when Array
        value.map { |nested| stringify(nested) }
      else
        value
      end
    end
    private_class_method :stringify

    def self.quiz_response_complete?(object, submitted)
      answers = submitted["answers"]
      questions = object["questions"]
      return false unless answers.is_a?(Hash) && questions.is_a?(Array) && questions.any?

      questions.each_with_index.all? do |question, index|
        next false unless question.is_a?(Hash)

        value = answers[index.to_s]
        case question["question_type"]
        when "multiple_choice"
          value.is_a?(String) && Array(question["options"]).any? { |option| option["id"] == value }
        when "true_false"
          %w[true false].include?(value)
        when "short_answer"
          value.is_a?(String) && value.present?
        else
          false
        end
      end
    end
    private_class_method :quiz_response_complete?

    def self.fill_blanks_response_complete?(object, submitted)
      answers = submitted["answers"]
      return false unless answers.is_a?(Hash)

      blank_ids = object.fetch("text_template", "").to_s.scan(/\{\{(\d+)\}\}/).flatten.uniq
      blank_ids.any? && blank_ids.all? { |blank_id| answers[blank_id].is_a?(String) && answers[blank_id].present? }
    end
    private_class_method :fill_blanks_response_complete?

    def self.ordering_response_complete?(object, submitted)
      ordered_ids = submitted["ordered_ids"]
      return false unless ordered_ids.is_a?(Array)

      valid_ids = Array(object["items"]).filter_map { |item| item["id"] if item.is_a?(Hash) }
      valid_ids.any? && ordered_ids.length == valid_ids.length &&
        ordered_ids.all? { |item_id| item_id.is_a?(String) } &&
        ordered_ids.uniq.length == valid_ids.length && ordered_ids.sort == valid_ids.sort
    end
    private_class_method :ordering_response_complete?

    def self.multiple_sentence_ordering_response_complete?(object, submitted)
      expected_sentences = object["sentences"]
      submitted_sentences = submitted["sentences"]
      return false unless submitted.keys == [ "sentences" ] && expected_sentences.is_a?(Array) &&
        expected_sentences.length >= 2 && submitted_sentences.is_a?(Array) && submitted_sentences.length == expected_sentences.length

      expected_by_id = expected_sentences.to_h do |sentence|
        return false unless sentence.is_a?(Hash) && sentence["id"].is_a?(String) && sentence["items"].is_a?(Array)

        [ sentence.fetch("id"), sentence.fetch("items").filter_map { |item| item["id"] if item.is_a?(Hash) } ]
      end
      return false unless expected_by_id.keys.uniq.length == expected_sentences.length

      submitted_ids = submitted_sentences.filter_map do |sentence|
        sentence.fetch("id") if sentence.is_a?(Hash) && sentence["id"].is_a?(String)
      end
      return false unless submitted_ids.length == submitted_sentences.length && submitted_ids.uniq.length == expected_sentences.length
      return false unless submitted_ids.sort == expected_by_id.keys.sort

      submitted_sentences.all? do |sentence|
        next false unless sentence.keys.sort == %w[id ordered_ids]

        ordered_ids = sentence["ordered_ids"]
        expected_ids = expected_by_id.fetch(sentence.fetch("id"))
        ordered_ids.is_a?(Array) && ordered_ids.length == expected_ids.length && ordered_ids.all? { |id| id.is_a?(String) } &&
          ordered_ids.uniq.length == expected_ids.length && ordered_ids.sort == expected_ids.sort
      end
    end
    private_class_method :multiple_sentence_ordering_response_complete?

    def self.crossword_response_complete?(object, submitted)
      submitted_cells = submitted.dig("cells")
      grid = object.dig("grid", "cells")
      return false unless submitted_cells.is_a?(Hash) && grid.is_a?(Array)

      open_cells = grid.each_with_index.flat_map do |row, row_index|
        row.each_with_index.filter_map { |cell, column_index| "#{row_index}-#{column_index}" if cell.present? }
      end
      open_cells.any? && open_cells.all? do |cell_id|
        value = submitted_cells[cell_id]
        value.is_a?(String) && normalize_crossword_letter(value).present?
      end
    end
    private_class_method :crossword_response_complete?

    def self.normalize_crossword_letter(value)
      value.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").upcase.gsub(/[^A-Z]/, "")[0].to_s
    end
    private_class_method :normalize_crossword_letter

    def self.valid_grading_snapshot?(exercise, correct)
      case exercise.exercise_type
      when "quiz"
        statuses = correct["questions"]
        questions = exercise.object.fetch("questions", [])
        statuses.is_a?(Array) && statuses.length == questions.length &&
          statuses.all? { |status| status.is_a?(Hash) && [ true, false ].include?(status["correct"]) }
      when "fill_blanks"
        statuses = correct["blanks"]
        blank_ids = exercise.object.fetch("text_template", "").scan(/\{\{(\d+)\}\}/).flatten.uniq
        statuses.is_a?(Array) && statuses.map { |status| status["id"] }.sort == blank_ids.sort &&
          statuses.all? { |status| [ true, false ].include?(status["correct"]) }
      when "ordering"
        if exercise.object.deep_stringify_keys["format"] == ExerciseContentValidator::MULTIPLE_SENTENCES_FORMAT
          return valid_multiple_sentence_grading_snapshot?(exercise, correct)
        end

        statuses = correct["positions"]
        expected_ids = Array(exercise.object["correct_order"])
        statuses.is_a?(Array) && statuses.map { |status| status["expected_item_id"] } == expected_ids &&
          statuses.all? { |status| [ true, false ].include?(status["correct"]) }
      when "crossword"
        statuses = correct["statuses"]
        word_ids = Array(exercise.object["words"]).map { |word| word["id"] }
        statuses.is_a?(Hash) && statuses.keys.sort == word_ids.sort && statuses.values.all? { |status| [ true, false ].include?(status) }
      else
        false
      end
    end
    private_class_method :valid_grading_snapshot?

    def self.valid_multiple_sentence_grading_snapshot?(exercise, correct)
      object = stringify(exercise.object)
      expected_sentences = object["sentences"]
      graded_sentences = correct["sentences"]
      return false unless expected_sentences.is_a?(Array) && graded_sentences.is_a?(Array) &&
        graded_sentences.length == expected_sentences.length

      positions = []
      valid_sentences = expected_sentences.zip(graded_sentences).all? do |expected, graded|
        expected_order = Array(expected["correct_order"])
        sentence_positions = graded.is_a?(Hash) && graded["positions"]
        next false unless graded.is_a?(Hash) && graded["id"] == expected["id"] && sentence_positions.is_a?(Array) &&
          sentence_positions.length == expected_order.length &&
          sentence_positions.all? { |position| position.is_a?(Hash) && [ true, false ].include?(position["correct"]) } &&
          sentence_positions.map { |position| position["expected_item_id"] } == expected_order &&
          sentence_positions.map { |position| position["expected_label"] }.all? { |label| label.is_a?(String) }

        positions.concat(sentence_positions)
        true
      end
      return false unless valid_sentences && positions.any?

      correct_count = positions.count { |position| position["correct"] }
      correct["correct"] == (correct_count == positions.length) &&
        correct["positions_correct"] == correct_count && correct["total_positions"] == positions.length
    end
    private_class_method :valid_multiple_sentence_grading_snapshot?

    def self.valid_memory_game_attempt?(attempt, answer, correct)
      return false unless answer["completed"] == true

      deck = correct["deck"]
      return false unless deck.is_a?(Array) && deck.any?
      return false unless deck.all? { |card| card.is_a?(Hash) && card["id"].is_a?(String) && card["pair_id"].is_a?(String) }

      card_ids = deck.map { |card| card.fetch("id") }
      return false unless card_ids.uniq.length == card_ids.length

      matched_card_ids = answer["matched_card_ids"]
      return false unless matched_card_ids.is_a?(Array) && matched_card_ids.all? { |card_id| card_id.is_a?(String) }
      return false unless matched_card_ids.uniq.sort == card_ids.sort
      return false unless answer["selected_card_id"].nil? && answer["pending_reset_ids"].blank?

      pair_ids = deck.map { |card| card.fetch("pair_id") }
      pair_counts = pair_ids.tally
      total_pairs = pair_counts.length
      total_pairs.positive? && pair_counts.values.all? { |count| count == 2 } &&
        answer["matches"] == total_pairs && attempt.score == correct["points"]
    end
    private_class_method :valid_memory_game_attempt?
  end
end
