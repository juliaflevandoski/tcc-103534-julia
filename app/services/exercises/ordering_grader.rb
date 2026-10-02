module Exercises
  class OrderingGrader
    Result = Struct.new(:answer, :correct, :score, :correct_count, :total_items, keyword_init: true)

    def self.call(exercise:, ordered_ids:, points:)
      object = exercise.to_h.deep_stringify_keys
      items = object.fetch("items", [])
      correct_order = Array(object["correct_order"]).map(&:to_s)
      item_labels = items.to_h { |item| [ item.to_h.fetch("id").to_s, item.to_h.fetch("label").to_s ] }
      submitted_order = Array(ordered_ids).first(correct_order.length).map do |item_id|
        item_id.to_s.in?(item_labels.keys) ? item_id.to_s : nil
      end
      statuses = correct_order.each_with_index.map do |item_id, index|
        {
          "expected_item_id" => item_id,
          "expected_label" => item_labels.fetch(item_id, ""),
          "correct" => submitted_order[index] == item_id
        }
      end
      correct_count = statuses.count { |status| status.fetch("correct") }
      total_items = statuses.length
      score = total_items.positive? ? points.to_i * correct_count / total_items : 0

      Result.new(
        answer: { "ordered_ids" => submitted_order },
        correct: { "positions" => statuses },
        score:,
        correct_count:,
        total_items:
      )
    end
  end
end
