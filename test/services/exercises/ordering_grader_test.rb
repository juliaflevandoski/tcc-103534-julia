require "test_helper"

class Exercises::OrderingGraderTest < ActiveSupport::TestCase
  test "awards proportional points for items in their exact positions" do
    exercise = {
      "items" => [
        { "id" => "item-1", "label" => "Primeiro" },
        { "id" => "item-2", "label" => "Segundo" },
        { "id" => "item-3", "label" => "Terceiro" },
        { "id" => "item-4", "label" => "Quarto" }
      ],
      "correct_order" => %w[item-1 item-2 item-3 item-4]
    }

    result = Exercises::OrderingGrader.call(
      exercise:,
      ordered_ids: %w[item-1 item-3 item-2 item-4],
      points: 10
    )

    assert_equal 2, result.correct_count
    assert_equal 4, result.total_items
    assert_equal 5, result.score
    assert_equal [ true, false, false, true ], result.correct.fetch("positions").pluck("correct")
  end

  test "ignores forged IDs and marks missing positions incorrect" do
    result = Exercises::OrderingGrader.call(
      exercise: { "items" => [ { "id" => "item-1", "label" => "Um" }, { "id" => "item-2", "label" => "Dois" } ], "correct_order" => %w[item-1 item-2] },
      ordered_ids: %w[forged item-1 item-2],
      points: 9
    )

    assert_equal [ nil, "item-1" ], result.answer.fetch("ordered_ids")
    assert_equal 0, result.score
    assert_equal [ false, false ], result.correct.fetch("positions").pluck("correct")
  end
end
