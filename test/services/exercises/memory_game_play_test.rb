require "test_helper"

class Exercises::MemoryGamePlayTest < ActiveSupport::TestCase
  test "creates a shuffled, stable deck with two opaque card IDs per pair" do
    first_start = Exercises::MemoryGamePlay.start(object: game_object, seed: 41)
    second_start = Exercises::MemoryGamePlay.start(object: game_object, seed: 41)
    deck = first_start.fetch("correct").fetch("deck")

    assert_equal 8, first_start.fetch("card_ids").length
    assert_equal deck.pluck("pair_id"), second_start.fetch("correct").fetch("deck").pluck("pair_id")
    assert_equal 8, deck.pluck("id").uniq.length
    assert_equal 4, deck.group_by { |card| card.fetch("pair_id") }.length
    assert deck.group_by { |card| card.fetch("pair_id") }.values.all? { |cards| cards.length == 2 }
    assert_not_equal %w[pair-1 pair-1 pair-2 pair-2 pair-3 pair-3 pair-4 pair-4], deck.pluck("pair_id")
  end

  test "checks a correct pair on the server and records the completed score" do
    start = Exercises::MemoryGamePlay.start(object: game_object, seed: 41)
    first, second = matching_card_ids(start.fetch("correct"))

    first_reveal = Exercises::MemoryGamePlay.reveal(
      answer: start.fetch("answer"), correct: start.fetch("correct"), card_id: first, points: 10
    )
    second_reveal = Exercises::MemoryGamePlay.reveal(
      answer: first_reveal.answer, correct: start.fetch("correct"), card_id: second, points: 10
    )

    assert first_reveal.success?
    assert second_reveal.success?
    assert second_reveal.matched
    assert_equal 1, second_reveal.answer.fetch("attempts")
    assert_equal 1, second_reveal.answer.fetch("matches")
    assert_equal 0, second_reveal.answer.fetch("errors")
    assert_equal 2, second_reveal.answer.fetch("matched_card_ids").length
    assert_equal 0, second_reveal.score
    assert_not second_reveal.card.key?("pair_id")
  end

  test "rejects a third card until a mismatch is hidden" do
    start = Exercises::MemoryGamePlay.start(object: game_object, seed: 41)
    pair_cards = start.fetch("correct").fetch("deck").group_by { |card| card.fetch("pair_id") }.values
    first_id = pair_cards[0][0].fetch("id")
    second_id = pair_cards[1][0].fetch("id")
    third_id = pair_cards[2][0].fetch("id")

    first_reveal = Exercises::MemoryGamePlay.reveal(
      answer: start.fetch("answer"), correct: start.fetch("correct"), card_id: first_id, points: 8
    )
    mismatch = Exercises::MemoryGamePlay.reveal(
      answer: first_reveal.answer, correct: start.fetch("correct"), card_id: second_id, points: 8
    )
    third_reveal = Exercises::MemoryGamePlay.reveal(
      answer: mismatch.answer, correct: start.fetch("correct"), card_id: third_id, points: 8
    )
    deadline = Time.iso8601(mismatch.answer.fetch("pending_reset_until"))
    early_reset = Exercises::MemoryGamePlay.reset(answer: mismatch.answer, correct: mismatch.correct, at: deadline - 0.1)
    reset = Exercises::MemoryGamePlay.reset(answer: mismatch.answer, correct: mismatch.correct, at: deadline)
    next_reveal = Exercises::MemoryGamePlay.reveal(
      answer: reset.answer, correct: mismatch.correct, card_id: third_id, points: 8
    )

    assert mismatch.success?
    assert_not mismatch.matched
    assert_equal 1, mismatch.answer.fetch("errors")
    assert_not third_reveal.success?
    assert_not early_reset.success?
    assert reset.success?
    assert next_reveal.success?
  end

  test "finishes after all pairs are found and awards the full exercise score" do
    start = Exercises::MemoryGamePlay.start(object: game_object, seed: 41)
    answer = start.fetch("answer")
    total_pairs = start.fetch("correct").fetch("deck").group_by { |card| card.fetch("pair_id") }
    last_result = nil

    total_pairs.each_value do |cards|
      first_reveal = Exercises::MemoryGamePlay.reveal(
        answer:, correct: start.fetch("correct"), card_id: cards[0].fetch("id"), points: 11
      )
      result = Exercises::MemoryGamePlay.reveal(
        answer: first_reveal.answer, correct: start.fetch("correct"), card_id: cards[1].fetch("id"), points: 11
      )
      answer = result.answer
      last_result = result
    end

    assert last_result.completed
    assert_equal 4, answer.fetch("matches")
    assert_equal 4, answer.fetch("attempts")
    assert_equal 11, last_result.score
  end

  private

  def game_object
    {
      "pairs" => 4.times.map do |index|
        {
          "id" => "pair-#{index + 1}",
          "left" => { "type" => "word", "content" => "WORD-#{index + 1}" },
          "right" => { "type" => "word", "content" => "TERM-#{index + 1}" }
        }
      end
    }
  end

  def matching_card_ids(correct)
    cards = correct.fetch("deck").group_by { |card| card.fetch("pair_id") }.values.first
    cards.pluck("id")
  end
end
