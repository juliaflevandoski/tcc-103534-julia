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
end
