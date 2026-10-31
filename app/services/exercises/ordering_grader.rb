module Exercises
  class OrderingGrader
    Result = Struct.new(:answer, :correct, :score, :correct_count, :total_items, keyword_init: true)

    def self.call(exercise:, ordered_ids: nil, sentences: nil, points:)
      object = exercise.to_h.deep_stringify_keys
      if object["format"] == ExerciseContentValidator::MULTIPLE_SENTENCES_FORMAT
        return grade_multiple_sentences(object, sentences:, points:)
      end

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

    def self.grade_multiple_sentences(object, sentences:, points:)
      submitted_by_id = sentences.to_h { |sentence| [ sentence.fetch("id"), sentence.fetch("ordered_ids") ] }
      sentence_results = object.fetch("sentences").map do |sentence|
        items_by_id = sentence.fetch("items").index_by { |item| item.fetch("id") }
        expected_order = sentence.fetch("correct_order")
        submitted_order = submitted_by_id.fetch(sentence.fetch("id"))
        positions = expected_order.each_with_index.map do |expected_id, index|
          submitted_id = submitted_order.fetch(index)
          expected_label = items_by_id.fetch(expected_id).fetch("label")
          submitted_label = items_by_id.fetch(submitted_id).fetch("label")
          {
            "expected_item_id" => expected_id,
            "submitted_item_id" => submitted_id,
            "expected_label" => expected_label,
            "submitted_label" => submitted_label,
            "correct" => submitted_label == expected_label
          }
        end
        { "id" => sentence.fetch("id"), "positions" => positions }
      end
      all_positions = sentence_results.flat_map { |sentence| sentence.fetch("positions") }
      correct_count = all_positions.count { |position| position.fetch("correct") }
      total_positions = all_positions.length
      score = total_positions.positive? ? points.to_i * correct_count / total_positions : 0

      Result.new(
        answer: { "sentences" => object.fetch("sentences").map do |sentence|
          { "id" => sentence.fetch("id"), "ordered_ids" => submitted_by_id.fetch(sentence.fetch("id")) }
        end },
        correct: {
          "sentences" => sentence_results,
          "correct" => correct_count == total_positions,
          "positions_correct" => correct_count,
          "total_positions" => total_positions
        },
        score:,
        correct_count:,
        total_items: total_positions
      )
    end
    private_class_method :grade_multiple_sentences
  end
end
