require "test_helper"

class Exercises::QuizGeneratorTest < ActiveSupport::TestCase
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

  setup do
    @quiz = {
      "questions" => [
        multiple_choice_question("Quanto é 2 + 2?", correct: "four"),
        {
          "question_type" => "true_false",
          "statement" => "A água congela a 0 °C em condições padrão?",
          "correct_option_ids" => [ "true" ]
        },
        {
          "question_type" => "short_answer",
          "statement" => "Qual é a capital do Brasil?",
          "correct_answer" => "Brasília"
        }
      ]
    }
  end

  test "generates a mixed quiz using the existing Ludus object contract" do
    client = fake_client(data: @quiz)
    result = build_generator(client).call(
      topic: "Matemática e conhecimentos gerais",
      difficulty: "medium",
      question_count: 3,
      question_types: %w[multiple_choice true_false short_answer]
    )

    assert result.success?
    assert_equal @quiz, result.quiz
    assert_equal %w[multiple_choice true_false short_answer], result.quiz.fetch("questions").pluck("question_type")
    assert_equal 1, client.calls.length
    call = client.calls.fetch(0)
    assert_includes call.fetch(:instructions), "Médio"
    assert_includes call.fetch(:instructions), "easy: Fácil"
    assert_includes call.fetch(:instructions), "hard: Difícil"
    assert_includes call.fetch(:instructions), "Aplique o nível selecionado: medium."
    assert_includes call.fetch(:instructions), "revisão do professor"
    assert_includes call.fetch(:input), "Matemática e conhecimentos gerais"
    assert_equal 3, call.dig(:schema, "properties", "questions", "minItems")
    assert_equal 3, call.dig(:schema, "properties", "questions", "maxItems")
    assert_equal %w[multiple_choice true_false short_answer], call.dig(:schema, "properties", "questions", "items", "anyOf").map { |branch| branch.dig("properties", "question_type", "enum").first }
  end

  test "each difficulty level adds its quiz-specific reasoning criteria" do
    criteria = {
      "easy" => "reconhecimento e compreensão de conceitos fundamentais",
      "medium" => "aplicação e interpretação de conceitos em situações familiares",
      "hard" => "análise e comparação de conceitos, aplicação em contextos novos"
    }
    prompts = criteria.map do |difficulty, criterion|
      client = fake_client(data: @quiz)
      result = build_generator(client).call(
        topic: "Ciências naturais",
        difficulty:,
        question_count: @quiz.fetch("questions").length,
        question_types: Exercises::ExerciseContentValidator::QUESTION_TYPES
      )
      call = client.calls.fetch(0)

      assert result.success?
      assert_includes call.fetch(:instructions), criterion
      assert_includes call.fetch(:instructions), "Aplique o nível selecionado: #{difficulty}."
      assert_includes call.fetch(:input), "Nível: #{difficulty}"
      assert_includes call.fetch(:input), "Quantidade de questões: #{@quiz.fetch("questions").length}"
      call.fetch(:instructions)
    end

    assert_equal 3, prompts.uniq.length
  end

  test "accepts one question type as a string and both inclusive question-count limits" do
    [ 1, 20 ].each do |count|
      questions = Array.new(count) { |index| multiple_choice_question("Questão única #{index + 1}?") }
      client = fake_client(data: { "questions" => questions })
      result = build_generator(client).call(topic: "Matemática", difficulty: "easy", question_count: count, question_types: "multiple_choice")

      assert result.success?, "count #{count}: #{result.message}"
      assert_equal count, result.quiz.fetch("questions").length
      assert_equal [ "multiple_choice" ], client.calls.fetch(0).dig(:schema, "properties", "questions", "items", "anyOf").map { |branch| branch.dig("properties", "question_type", "enum").first }
    end
  end

  test "rejects missing required inputs before calling the communication service" do
    [
      {},
      { topic: "Matemática", difficulty: "easy" },
      { topic: "Matemática", question_count: 1 },
      { difficulty: "easy", question_count: 1 }
    ].each do |arguments|
      client = fake_client(data: @quiz)
      result = build_generator(client).call(**arguments)

      assert result.failure?
      assert_equal :invalid_input, result.error_code
      assert_empty client.calls
    end
  end

  test "rejects blank or invalid topics before calling the communication service" do
    [ "", "  ", nil, 42 ].each do |topic|
      client = fake_client(data: @quiz)
      result = build_generator(client).call(topic:, difficulty: "easy", question_count: 1)

      assert result.failure?
      assert_equal :invalid_input, result.error_code
      assert_empty client.calls
    end
  end

  test "rejects question counts outside the inclusive limits or with invalid values" do
    [ 0, 21, "", "many", 1.5, true ].each do |count|
      client = fake_client(data: @quiz)
      result = build_generator(client).call(topic: "Ciências", difficulty: "medium", question_count: count)

      assert result.failure?
      assert_equal :invalid_input, result.error_code
      assert_empty client.calls
    end
  end

  test "rejects empty or unsupported difficulty values before calling the communication service" do
    [ nil, "", "easy ", "beginner", "Fácil" ].each do |difficulty|
      client = fake_client(data: @quiz)
      result = build_generator(client).call(topic: "Ciências", difficulty:, question_count: 1)

      assert result.failure?
      assert_equal :invalid_input, result.error_code
      assert_empty client.calls
    end
  end

  test "rejects empty, duplicate, or unsupported question types before calling the communication service" do
    [ [], [ "essay" ], [ "true_false", "essay" ], [ "true_false", "true_false" ], 42 ].each do |question_types|
      client = fake_client(data: @quiz)
      result = build_generator(client).call(topic: "Ciências", difficulty: "hard", question_count: 1, question_types:)

      assert result.failure?
      assert_equal :invalid_input, result.error_code
      assert_empty client.calls
    end
  end

  test "returns communication failures without presenting a quiz" do
    client = fake_client(error_code: :rate_limited, message: "Limite da API atingido.")
    result = build_generator(client).call(topic: "Ciências", difficulty: "medium", question_count: 1)

    assert result.failure?
    assert_equal :rate_limited, result.error_code
    assert_equal "Limite da API atingido.", result.message
    assert_nil result.quiz
    assert_equal 1, client.calls.length
  end

  test "rejects malformed or non-object response data" do
    [ nil, "{invalid json", [], { "questions" => "not an array" } ].each do |data|
      client = fake_client(data:)
      result = build_generator(client).call(topic: "Ciências", difficulty: "easy", question_count: 1)

      assert result.failure?
      assert_equal :invalid_response, result.error_code
      assert_nil result.quiz
    end
  end

  test "rejects missing required fields and malformed answer structures" do
    invalid_quizzes = [
      { "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta sem resposta." } ] },
      { "questions" => [ { "question_type" => "multiple_choice", "statement" => "Sem gabarito.", "options" => [ { "id" => "a", "text" => "A" }, { "id" => "b", "text" => "B" } ], "correct_option_ids" => [ "missing" ] } ] },
      { "questions" => [ { "question_type" => "true_false", "statement" => "Valor inesperado?", "correct_option_ids" => [ "yes" ] } ] },
      { "questions" => [ 42 ] },
      { "questions" => [ { "question_type" => "multiple_choice", "statement" => "Opções malformadas?", "options" => [ 42 ], "correct_option_ids" => [ "a" ] } ] },
      { "questions" => [ multiple_choice_question("Alternativas duplicadas?", duplicate_options: true) ] },
      { "questions" => [ { "question_type" => "short_answer", "statement" => "Enunciado repetido?", "correct_answer" => "sim" }, { "question_type" => "true_false", "statement" => "  ENUNCIADO   REPETIDO? ", "correct_option_ids" => [ "true" ] } ] }
    ]

    invalid_quizzes.each do |quiz|
      client = fake_client(data: quiz)
      result = build_generator(client).call(
        topic: "Ciências",
        difficulty: "easy",
        question_count: quiz.fetch("questions").length,
        question_types: Exercises::ExerciseContentValidator::QUESTION_TYPES
      )

      assert result.failure?
      assert_equal :invalid_response, result.error_code
      assert_nil result.quiz
    end
  end

  test "rejects a response with a different number or an unrequested question type" do
    [
      { "questions" => [] },
      { "questions" => [ @quiz.fetch("questions").first, @quiz.fetch("questions")[1] ] },
      { "questions" => [ @quiz.fetch("questions")[1] ] }
    ].each do |quiz|
      client = fake_client(data: quiz)
      result = build_generator(client).call(
        topic: "Ciências",
        difficulty: "easy",
        question_count: 1,
        question_types: [ "multiple_choice" ]
      )

      assert result.failure?
      assert_equal :invalid_response, result.error_code
    end
  end

  private

  def fake_client(data: nil, error_code: nil, message: nil)
    FakeClient.new(Response.new(data:, error_code:, message:))
  end

  def build_generator(client)
    Exercises::QuizGenerator.new(client:)
  end

  def multiple_choice_question(statement, correct: "a", duplicate_options: false)
    options = [ { "id" => "a", "text" => "Quatro" }, { "id" => "b", "text" => duplicate_options ? " quatro " : "Cinco" } ]
    correct_id = correct == "four" ? "a" : correct
    {
      "question_type" => "multiple_choice",
      "statement" => statement,
      "options" => options,
      "correct_option_ids" => [ correct_id ]
    }
  end
end
