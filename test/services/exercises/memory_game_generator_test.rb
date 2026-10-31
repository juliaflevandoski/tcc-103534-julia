require "test_helper"

class Exercises::MemoryGameGeneratorTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls

    def initialize(result)
      @result = result
      @calls = []
    end

    def call(**arguments)
      @calls << arguments
      @result
    end
  end

  Response = Struct.new(:data, :error_code, :message, keyword_init: true) do
    def success?
      error_code.nil?
    end
  end

  test "builds valid word-word pairs using the existing builder" do
    data = {
      "instructions" => "Combine os animais com seus nomes em português.",
      "pairs" => [
        { "left_text" => "DOG", "right_text" => "CÃO" },
        { "left_text" => "CAT", "right_text" => "GATO" }
      ]
    }
    client = fake_client(data:)
    result = build_generator(client).call(topic: "Animais", difficulty: "easy", pair_count: 2, pair_type: "word_word")

    assert result.success?, result.message
    assert_equal "word_word", result.draft.fetch("pair_type")
    assert_equal 2, result.draft.fetch("pairs").length
    assert result.draft.fetch("pairs").all? { |pair| pair.keys.sort == %w[id left right] }
    assert result.draft.fetch("pairs").all? { |pair| pair.fetch("id").present? }
    assert Exercises::ExerciseContentValidator.call(exercise_type: "memory_game", object: result.draft).success?
    assert_equal 1, client.calls.length
  end

  test "each difficulty level adds memory game-specific relation criteria for existing pair types" do
    difficulty_criteria = {
      "easy" => "relações diretas e facilmente reconhecíveis",
      "medium" => "compreender seus significados ou usos em um contexto familiar",
      "hard" => "relações conceituais mais elaboradas"
    }
    pair_types = {
      "word_word" => valid_data.fetch("pairs"),
      "word_image" => [ { "word" => "DOG", "image_description" => "A dog" }, { "word" => "CAT", "image_description" => "A cat" } ],
      "image_image" => [ { "left_image_description" => "A dog", "right_image_description" => "A bone" }, { "left_image_description" => "A cat", "right_image_description" => "A ball" } ]
    }

    difficulty_criteria.each do |difficulty, criterion|
      pair_types.each do |pair_type, pairs|
        client = fake_client(data: { "instructions" => "Combine as relações.", "pairs" => pairs })
        result = build_generator(client).call(topic: "Animais e seus elementos", difficulty:, pair_count: 2, pair_type:)
        call = client.calls.fetch(0)

        assert result.success?, "#{difficulty}/#{pair_type}: #{result.message}"
        assert_includes call.fetch(:instructions), criterion
        assert_includes call.fetch(:instructions), "Aplique o nível selecionado: #{difficulty}."
        assert_includes call.fetch(:input), "Dificuldade: #{difficulty}"
        assert_includes call.fetch(:input), "Tipo de associação: #{pair_type}"
        assert_includes call.fetch(:instructions), "não gere, procure nem referencie arquivos"
      end
    end
  end

  test "returns text-only image placeholders without inventing image references" do
    [
      [ "word_image", [ { "word" => "DOG", "image_description" => "A small brown dog" }, { "word" => "CAT", "image_description" => "A gray cat" } ] ],
      [ "image_image", [ { "left_image_description" => "A red apple", "right_image_description" => "A green pear" }, { "left_image_description" => "A blue car", "right_image_description" => "A yellow bus" } ] ]
    ].each do |pair_type, pairs|
      result = build_generator(fake_client(data: { "instructions" => "Encontre as relações.", "pairs" => pairs })).call(
        topic: "Objetos",
        difficulty: "medium",
        pair_count: 2,
        pair_type:
      )

      assert result.success?, "#{pair_type}: #{result.message}"
      assert_equal pair_type, result.draft.fetch("pair_type")
      image_elements = result.draft.fetch("pairs").flat_map { |pair| pair.values.select { |element| element["type"] == "image" } }
      assert_equal 2 * (pair_type == "image_image" ? 2 : 1), image_elements.length
      image_elements.each do |element|
        assert element.fetch("ai_description").present?
        assert_equal %w[ai_description type], element.keys.sort
        assert_not element.key?("blob_id")
        assert_not element.key?("url")
        assert_not element.key?("upload_key")
      end
    end
  end

  test "rejects invalid parameters before calling the API" do
    [
      { topic: " ", difficulty: "easy", pair_count: 2, pair_type: "word_word" },
      { topic: "Tema", difficulty: "expert", pair_count: 2, pair_type: "word_word" },
      { topic: "Tema", difficulty: "easy", pair_count: 1, pair_type: "word_word" },
      { topic: "Tema", difficulty: "easy", pair_count: 21, pair_type: "word_word" },
      { topic: "Tema", difficulty: "easy", pair_count: 2, pair_type: "word_audio" }
    ].each do |arguments|
      client = fake_client(data: valid_data)
      result = build_generator(client).call(**arguments)

      assert result.failure?
      assert_equal :invalid_input, result.error_code
      assert_empty client.calls
    end
  end

  test "rejects missing pair data, duplicates and extra image references" do
    invalid_data = [
      { "instructions" => "Combine", "pairs" => [ { "left_text" => "DOG", "right_text" => "CÃO" } ] },
      { "instructions" => "Combine", "pairs" => [ { "left_text" => "DOG", "right_text" => "CÃO" }, { "left_text" => " dog ", "right_text" => "cão" } ] },
      { "instructions" => "Combine", "pairs" => [ { "word" => "DOG", "image_description" => "Dog", "blob_id" => 123 }, { "word" => "CAT", "image_description" => "Cat" } ] }
    ]

    invalid_data.each_with_index do |data, index|
      pair_type = index == 2 ? "word_image" : "word_word"
      result = build_generator(fake_client(data:)).call(topic: "Tema", difficulty: "easy", pair_count: 2, pair_type:)

      assert result.failure?
      assert_equal :invalid_response, result.error_code
      assert_nil result.draft
    end
  end

  test "returns provider failures without creating a draft" do
    result = build_generator(fake_client(error_code: :timeout, message: "Timeout.")).call(
      topic: "Tema",
      difficulty: "hard",
      pair_count: 2,
      pair_type: "word_word"
    )

    assert result.failure?
    assert_equal :timeout, result.error_code
    assert_nil result.draft
  end

  private

  def fake_client(data: nil, error_code: nil, message: nil)
    FakeClient.new(Response.new(data:, error_code:, message:))
  end

  def build_generator(client)
    Exercises::MemoryGameGenerator.new(client:)
  end

  def valid_data
    { "instructions" => "Combine os pares.", "pairs" => [ { "left_text" => "DOG", "right_text" => "CÃO" }, { "left_text" => "CAT", "right_text" => "GATO" } ] }
  end
end
