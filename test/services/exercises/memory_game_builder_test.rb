require "test_helper"

class Exercises::MemoryGameBuilderTest < ActiveSupport::TestCase
  test "builds word pairs with unique server-generated pair IDs" do
    result = Exercises::MemoryGameBuilder.call(object: {
      instructions: "Combine as palavras.",
      pair_type: "word_word",
      pairs: [
        { left: { type: "word", content: " DOG " }, right: { type: "word", content: "CACHORRO" } },
        { left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } }
      ]
    })

    assert result.success?
    assert_equal "Combine as palavras.", result.object.fetch("instructions")
    assert_equal [ "DOG", "CAT" ], result.object.fetch("pairs").map { |pair| pair.dig("left", "content") }
    pair_ids = result.object.fetch("pairs").pluck("id")
    assert_equal 2, pair_ids.uniq.length
  end

  test "validates minimum pair count and element types" do
    result = Exercises::MemoryGameBuilder.call(object: {
      pair_type: "word_image",
      pairs: [
        { left: { type: "word", content: "DOG" }, right: { type: "word", content: "CAT" } }
      ]
    })

    assert_not result.success?
    assert_includes result.errors, "Adicione pelo menos dois pares."
    assert result.errors.any? { |message| message.include?("elemento da direita inválido") }
  end

  test "validates image elements for both supported image association types" do
    [ "word_image", "image_image" ].each do |pair_type|
      element_types = Exercises::MemoryGameBuilder::PAIR_TYPES.fetch(pair_type)
      pairs = 2.times.map do |index|
        elements = element_types.map.with_index do |type, side_index|
          if type == "image"
            { type:, blob_id: index + side_index + 1 }
          else
            { type: "word", content: "WORD" }
          end
        end
        { left: elements[0], right: elements[1] }
      end

      result = Exercises::MemoryGameBuilder.call(object: { pair_type:, pairs: })

      assert result.success?, "#{pair_type} should accept valid image references"
      assert_equal 2, result.object.fetch("pairs").length
    end
  end

  test "keeps an upload key temporary until the controller attaches the image" do
    result = Exercises::MemoryGameBuilder.call(object: {
      pair_type: "word_image",
      pairs: 2.times.map do |index|
        {
          left: { type: "word", content: "WORD-#{index}" },
          right: { type: "image", upload_key: "pair-#{index}-right" }
        }
      end
    })

    assert result.success?
    assert_equal "pair-0-right", result.object.dig("pairs", 0, "right", "upload_key")
  end
end
