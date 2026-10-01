module Exercises
  class CrosswordGrader
    Result = Struct.new(:score, :correct_words, :total_words, :statuses, :correct_snapshot, keyword_init: true) do
      def complete?
        correct_words == total_words
      end
    end

    def self.call(layout:, answer:, points:)
      new(layout:, answer:, points:).call
    end

    def initialize(layout:, answer:, points:)
      @layout = layout.deep_stringify_keys
      @answer = answer.respond_to?(:to_h) ? answer.to_h.deep_stringify_keys : {}
      @points = points.to_i
    end

    def call
      entries = Array(@layout["words"])
      statuses = entries.to_h do |entry|
        [ entry.fetch("id"), word_correct?(entry) ]
      end
      correct_words = statuses.values.count(true)
      total_words = entries.length
      score = total_words.positive? ? (@points * correct_words / total_words) : 0

      Result.new(
        score:,
        correct_words:,
        total_words:,
        statuses:,
        correct_snapshot: {
          "words" => entries.map { |entry| { "id" => entry["id"], "normalized" => entry["normalized"] } },
          "statuses" => statuses
        }
      )
    end

    private

    def word_correct?(entry)
      expected = entry.fetch("normalized").to_s
      submitted = expected.length.times.map do |index|
        row = entry.fetch("row").to_i + (entry.fetch("direction") == "down" ? index : 0)
        column = entry.fetch("column").to_i + (entry.fetch("direction") == "across" ? index : 0)
        normalize_letter(@answer.dig("cells", "#{row}-#{column}"))
      end
      submitted.none?(&:empty?) && submitted.join == expected
    end

    def normalize_letter(value)
      value.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").upcase.gsub(/[^A-Z]/, "")[0].to_s
    end
  end
end
