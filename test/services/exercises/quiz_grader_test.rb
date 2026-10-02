require "test_helper"

class Exercises::QuizGraderTest < ActiveSupport::TestCase
  test "grades mixed question types and awards proportional points" do
    quiz = {
      "questions" => [
        {
          "question_type" => "multiple_choice",
          "statement" => "Quanto é 2 + 2?",
          "options" => [ { "id" => "a", "text" => "4" }, { "id" => "b", "text" => "5" } ],
          "correct_option_ids" => [ "a" ]
        },
        {
          "question_type" => "true_false",
          "statement" => "2 + 2 é igual a 5?",
          "correct_option_ids" => [ "false" ]
        },
        {
          "question_type" => "short_answer",
          "statement" => "Escreva quatro.",
          "correct_answer" => "Quatro"
        }
      ]
    }

    result = Exercises::QuizGrader.call(
      quiz:,
      answers: { "0" => "a", "1" => "true", "2" => "  QUATRO  " },
      points: 10
    )

    assert_equal 2, result.correct_count
    assert_equal 3, result.total_questions
    assert_equal 6, result.score
    assert_equal [ true, false, true ], result.correct.fetch("questions").pluck("correct")
    assert_equal "4", result.correct.fetch("questions").first.fetch("correct_answer")
    assert_equal({ "0" => "a", "1" => "true", "2" => "  QUATRO  " }, result.answer.fetch("answers"))
  end

  test "ignores submitted answers for unknown question indexes" do
    result = Exercises::QuizGrader.call(
      quiz: { "questions" => [ { "question_type" => "short_answer", "correct_answer" => "ok" } ] },
      answers: { "0" => "ok", "99" => "forged" },
      points: 5
    )

    assert_equal 5, result.score
    assert_equal({ "0" => "ok" }, result.answer.fetch("answers"))
  end
end
