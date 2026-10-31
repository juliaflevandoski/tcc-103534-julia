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

  test "grades all multiple sentence positions correctly" do
    result = Exercises::OrderingGrader.call(
      exercise: multiple_sentence_exercise,
      sentences: [
        { "id" => "sentence-one", "ordered_ids" => %w[a b c d] },
        { "id" => "sentence-two", "ordered_ids" => %w[e f g h] }
      ],
      points: 100
    )

    assert_equal 8, result.correct_count
    assert_equal 8, result.total_items
    assert_equal 100, result.score
    assert_equal true, result.correct.fetch("correct")
  end

  test "grades incorrect and partial multiple sentence positions proportionally" do
    incorrect = Exercises::OrderingGrader.call(
      exercise: multiple_sentence_exercise,
      sentences: [
        { "id" => "sentence-one", "ordered_ids" => %w[d c b a] },
        { "id" => "sentence-two", "ordered_ids" => %w[h g f e] }
      ],
      points: 100
    )
    partial = Exercises::OrderingGrader.call(
      exercise: multiple_sentence_exercise,
      sentences: [
        { "id" => "sentence-one", "ordered_ids" => %w[a b c d] },
        { "id" => "sentence-two", "ordered_ids" => %w[e h f g] }
      ],
      points: 100
    )

    assert_equal 0, incorrect.score
    assert_equal false, incorrect.correct.fetch("correct")
    assert_equal 5, partial.correct_count
    assert_equal 8, partial.total_items
    assert_equal 62, partial.score
    assert_equal 5, partial.correct.fetch("positions_correct")
    assert_equal 8, partial.correct.fetch("total_positions")
  end

  test "swapped IDs for identical repeated words remain correct by text" do
    exercise = {
      "format" => "multiple_sentences",
      "sentences" => [
        {
          "id" => "sentence-one",
          "items" => [ { "id" => "a", "label" => "I" }, { "id" => "b", "label" => "think" }, { "id" => "c", "label" => "I" }, { "id" => "d", "label" => "can." } ],
          "correct_order" => %w[a b c d]
        },
        {
          "id" => "sentence-two",
          "items" => [ { "id" => "e", "label" => "We" }, { "id" => "f", "label" => "will" } ],
          "correct_order" => %w[e f]
        }
      ]
    }
    result = Exercises::OrderingGrader.call(
      exercise:,
      sentences: [
        { "id" => "sentence-one", "ordered_ids" => %w[c b a d] },
        { "id" => "sentence-two", "ordered_ids" => %w[e f] }
      ],
      points: 100
    )

    assert_equal 6, result.correct_count
    assert_equal [ true, true, true, true ], result.correct.fetch("sentences").first.fetch("positions").pluck("correct")
  end

  private

  def multiple_sentence_exercise
    {
      "format" => "multiple_sentences",
      "sentences" => [
        { "id" => "sentence-one", "items" => [ { "id" => "a", "label" => "A" }, { "id" => "b", "label" => "B" }, { "id" => "c", "label" => "C" }, { "id" => "d", "label" => "D" } ], "correct_order" => %w[a b c d] },
        { "id" => "sentence-two", "items" => [ { "id" => "e", "label" => "E" }, { "id" => "f", "label" => "F" }, { "id" => "g", "label" => "G" }, { "id" => "h", "label" => "H" } ], "correct_order" => %w[e f g h] }
      ]
    }
  end
end
