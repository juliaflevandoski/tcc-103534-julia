require "test_helper"

class CrosswordAiGenerationTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  class FakeClient
    attr_reader :calls
    attr_accessor :response

    def initialize(response)
      @response = response
      @calls = []
    end

    def call(**arguments)
      @calls << arguments
      response
    end
  end

  ApiResult = Struct.new(:data, :error_code, :message, keyword_init: true) do
    def success?
      error_code.nil?
    end
  end

  setup do
    @api_response = ApiResult.new(data: {
      "words" => [
        { "word" => "APPLE", "clue" => "A fruit that can be red or green" },
        { "word" => "PEAR", "clue" => "A green fruit with a narrow top" },
        { "word" => "GRAPE", "clue" => "A small fruit that grows in bunches" }
      ]
    })
    @client = FakeClient.new(@api_response)
    @generator = Exercises::CrosswordGenerator.new(client: @client)
    @original_generator = ExercisesController.crossword_generator_service
    ExercisesController.crossword_generator_service = @generator
    @teacher = Teacher.create!(
      name: "Professor Crossword IA",
      username: "crossword-ai-#{SecureRandom.hex(6)}",
      email: "crossword-ai-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
  end

  teardown do
    ExercisesController.crossword_generator_service = @original_generator
  end

  test "new crossword form presents AI generation controls without requiring AI fields to save manually" do
    get new_exercise_url

    assert_response :success
    assert_select "dialog[data-exercise-form-target='crosswordAiModal']"
    assert_select "button[data-action='exercise-form#openCrosswordAiModal']"
    assert_select "input[data-exercise-form-target='crosswordAiTopic'][required]", count: 0
    assert_select "select[data-exercise-form-target='crosswordAiDifficulty'][required]", count: 0
    assert_select "input[data-exercise-form-target='crosswordAiWordCount'][required]", count: 0
    assert_select "button[data-action='exercise-form#previewCrossword']", text: "Gerar prévia"
  end

  test "teacher receives builder-generated layout without saving and saves reviewed words normally" do
    assert_no_difference("Exercise.count") do
      post generate_crossword_exercises_url, params: valid_params, as: :json
    end

    assert_response :success
    draft = response.parsed_body.dig("data", "draft")
    assert_equal 3, draft.fetch("words").length
    assert draft.key?("grid")
    assert draft.key?("layout_seed")
    assert Exercises::ExerciseContentValidator.call(exercise_type: "crossword", object: draft).success?
    assert_equal 1, @client.calls.length

    draft.fetch("words").find { |word| word.fetch("word") == "APPLE" }["clue"] = "Revisada pelo professor"
    assert_difference("Exercise.count") do
      post exercises_url, params: {
        exercise: { title: "Cruzadinha revisada", exercise_type: "crossword", object: draft.to_json }
      }
    end

    saved = @teacher.exercises.order(:id).last
    assert_redirected_to exercise_url(saved)
    assert_equal "Revisada pelo professor", saved.object.fetch("words").find { |word| word.fetch("word") == "APPLE" }.fetch("clue")
    assert_equal draft.fetch("layout_seed"), saved.object.fetch("layout_seed")
    assert Exercises::ExerciseContentValidator.call(exercise_type: "crossword", object: saved.object).success?
  end

  test "invalid parameters are rejected before the API call" do
    [
      valid_params.merge(topic: " "),
      valid_params.merge(difficulty: "expert"),
      valid_params.merge(word_count: 1),
      valid_params.merge(word_count: 21),
      valid_params.merge(word_count: "invalid")
    ].each do |invalid_params|
      assert_no_difference("Exercise.count") do
        post generate_crossword_exercises_url, params: invalid_params, as: :json
      end
      assert_response :unprocessable_entity
    end
    assert_empty @client.calls
  end

  test "builder-rejected or duplicate words return controlled failures without persistence" do
    @client.response = ApiResult.new(data: {
      "words" => [ { "word" => "Maçã", "clue" => "Fruta" }, { "word" => "MACA", "clue" => "Repetida" } ]
    })
    assert_no_difference("Exercise.count") do
      post generate_crossword_exercises_url, params: valid_params.merge(word_count: 2), as: :json
    end
    assert_response :bad_gateway
    assert_includes response.parsed_body.dig("errors", 0, "message"), "repetida"
  end

  test "students and unauthenticated users cannot generate crosswords" do
    delete logout_url
    post generate_crossword_exercises_url, params: valid_params, as: :json
    assert_response :unauthorized
    assert_empty @client.calls

    student = Student.create!(
      name: "Aluno Crossword IA",
      username: "crossword-ai-student-#{SecureRandom.hex(6)}",
      email: "crossword-ai-student-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
    post generate_crossword_exercises_url, params: valid_params, as: :json
    assert_response :forbidden
    assert_empty @client.calls
  end

  private

  def valid_params
    { topic: "Fruit", difficulty: "medium", word_count: 3 }
  end
end
