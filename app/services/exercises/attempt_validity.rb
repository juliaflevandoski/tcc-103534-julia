module Exercises
  class AttemptValidity
    class BlankResponse < StandardError; end

    def self.ensure_response!(exercise:, answer:)
      return if response_present?(exercise:, answer:)

      raise BlankResponse, "Responda à atividade antes de enviá-la."
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
        response_present?(exercise:, answer:) && valid_grading_snapshot?(exercise, correct)
      end
    rescue ActiveRecord::RecordNotFound, TypeError, ArgumentError
      false
    end

    def self.response_present?(exercise:, answer:)
      object = stringify(exercise.object)
      submitted = stringify(answer)
      return false unless object.is_a?(Hash) && submitted.is_a?(Hash)

      case exercise.exercise_type
      when "quiz"
        quiz_response_present?(object, submitted)
      when "fill_blanks"
        fill_blanks_response_present?(object, submitted)
      when "ordering"
        ordering_response_present?(object, submitted)
      when "crossword"
        crossword_response_present?(object, submitted)
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

    def self.quiz_response_present?(object, submitted)
      answers = submitted["answers"]
      questions = object["questions"]
      return false unless answers.is_a?(Hash) && questions.is_a?(Array)

      questions.each_with_index.any? do |question, index|
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
    private_class_method :quiz_response_present?

    def self.fill_blanks_response_present?(object, submitted)
      answers = submitted["answers"]
      return false unless answers.is_a?(Hash)

      blank_ids = object.fetch("text_template", "").to_s.scan(/\{\{(\d+)\}\}/).flatten.uniq
      blank_ids.any? { |blank_id| answers[blank_id].is_a?(String) && answers[blank_id].present? }
    end
    private_class_method :fill_blanks_response_present?

    def self.ordering_response_present?(object, submitted)
      ordered_ids = submitted["ordered_ids"]
      return false unless ordered_ids.is_a?(Array)

      valid_ids = Array(object["items"]).filter_map { |item| item["id"] if item.is_a?(Hash) }
      ordered_ids.any? { |item_id| item_id.is_a?(String) && valid_ids.include?(item_id) }
    end
    private_class_method :ordering_response_present?

    def self.crossword_response_present?(object, submitted)
      submitted_cells = submitted.dig("cells")
      grid = object.dig("grid", "cells")
      return false unless submitted_cells.is_a?(Hash) && grid.is_a?(Array)

      open_cells = grid.each_with_index.flat_map do |row, row_index|
        row.each_with_index.filter_map { |cell, column_index| "#{row_index}-#{column_index}" if cell.present? }
      end
      open_cells.any? do |cell_id|
        value = submitted_cells[cell_id]
        value.is_a?(String) && normalize_crossword_letter(value).present?
      end
    end
    private_class_method :crossword_response_present?

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

    def self.valid_memory_game_attempt?(attempt, answer, correct)
      return false unless answer["completed"] == true

      deck = correct["deck"]
      return false unless deck.is_a?(Array) && deck.any?

      pair_ids = deck.filter_map { |card| card["pair_id"] if card.is_a?(Hash) }
      pair_counts = pair_ids.tally
      total_pairs = pair_counts.length
      total_pairs.positive? && pair_counts.values.all? { |count| count == 2 } &&
        answer["matches"] == total_pairs && attempt.score == correct["points"]
    end
    private_class_method :valid_memory_game_attempt?
  end
end
