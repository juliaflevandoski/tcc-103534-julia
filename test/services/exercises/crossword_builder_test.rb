require "test_helper"

class Exercises::CrosswordBuilderTest < ActiveSupport::TestCase
  test "crosses matching letters horizontally and vertically" do
    result = build(words: [
      { word: "APPLE", clue: "A fruit" },
      { word: "PEAR", clue: "Another fruit" },
      { word: "SCHOOL", clue: "A place to learn" }
    ])

    assert result.success?
    assert_equal %w[APPLE PEAR SCHOOL], result.object["words"].map { |entry| entry["normalized"] }.sort
    assert_includes result.object["words"].map { |entry| entry["direction"] }, "across"
    assert_includes result.object["words"].map { |entry| entry["direction"] }, "down"
    assert_operator crossing_count(result.object), :>=, 1
    assert_grid_matches_entries(result.object)
    assert_no_invalid_adjacencies(result.object)
  end

  test "places words with no shared letters without silently dropping them" do
    result = build(words: [
      { word: "CAT", clue: "A pet" },
      { word: "DOG", clue: "A barking pet" },
      { word: "BEE", clue: "A flying insect" }
    ])

    assert result.success?
    assert_empty result.unplaced_words
    assert_equal 3, result.object["words"].length
    assert_grid_matches_entries(result.object)
    assert_no_invalid_adjacencies(result.object)
  end

  test "normalizes case and accents for grid letters while preserving the entered word" do
    result = build(words: [
      { word: "Maçã", clue: "Fruta" },
      { word: "CÃO", clue: "Animal" }
    ])

    assert result.success?
    assert_equal "Maçã", result.object["words"].find { |entry| entry["word"] == "Maçã" }["word"]
    assert_equal %w[CAO MACA], result.object["words"].map { |entry| entry["normalized"] }.sort
    assert_grid_matches_entries(result.object)
    assert_no_invalid_adjacencies(result.object)
  end

  test "same words and seed produce the same persisted layout" do
    words = [ { word: "APPLE", clue: "Fruit" }, { word: "PEAR", clue: "Fruit" }, { word: "GRAPE", clue: "Fruit" } ]

    first = build(words:, seed: 21)
    second = build(words:, seed: 21)

    assert_equal first.object, second.object
  end

  test "different seeds can produce a different valid arrangement for regeneration" do
    words = [
      { word: "APPLE", clue: "Fruit" },
      { word: "PEAR", clue: "Fruit" },
      { word: "GRAPE", clue: "Fruit" },
      { word: "SCHOOL", clue: "Place to learn" }
    ]
    first = build(words:, seed: 1)
    second = build(words:, seed: 4)

    assert first.success?
    assert second.success?
    first_positions = first.object.fetch("words").map { |entry| entry.slice("row", "column", "direction") }
    second_positions = second.object.fetch("words").map { |entry| entry.slice("row", "column", "direction") }
    assert_not_equal first_positions, second_positions
    assert_grid_matches_entries(first.object)
    assert_grid_matches_entries(second.object)
  end

  test "reports all invalid or unplaceable entries instead of omitting them" do
    invalid_word = "A" * (Exercises::CrosswordBuilder::MAX_GRID_SIZE + 1)
    result = build(words: [
      { word: invalid_word, clue: "Too long" },
      { word: "DOG", clue: "Animal" }
    ])

    assert_not result.success?
    assert_match(/palavra 1.*limite/i, result.errors.join(" "))
    assert_includes result.unplaced_words, invalid_word
  end

  test "rejects duplicate answers after accent and case normalization" do
    result = build(words: [
      { word: "Maçã", clue: "Fruit" },
      { word: "MACA", clue: "Same answer" }
    ])

    assert_not result.success?
    assert_match(/repetida após normalização/i, result.errors.join(" "))
  end

  test "rejects entries without a clue and multiword answers" do
    result = build(words: [
      { word: "APPLE PIE", clue: "Dessert" },
      { word: "DOG", clue: "" }
    ])

    assert_not result.success?
    assert_equal 2, result.errors.length
  end

  test "requires instructions before generating a crossword" do
    result = Exercises::CrosswordBuilder.call(
      words: [ { word: "APPLE", clue: "Fruit" }, { word: "PEAR", clue: "Fruit" } ],
      instructions: " ",
      seed: 3
    )

    assert_not result.success?
    assert_includes result.errors, "Informe as instruções da cruzadinha."
  end

  test "rejects a malformed word collection safely" do
    result = Exercises::CrosswordBuilder.call(words: { word: "APPLE" }, instructions: "Complete")

    assert_not result.success?
    assert_includes result.errors, "A lista de palavras está inválida."
  end
  private

  def build(words:, seed: 0)
    Exercises::CrosswordBuilder.call(words:, instructions: "Complete a cruzadinha", seed:)
  end

  def crossing_count(object)
    positions = Hash.new(0)
    object.fetch("words").each do |entry|
      entry.fetch("normalized").length.times do |index|
        row = entry.fetch("row") + (entry.fetch("direction") == "down" ? index : 0)
        column = entry.fetch("column") + (entry.fetch("direction") == "across" ? index : 0)
        positions[[ row, column ]] += 1
      end
    end
    positions.values.count { |count| count > 1 }
  end

  def assert_grid_matches_entries(object)
    grid = object.fetch("grid").fetch("cells")
    object.fetch("words").each do |entry|
      entry.fetch("normalized").chars.each_with_index do |letter, index|
        row = entry.fetch("row") + (entry.fetch("direction") == "down" ? index : 0)
        column = entry.fetch("column") + (entry.fetch("direction") == "across" ? index : 0)
        assert_equal letter, grid.fetch(row).fetch(column)
      end
    end
  end

  def assert_no_invalid_adjacencies(object)
    entries = object.fetch("words")
    cells = {}
    entries.each do |entry|
      entry.fetch("normalized").chars.each_with_index do |letter, index|
        row = entry.fetch("row") + (entry.fetch("direction") == "down" ? index : 0)
        column = entry.fetch("column") + (entry.fetch("direction") == "across" ? index : 0)
        cells[[ row, column ]] ||= { letter:, entries: [] }
        cells[[ row, column ]][:entries] << entry
      end
    end

    cells.each_key do |row, column|
      [ [ row, column + 1, "across" ], [ row + 1, column, "down" ] ].each do |next_row, next_column, direction|
        next_cell = cells[[ next_row, next_column ]]
        next unless next_cell

        belongs_to_declared_word = cells[[ row, column ]][:entries].any? do |entry|
          entry.fetch("direction") == direction && next_cell[:entries].include?(entry)
        end
        assert belongs_to_declared_word, "Adjacent cells must belong to the same explicitly placed word"
      end
    end
  end
end
