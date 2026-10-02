module Exercises
  class QuizGrader
    Result = Struct.new(:answer, :correct, :score, :correct_count, :total_questions, keyword_init: true)

    def self.call(quiz:, answers:, points:)
      questions = quiz.to_h.fetch("questions", [])
      submitted_answers = answers.respond_to?(:to_unsafe_h) ? answers.to_unsafe_h : answers.to_h
      normalized_answers = questions.each_index.to_h do |index|
        [ index.to_s, submitted_answers[index.to_s].to_s ]
      end
      statuses = questions.each_with_index.map do |question, index|
        question = question.to_h
        answer = normalized_answers.fetch(index.to_s)
        {
          "statement" => question["statement"].to_s,
          "correct" => answer_correct?(question, answer),
          "correct_answer" => correct_answer_for(question)
        }
      end
      correct_count = statuses.count { |status| status.fetch("correct") }
      total_questions = statuses.length
      score = total_questions.positive? ? points.to_i * correct_count / total_questions : 0

      Result.new(
        answer: { "answers" => normalized_answers },
        correct: { "questions" => statuses },
        score:,
        correct_count:,
        total_questions:
      )
    end

    def self.answer_correct?(question, answer)
      case question["question_type"]
      when "multiple_choice", "true_false"
        Array(question["correct_option_ids"]).first.to_s == answer
      when "short_answer"
        normalize_text(question["correct_answer"]) == normalize_text(answer)
      else
        false
      end
    end
    private_class_method :answer_correct?

    def self.correct_answer_for(question)
      case question["question_type"]
      when "multiple_choice"
        option_id = Array(question["correct_option_ids"]).first.to_s
        Array(question["options"]).find { |option| option.to_h["id"].to_s == option_id }
          &.to_h&.fetch("text", option_id) || option_id
      when "true_false"
        Array(question["correct_option_ids"]).first.to_s == "true" ? "Verdadeiro" : "Falso"
      when "short_answer"
        question["correct_answer"].to_s
      else
        ""
      end
    end
    private_class_method :correct_answer_for

    def self.normalize_text(value)
      value.to_s.gsub(/\s+/, " ").strip.downcase
    end
    private_class_method :normalize_text
  end
end
