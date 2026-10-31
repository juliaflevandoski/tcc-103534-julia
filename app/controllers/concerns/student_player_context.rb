module StudentPlayerContext
  extend ActiveSupport::Concern

  private

  def ordering_sentences_for_student(ordering)
    Array(ordering["sentences"]).map do |sentence|
      {
        "id" => sentence.fetch("id"),
        "items" => Array(sentence["items"]).shuffle.map { |item| item.slice("id", "label") }
      }
    end
  end

  def crossword_student_payload(object)
    layout = object.deep_stringify_keys
    cells = layout.fetch("grid").fetch("cells")
    {
      instructions: layout["instructions"],
      grid_mask: cells.map { |row| row.map(&:present?) },
      entries: layout.fetch("words").map do |entry|
        entry.slice("id", "clue", "number", "row", "column", "direction").merge("length" => entry.fetch("normalized").length)
          .symbolize_keys
      end
    }
  end
end
