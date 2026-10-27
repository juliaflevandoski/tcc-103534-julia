require "test_helper"

class Exercises::FillBlanksGeneratorTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls

    def initialize(result: nil, error: nil)
      @result = result
      @error = error
      @calls = []
    end

    def call(**arguments)
      @calls << arguments
      raise @error if @error

      @result
    end
  end

  Response = Struct.new(:data, :error_code, :message, keyword_init: true) do
    def success?
      error_code.nil?
    end
  end

  test "generates and normalizes a valid fill blanks object accepted by the existing validator" do
    client = fake_client(data: {
      "text_template" => "A água ferve a {{1}} graus Celsius e congela a {{2}} graus.",
      "blank_answers" => [ "100", "0" ]
    })
    result = build_generator(client).call(topic: "Estados da água", difficulty: "medium", blank_count: 2)

    assert result.success?
    assert_equal({
      "text_template" => "A água ferve a {{1}} graus Celsius e congela a {{2}} graus.",
      "blanks" => { "1" => "100", "2" => "0" }
    }, result.draft)
    assert Exercises::ExerciseContentValidator.call(exercise_type: "fill_blanks", object: result.draft).success?
    assert_equal 1, client.calls.length
    assert_equal 2, client.calls.first.dig(:schema, "properties", "blank_answers", "minItems")
    assert_equal 2, client.calls.first.dig(:schema, "properties", "blank_answers", "maxItems")
    assert_includes client.calls.first.fetch(:instructions), "candidato para revisão"
    assert_includes client.calls.first.fetch(:instructions), "Aplique o nível selecionado: medium"
  end

  test "rejects invalid common parameters and blank counts before calling the API" do
    [
      { topic: " ", difficulty: "easy", blank_count: 1 },
      { topic: "Ciências", difficulty: "expert", blank_count: 1 },
      { topic: "Ciências", difficulty: "easy", blank_count: 0 },
      { topic: "Ciências", difficulty: "easy", blank_count: 21 },
      { topic: "Ciências", difficulty: "easy", blank_count: "many" },
      { topic: "Ciências", difficulty: "easy", blank_count: 1.5 }
    ].each do |arguments|
      client = fake_client(data: valid_data)
      result = build_generator(client).call(**arguments)

      assert result.failure?
      assert_equal :invalid_input, result.error_code
      assert_empty client.calls
    end
  end

  test "rejects inconsistent markers, missing answers, and invalid final content" do
    invalid_data = [
      { "text_template" => "Texto sem marcadores.", "blank_answers" => [ "resposta" ] },
      { "text_template" => "{{1}} e {{1}}", "blank_answers" => [ "uma", "duas" ] },
      { "text_template" => "{{1}} e {{3}}", "blank_answers" => [ "uma", "três" ] },
      { "text_template" => "{{1}}", "blank_answers" => [ "" ] },
      { "text_template" => "{{1}}", "blank_answers" => [ "uma" ], "extra" => "campo" }
    ]

    invalid_data.each do |data|
      result = build_generator(fake_client(data:)).call(topic: "Ciências", difficulty: "easy", blank_count: 2)

      assert result.failure?
      assert_equal :invalid_response, result.error_code
      assert_nil result.draft
    end
  end

  test "returns provider failures and unexpected client errors as controlled failures" do
    failed_response = Response.new(error_code: :timeout, message: "A comunicação excedeu o tempo limite.")
    result = build_generator(fake_client(result: failed_response)).call(topic: "Ciências", difficulty: "hard", blank_count: 2)

    assert result.failure?
    assert_equal :timeout, result.error_code
    assert_equal "A comunicação excedeu o tempo limite.", result.message

    raised_result = build_generator(fake_client(error: RuntimeError.new("Bearer should not leak"))).call(
      topic: "Ciências",
      difficulty: "hard",
      blank_count: 2
    )
    assert raised_result.failure?
    assert_equal :communication_error, raised_result.error_code
    assert_not_includes raised_result.message, "Bearer"
  end

  private

  def fake_client(data: nil, result: nil, error: nil)
    result ||= Response.new(data:, error_code: nil, message: nil)
    FakeClient.new(result:, error:)
  end

  def build_generator(client)
    Exercises::FillBlanksGenerator.new(client:)
  end

  def valid_data
    { "text_template" => "A água ferve a {{1}} graus.", "blank_answers" => [ "100" ] }
  end
end
