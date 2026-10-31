require "test_helper"

class Exercises::CrosswordGeneratorTest < ActiveSupport::TestCase
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

  test "builds and validates the crossword layout from AI words and clues" do
    words = [
      { "word" => "Maçã", "clue" => "Fruta que pode ser vermelha ou verde" },
      { "word" => "CÃO", "clue" => "Animal doméstico que late" },
      { "word" => "GATO", "clue" => "Animal doméstico que mia" }
    ]
    client = fake_client(data: { "words" => words })
    result = build_generator(client).call(topic: "Animais e frutas", difficulty: "easy", word_count: 3)

    assert result.success?, result.message
    assert_equal 3, result.draft.fetch("words").length
    assert_equal %w[CAO GATO MACA], result.draft.fetch("words").pluck("normalized").sort
    assert_equal "Maçã", result.draft.fetch("words").find { |entry| entry.fetch("word") == "Maçã" }.fetch("word")
    assert result.draft.key?("grid")
    assert result.draft.key?("layout_seed")
    assert Exercises::ExerciseContentValidator.call(exercise_type: "crossword", object: result.draft).success?
    assert_equal 1, client.calls.length
    assert_equal 3, client.calls.first.dig(:schema, "properties", "words", "maxItems")
    assert_includes client.calls.first.fetch(:instructions), "o Ludus construirá a grade"
  end

  test "each difficulty level adds crossword-specific vocabulary and clue criteria" do
    criteria = {
      "easy" => "termos familiares ao tema e pistas diretas",
      "medium" => "pistas que exijam interpretar o enunciado ou aplicar conceitos",
      "hard" => "relações conceituais e inferências mais elaboradas"
    }
    prompts = criteria.map do |difficulty, criterion|
      client = fake_client(data: valid_data)
      result = build_generator(client).call(topic: "Frutas", difficulty:, word_count: 2)
      call = client.calls.fetch(0)

      assert result.success?, result.message
      assert_includes call.fetch(:instructions), criterion
      assert_includes call.fetch(:instructions), "Aplique o nível selecionado: #{difficulty}."
      assert_includes call.fetch(:input), "Dificuldade: #{difficulty}"
      assert_includes call.fetch(:input), "Quantidade exata de palavras: 2"
      assert_includes call.fetch(:instructions), "não permitir várias respostas igualmente válidas"
      call.fetch(:instructions)
    end

    assert_equal 3, prompts.uniq.length
  end

  test "rejects invalid parameters before calling the API" do
    [
      { topic: " ", difficulty: "easy", word_count: 2 },
      { topic: "Tema", difficulty: "expert", word_count: 2 },
      { topic: "Tema", difficulty: "easy", word_count: 1 },
      { topic: "Tema", difficulty: "easy", word_count: 21 },
      { topic: "Tema", difficulty: "easy", word_count: "invalid" }
    ].each do |arguments|
      client = fake_client(data: valid_data)
      result = build_generator(client).call(**arguments)

      assert result.failure?
      assert_equal :invalid_input, result.error_code
      assert_empty client.calls
    end
  end

  test "rejects malformed, duplicate, or builder-incompatible AI words" do
    invalid_words = [
      [ { "word" => "APPLE", "clue" => "Fruit" } ],
      [ { "word" => "ONE TWO", "clue" => "A phrase" }, { "word" => "DOG", "clue" => "Animal" } ],
      [ { "word" => "Maçã", "clue" => "Fruit" }, { "word" => "MACA", "clue" => "Same answer" } ],
      [ { "word" => "APPLE", "clue" => " " }, { "word" => "PEAR", "clue" => "Fruit" } ],
      [ { "word" => "A" * (Exercises::CrosswordBuilder::MAX_GRID_SIZE + 1), "clue" => "Too long" }, { "word" => "DOG", "clue" => "Animal" } ]
    ]

    invalid_words.each do |words|
      result = build_generator(fake_client(data: { "words" => words })).call(
        topic: "Tema",
        difficulty: "medium",
        word_count: [ words.length, 2 ].max
      )

      assert result.failure?
      assert_equal :invalid_response, result.error_code
      assert_nil result.draft
    end
  end

  test "returns provider failures without producing a layout" do
    result = build_generator(fake_client(error_code: :service_unavailable, message: "Serviço indisponível.")).call(
      topic: "Tema",
      difficulty: "hard",
      word_count: 2
    )

    assert result.failure?
    assert_equal :service_unavailable, result.error_code
    assert_nil result.draft
  end

  private

  def fake_client(data: nil, error_code: nil, message: nil)
    FakeClient.new(Response.new(data:, error_code:, message:))
  end

  def build_generator(client)
    Exercises::CrosswordGenerator.new(client:)
  end

  def valid_data
    { "words" => [ { "word" => "APPLE", "clue" => "Fruit" }, { "word" => "PEAR", "clue" => "Fruit" } ] }
  end
end
