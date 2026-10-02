require "test_helper"

class Exercises::FillBlanksGraderTest < ActiveSupport::TestCase
  test "grades blanks proportionally while ignoring case and extra whitespace" do
    exercise = {
      "text_template" => "A capital do {{1}} é {{2}}.",
      "blanks" => { "1" => "Brasil", "2" => "Brasília" }
    }

    result = Exercises::FillBlanksGrader.call(
      exercise:,
      answers: { "1" => "  BRASIL ", "2" => "Brasilia" },
      points: 9
    )

    assert_equal 1, result.correct_count
    assert_equal 2, result.total_blanks
    assert_equal 4, result.score
    assert_equal [ true, false ], result.correct.fetch("blanks").pluck("correct")
    assert_equal "Brasília", result.correct.fetch("blanks").last.fetch("correct_answer")
    assert_equal({ "1" => "  BRASIL ", "2" => "Brasilia" }, result.answer.fetch("answers"))
  end

  test "ignores forged answer keys and treats omitted blanks as unanswered" do
    result = Exercises::FillBlanksGrader.call(
      exercise: { "text_template" => "{{1}} / {{2}}", "blanks" => { "1" => "um", "2" => "dois" } },
      answers: { "1" => "um", "99" => "forged" },
      points: 5
    )

    assert_equal 2, result.score
    assert_equal({ "1" => "um", "2" => "" }, result.answer.fetch("answers"))
  end
end
