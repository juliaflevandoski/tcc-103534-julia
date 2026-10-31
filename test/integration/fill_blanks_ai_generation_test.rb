require "test_helper"

class FillBlanksAiGenerationTest < ActionDispatch::IntegrationTest
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

  class FakeHttp
    attr_accessor :use_ssl, :open_timeout, :read_timeout, :write_timeout
    attr_reader :last_request

    def initialize(response)
      @response = response
    end

    def request(request)
      @last_request = request
      @response
    end
  end

  HttpResponse = Struct.new(:code, :body)

  ApiResult = Struct.new(:data, :error_code, :message, keyword_init: true) do
    def success?
      error_code.nil?
    end
  end

  setup do
    @api_response = ApiResult.new(
      data: {
        "text_template" => "A água ferve a {{1}} graus e congela a {{2}} graus.",
        "blank_answers" => [ "100", "0" ]
      }
    )
    @client = FakeClient.new(@api_response)
    @generator = Exercises::FillBlanksGenerator.new(client: @client)
    @original_generator = ExercisesController.fill_blanks_generator_service
    ExercisesController.fill_blanks_generator_service = @generator
    @teacher = Teacher.create!(
      name: "Professor Lacunas IA",
      username: "blank-ai-#{SecureRandom.hex(6)}",
      email: "blank-ai-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
  end

  teardown do
    ExercisesController.fill_blanks_generator_service = @original_generator
  end

  test "teacher receives a validated fill blanks draft and saves reviewed edits normally" do
    assert_no_difference("Exercise.count") do
      post generate_fill_blanks_exercises_url, params: valid_params, as: :json
    end

    assert_response :success
    draft = response.parsed_body.dig("data", "draft")
    assert_equal "A água ferve a {{1}} graus e congela a {{2}} graus.", draft.fetch("text_template")
    assert_equal({ "1" => "100", "2" => "0" }, draft.fetch("blanks"))
    assert Exercises::ExerciseContentValidator.call(exercise_type: "fill_blanks", object: draft).success?
    assert_equal 1, @client.calls.length
    assert_includes @client.calls.first.fetch(:input), "Estados da água"
    assert_includes @client.calls.first.fetch(:input), "Dificuldade: medium"
    assert_includes @client.calls.first.fetch(:input), "Quantidade exata de lacunas: 2"

    draft["blanks"]["1"] = "cem"
    assert_difference("Exercise.count") do
      post exercises_url, params: {
        exercise: { title: "Estados da água", exercise_type: "fill_blanks", object: draft.to_json }
      }
    end

    saved = @teacher.exercises.order(:id).last
    assert_equal draft, saved.object
    assert_redirected_to exercise_url(saved)
  end

  test "endpoint uses the existing HTTP client with a simulated OpenAI response" do
    structured_data = {
      "text_template" => "A água ferve a {{1}} graus.",
      "blank_answers" => [ "100" ]
    }
    response_body = {
      "status" => "completed",
      "output" => [
        { "type" => "message", "content" => [ { "type" => "output_text", "text" => structured_data.to_json } ] }
      ]
    }.to_json
    http = FakeHttp.new(HttpResponse.new("200", response_body))
    client = OpenaiResponsesClient.new(
      http_factory: ->(_host, _port) { http },
      api_key_provider: -> { "test-only-key" }
    )
    ExercisesController.fill_blanks_generator_service = Exercises::FillBlanksGenerator.new(client:)

    assert_no_difference("Exercise.count") do
      post generate_fill_blanks_exercises_url, params: valid_params.merge(blank_count: 1), as: :json
    end

    assert_response :success
    assert_equal({ "text_template" => "A água ferve a {{1}} graus.", "blanks" => { "1" => "100" } }, response.parsed_body.dig("data", "draft"))
    request_payload = JSON.parse(http.last_request.body)
    assert_equal OpenaiResponsesClient::MODEL, request_payload.fetch("model")
    assert_equal "json_schema", request_payload.dig("text", "format", "type")
    assert_equal true, request_payload.dig("text", "format", "strict")
  end

  test "generation modal controls are not required to save a manual fill blanks exercise" do
    get new_exercise_url

    assert_response :success
    assert_select "dialog[data-exercise-form-target='fillBlanksAiModal']"
    assert_select "button[data-action='exercise-form#openFillBlanksAiModal']"
    assert_select "input[data-exercise-form-target='fillBlanksAiTopic'][required]", count: 0
    assert_select "select[data-exercise-form-target='fillBlanksAiDifficulty'][required]", count: 0
    assert_select "input[data-exercise-form-target='fillBlanksAiCount'][required]", count: 0

    object = { "text_template" => "A {{1}}.", "blanks" => { "1" => "lacuna" } }
    assert_difference("Exercise.count") do
      post exercises_url, params: {
        exercise: { title: "Lacuna manual", exercise_type: "fill_blanks", object: object.to_json }
      }
    end
    assert_redirected_to exercise_url(@teacher.exercises.order(:id).last)
    assert_empty @client.calls
  end

  test "invalid parameters are rejected before the OpenAI client is called" do
    [
      valid_params.merge(topic: " "),
      valid_params.merge(difficulty: "expert"),
      valid_params.merge(blank_count: 0),
      valid_params.merge(blank_count: 21),
      valid_params.merge(blank_count: "invalid")
    ].each do |invalid_params|
      assert_no_difference("Exercise.count") do
        post generate_fill_blanks_exercises_url, params: invalid_params, as: :json
      end

      assert_response :unprocessable_entity
    end

    assert_empty @client.calls
  end

  test "endpoint invokes the generator class contract and rejects invalid input before networking" do
    ExercisesController.fill_blanks_generator_service = Exercises::FillBlanksGenerator
    assert_no_difference("Exercise.count") do
      post generate_fill_blanks_exercises_url, params: valid_params.merge(blank_count: 0), as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "generation", response.parsed_body.dig("errors", 0, "field")
  end

  test "unauthenticated and student requests are rejected before generation" do
    delete logout_url
    post generate_fill_blanks_exercises_url, params: valid_params, as: :json
    assert_response :unauthorized
    assert_empty @client.calls

    student = Student.create!(
      name: "Aluno Lacunas IA",
      username: "blank-ai-student-#{SecureRandom.hex(6)}",
      email: "blank-ai-student-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
    post generate_fill_blanks_exercises_url, params: valid_params, as: :json

    assert_response :forbidden
    assert_empty @client.calls
  end

  test "provider failures and incompatible responses remain controlled and do not save" do
    @client.response = ApiResult.new(error_code: :timeout, message: "A comunicação excedeu o tempo limite.")
    assert_no_difference("Exercise.count") do
      post generate_fill_blanks_exercises_url, params: valid_params, as: :json
    end
    assert_response :gateway_timeout
    assert_nil response.parsed_body["data"]

    @client.response = ApiResult.new(data: { "text_template" => "{{1}} e {{3}}", "blank_answers" => [ "um", "dois" ] })
    assert_no_difference("Exercise.count") do
      post generate_fill_blanks_exercises_url, params: valid_params, as: :json
    end
    assert_response :bad_gateway
    assert_includes response.parsed_body.dig("errors", 0, "message"), "formato"
  end

  test "unexpected generator exceptions return a generic response without leaking exception details" do
    generator = Object.new
    generator.define_singleton_method(:call) do |**_arguments|
      raise RuntimeError, "Bearer secret provider detail"
    end
    ExercisesController.fill_blanks_generator_service = generator

    assert_no_difference("Exercise.count") do
      post generate_fill_blanks_exercises_url, params: valid_params, as: :json
    end

    assert_response :internal_server_error
    assert_equal "Não foi possível gerar o exercício agora. Tente novamente.", response.parsed_body.dig("errors", 0, "message")
    assert_not_includes response.body, "Bearer secret"
    assert_not_includes response.body, "provider detail"
  end

  private

  def valid_params
    { topic: "Estados da água", difficulty: "medium", blank_count: 2 }
  end
end
