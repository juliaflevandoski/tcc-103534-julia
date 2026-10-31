require "test_helper"

class Exercises::OrderingGeneratorTest < ActiveSupport::TestCase
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

  test "builds a valid words ordering object with backend-generated IDs" do
    client = fake_client(data: {
      "instructions" => "Organize as etapas para preparar uma planta.",
      "ordered_labels" => [ "Escolher a semente", "Preparar a terra", "Regar o solo" ]
    })
    result = build_generator(client).call(topic: "Plantio", difficulty: "easy", item_count: 3, item_type: "words")

    assert result.success?
    assert_equal "words", result.draft.fetch("item_type")
    assert_equal %w[ai-item-1 ai-item-2 ai-item-3], result.draft.fetch("items").pluck("id")
    assert_equal %w[ai-item-1 ai-item-2 ai-item-3], result.draft.fetch("correct_order")
    assert Exercises::ExerciseContentValidator.call(exercise_type: "ordering", object: result.draft).success?
    assert_equal 1, client.calls.length
    assert_equal 3, client.calls.first.dig(:schema, "properties", "ordered_labels", "maxItems")
  end

  test "builds a validated multiple sentence object with distinct IDs and original word order" do
    client = fake_client(data: {
      "instructions" => "Organize as frases sobre o tema.",
      "sentences" => [ "I think I can.", "A ordem preserva vírgulas, pontos e acentos." ]
    })
    result = build_generator(client).call(
      topic: "Confiança e aprendizado",
      difficulty: "medium",
      format: "multiple_sentences",
      sentence_count: 2
    )

    assert result.success?, result.message
    assert_equal "multiple_sentences", result.draft.fetch("format")
    assert_equal [ "I", "think", "I", "can." ], result.draft.fetch("sentences").first.fetch("items").pluck("label")
    assert_equal "vírgulas,", result.draft.fetch("sentences").last.fetch("items")[3].fetch("label")
    sentence_ids = result.draft.fetch("sentences").pluck("id")
    word_ids = result.draft.fetch("sentences").flat_map { |sentence| sentence.fetch("items").pluck("id") }
    assert_equal 2, sentence_ids.uniq.length
    assert_equal word_ids.length, word_ids.uniq.length
    result.draft.fetch("sentences").each do |sentence|
      assert_equal sentence.fetch("items").pluck("id"), sentence.fetch("correct_order")
    end
    assert_not result.draft.key?("items")
    assert_not result.draft.key?("correct_order")
    assert Exercises::ExerciseContentValidator.call(exercise_type: "ordering", object: result.draft).success?
    assert_equal 2, client.calls.first.dig(:schema, "properties", "sentences", "minItems")
    assert_equal 2, client.calls.first.dig(:schema, "properties", "sentences", "maxItems")
    assert_equal Exercises::OrderingGenerator::MULTIPLE_SENTENCES_SCHEMA_NAME, client.calls.first.fetch(:schema_name)
  end

  test "multiple sentence prompts apply every approved difficulty without changing sentence count" do
    criteria = {
      "easy" => "vocabulário familiar e estrutura frasal direta",
      "medium" => "vocabulário intermediário e variedade de estruturas naturais",
      "hard" => "vocabulário mais preciso e estruturas sintáticas mais elaboradas"
    }
    prompts = criteria.map do |difficulty, criterion|
      client = fake_client(data: { "instructions" => "Organize.", "sentences" => [ "Frase um.", "Frase dois?" ] })
      result = build_generator(client).call(
        topic: "Aprendizagem",
        difficulty:,
        format: "multiple_sentences",
        sentence_count: 2
      )
      call = client.calls.fetch(0)

      assert result.success?, "#{difficulty}: #{result.message}"
      assert_includes call.fetch(:instructions), criterion
      assert_includes call.fetch(:instructions), "Aplique o nível selecionado: #{difficulty}."
      assert_includes call.fetch(:instructions), "sem presumir inglês"
      assert_includes call.fetch(:input), "Quantidade exata de frases completas: 2"
      call.fetch(:instructions)
    end

    assert_equal 3, prompts.uniq.length
  end

  test "rejects invalid multiple sentence counts before calling the API" do
    [ 1, 21, "invalid", 1.5, true ].each do |sentence_count|
      client = fake_client(data: valid_multiple_sentence_data)
      result = build_generator(client).call(
        topic: "Tema",
        difficulty: "easy",
        format: "multiple_sentences",
        sentence_count:
      )

      assert result.failure?
      assert_equal :invalid_input, result.error_code
      assert_empty client.calls
    end
  end

  test "accepts the minimum and maximum multiple sentence counts" do
    [ 2, 20 ].each do |sentence_count|
      sentences = Array.new(sentence_count) { |index| "Frase completa número #{index + 1}." }
      client = fake_client(data: { "instructions" => "Organize as frases.", "sentences" => sentences })
      result = build_generator(client).call(
        topic: "Tema",
        difficulty: "medium",
        format: "multiple_sentences",
        sentence_count:
      )

      assert result.success?, "count #{sentence_count}: #{result.message}"
      assert_equal sentence_count, result.draft.fetch("sentences").length
      assert_equal sentence_count, client.calls.first.dig(:schema, "properties", "sentences", "maxItems")
    end
  end

  test "rejects unsupported format before calling the API" do
    client = fake_client(data: valid_data)
    result = build_generator(client).call(
      topic: "Tema",
      difficulty: "easy",
      format: "unknown",
      item_count: 2,
      item_type: "words"
    )

    assert result.failure?
    assert_equal :invalid_input, result.error_code
    assert_empty client.calls
  end

  test "rejects malformed or wrong-count multiple sentence responses" do
    invalid_responses = [
      { "instructions" => "Organize.", "sentences" => [ "Frase completa aqui." ] },
      { "instructions" => "Organize.", "sentences" => [ "Frase completa aqui.", "  " ] },
      { "instructions" => "Organize.", "sentences" => [ "Sozinha", "Frase completa aqui." ] },
      { "instructions" => "Organize.", "sentences" => [ "Frase completa aqui.", 42 ] },
      { "instructions" => " ", "sentences" => [ "Frase completa aqui.", "Outra frase completa." ] },
      { "instructions" => "Organize.", "sentences" => [ "Frase completa aqui.", "Outra frase completa." ], "extra" => "field" }
    ]

    invalid_responses.each do |data|
      result = build_generator(fake_client(data:)).call(
        topic: "Tema",
        difficulty: "medium",
        format: "multiple_sentences",
        sentence_count: 2
      )

      assert result.failure?, data.inspect
      assert_equal :invalid_response, result.error_code
      assert_nil result.draft
    end
  end

  test "rejects wrong-count, empty, short, or malformed multiple sentence responses" do
    invalid_responses = [
      { "instructions" => "Organize", "sentences" => [ "Uma frase completa aqui." ] },
      { "instructions" => "Organize", "sentences" => [ "Uma frase completa aqui.", " " ] },
      { "instructions" => "Organize", "sentences" => [ "Sozinha", "Outra frase completa." ] },
      { "instructions" => " ", "sentences" => [ "Uma frase completa.", "Outra frase completa." ] },
      { "instructions" => "Organize", "sentences" => [ "Uma frase completa.", "Outra frase completa." ], "extra" => "campo" }
    ]

    invalid_responses.each do |data|
      result = build_generator(fake_client(data:)).call(
        topic: "Tema",
        difficulty: "easy",
        format: "multiple_sentences",
        sentence_count: 2
      )

      assert result.failure?
      assert_equal :invalid_response, result.error_code
      assert_nil result.draft
    end
  end

  test "missing format and explicit single sequence preserve the legacy contract" do
    [ nil, "single_sequence" ].each do |format|
      arguments = { topic: "Plantio", difficulty: "easy", item_count: 2, item_type: "words" }
      arguments[:format] = format if format
      result = build_generator(fake_client(data: valid_data)).call(**arguments)

      assert result.success?
      assert_equal %w[ai-item-1 ai-item-2], result.draft.fetch("correct_order")
      assert_not result.draft.key?("format")
      assert_not result.draft.key?("sentences")
    end
  end

  test "each difficulty level adds ordering-specific sequence criteria without changing item count" do
    criteria = {
      "easy" => "sequências curtas com relações evidentes",
      "medium" => "compreender um processo ou critério de ordenação familiar",
      "hard" => "sequências conceitualmente mais complexas"
    }
    prompts = criteria.map do |difficulty, criterion|
      client = fake_client(data: valid_data)
      result = build_generator(client).call(topic: "Etapas de um processo", difficulty:, item_count: 2, item_type: "words")
      call = client.calls.fetch(0)

      assert result.success?
      assert_includes call.fetch(:instructions), criterion
      assert_includes call.fetch(:instructions), "Aplique o nível selecionado: #{difficulty}."
      assert_includes call.fetch(:input), "Dificuldade: #{difficulty}"
      assert_includes call.fetch(:input), "Quantidade exata de itens: 2"
      assert_includes call.fetch(:instructions), "uma única sequência correta"
      call.fetch(:instructions)
    end

    assert_equal 3, prompts.uniq.length
  end

  test "normalizes numeric items and preserves their intended order" do
    result = build_generator(fake_client(data: {
      "instructions" => "Ordene do menor para o maior.",
      "ordered_labels" => [ "-2", "01", "10" ]
    })).call(topic: "Inteiros", difficulty: "medium", item_count: 3, item_type: "numbers")

    assert result.success?
    assert_equal %w[-2 1 10], result.draft.fetch("items").pluck("label")
    assert_equal "numbers", result.draft.fetch("item_type")
    assert Exercises::ExerciseContentValidator.call(exercise_type: "ordering", object: result.draft).success?
  end

  test "rejects invalid parameters before calling the API" do
    [
      { topic: " ", difficulty: "easy", item_count: 2, item_type: "words" },
      { topic: "Tema", difficulty: "expert", item_count: 2, item_type: "words" },
      { topic: "Tema", difficulty: "easy", item_count: 1, item_type: "words" },
      { topic: "Tema", difficulty: "easy", item_count: 21, item_type: "words" },
      { topic: "Tema", difficulty: "easy", item_count: 2, item_type: "sentences" }
    ].each do |arguments|
      client = fake_client(data: valid_data)
      result = build_generator(client).call(**arguments)

      assert result.failure?
      assert_equal :invalid_input, result.error_code
      assert_empty client.calls
    end
  end

  test "rejects duplicate, malformed, missing, or incompatible AI content" do
    invalid_data = [
      { "instructions" => "Ordene", "ordered_labels" => [ "Um", " um " ] },
      { "instructions" => "Ordene", "ordered_labels" => [ "1", "01" ] },
      { "instructions" => "Ordene", "ordered_labels" => [ "Um", "Dois", "Três" ] },
      { "instructions" => " ", "ordered_labels" => [ "Um", "Dois" ] },
      { "instructions" => "Ordene", "ordered_labels" => [ "não inteiro", "2" ] },
      { "instructions" => "Ordene", "ordered_labels" => [ "Um", "Dois" ], "extra" => "campo" }
    ]

    invalid_data.each_with_index do |data, index|
      item_type = index == 1 || index == 4 ? "numbers" : "words"
      result = build_generator(fake_client(data:)).call(topic: "Tema", difficulty: "hard", item_count: 2, item_type:)

      assert result.failure?
      assert_equal :invalid_response, result.error_code
      assert_nil result.draft
    end
  end

  test "returns provider failures without saving or creating a draft" do
    result = build_generator(fake_client(error_code: :service_unavailable, message: "Serviço indisponível.")).call(
      topic: "Tema",
      difficulty: "hard",
      item_count: 2,
      item_type: "words"
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
    Exercises::OrderingGenerator.new(client:)
  end

  def valid_data
    { "instructions" => "Ordene", "ordered_labels" => [ "Um", "Dois" ] }
  end

  def valid_multiple_sentence_data
    { "instructions" => "Organize.", "sentences" => [ "Uma frase completa.", "Outra frase completa." ] }
  end
end
