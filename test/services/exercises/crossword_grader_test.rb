require "test_helper"

class Exercises::CrosswordGraderTest < ActiveSupport::TestCase
  test "scores correct words proportionally without returning expected answers as feedback" do
    layout = {
      "words" => [
        { "id" => "w1", "normalized" => "CAT", "row" => 0, "column" => 0, "direction" => "across" },
        { "id" => "w2", "normalized" => "DOG", "row" => 1, "column" => 0, "direction" => "across" }
      ]
    }
    answer = { "cells" => { "0-0" => "C", "0-1" => "A", "0-2" => "T", "1-0" => "D", "1-1" => "X", "1-2" => "G" } }

    result = Exercises::CrosswordGrader.call(layout:, answer:, points: 11)

    assert_equal 5, result.score
    assert_equal 1, result.correct_words
    assert_equal 2, result.total_words
    assert_equal({ "w1" => true, "w2" => false }, result.statuses)
    assert_not result.complete?
    assert_not_includes result.statuses.values, "CAT"
  end

  test "does not count empty cells as a correct word" do
    layout = { "words" => [ { "id" => "w1", "normalized" => "DOG", "row" => 0, "column" => 0, "direction" => "down" } ] }
    answer = { "cells" => { "0-0" => "D", "1-0" => "O" } }

    result = Exercises::CrosswordGrader.call(layout:, answer:, points: 10)

    assert_equal 0, result.score
    assert_equal({ "w1" => false }, result.statuses)
  end

  test "awards all points only when each word is fully correct" do
    layout = { "words" => [ { "id" => "w1", "normalized" => "CAO", "row" => 0, "column" => 0, "direction" => "across" } ] }
    answer = { "cells" => { "0-0" => "c", "0-1" => "Ã", "0-2" => "o" } }

    result = Exercises::CrosswordGrader.call(layout:, answer:, points: 7)

    assert_equal 7, result.score
    assert result.complete?
  end
end
