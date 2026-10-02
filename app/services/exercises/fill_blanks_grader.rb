module Exercises
  class FillBlanksGrader
    Result = Struct.new(:answer, :correct, :score, :correct_count, :total_blanks, keyword_init: true)
    MARKER_PATTERN = /\{\{(\d+)\}\}/

    def self.call(exercise:, answers:, points:)
      object = exercise.to_h
      submitted_answers = answers.respond_to?(:to_unsafe_h) ? answers.to_unsafe_h : answers.to_h
      blank_ids = object.fetch("text_template", "").to_s.scan(MARKER_PATTERN).flatten.uniq
      expected_answers = object.fetch("blanks", {}).to_h
      normalized_answers = blank_ids.to_h do |blank_id|
        [ blank_id, submitted_answers[blank_id].to_s ]
      end
      statuses = blank_ids.map do |blank_id|
        expected_answer = expected_answers[blank_id].to_s
        submitted_answer = normalized_answers.fetch(blank_id)
        {
          "id" => blank_id,
          "correct" => expected_answer.present? && normalize_text(submitted_answer) == normalize_text(expected_answer),
          "correct_answer" => expected_answer
        }
      end
      correct_count = statuses.count { |status| status.fetch("correct") }
      total_blanks = statuses.length
      score = total_blanks.positive? ? points.to_i * correct_count / total_blanks : 0

      Result.new(
        answer: { "answers" => normalized_answers },
        correct: { "blanks" => statuses },
        score:,
        correct_count:,
        total_blanks:
      )
    end

    def self.normalize_text(value)
      value.to_s.gsub(/\s+/, " ").strip.downcase
    end
    private_class_method :normalize_text
  end
end
