require "test_helper"

class OrderingAiGenerationTest < ActionDispatch::IntegrationTest
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
      "instructions" => "Ordene as etapas para plantar uma semente.",
      "ordered_labels" => [ "Preparar a terra", "Colocar a semente", "Regar o solo" ]
    })
    @client = FakeClient.new(@api_response)
    @generator = Exercises::OrderingGenerator.new(client: @client)
    @original_generator = ExercisesController.ordering_generator_service
    ExercisesController.ordering_generator_service = @generator
    @teacher = Teacher.create!(
      name: "Professor Ordenação IA",
      username: "ordering-ai-#{SecureRandom.hex(6)}",
      email: "ordering-ai-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
  end

  teardown do
    ExercisesController.ordering_generator_service = @original_generator
  end

  test "teacher receives a validated ordering draft and saves reviewed edits normally" do
    assert_no_difference("Exercise.count") do
      post generate_ordering_exercises_url, params: valid_params, as: :json
    end

    assert_response :success
    draft = response.parsed_body.dig("data", "draft")
    assert_equal %w[ai-item-1 ai-item-2 ai-item-3], draft.fetch("correct_order")
    assert_equal [ "Preparar a terra", "Colocar a semente", "Regar o solo" ], draft.fetch("items").pluck("label")
    assert Exercises::ExerciseContentValidator.call(exercise_type: "ordering", object: draft).success?
    assert_equal 1, @client.calls.length

    draft["items"][1]["label"] = "Colocar a semente na terra"
    assert_difference("Exercise.count") do
      post exercises_url, params: { exercise: { title: "Plantio", exercise_type: "ordering", object: draft.to_json } }
    end

    saved = @teacher.exercises.order(:id).last
    assert_redirected_to exercise_url(saved)
    assert_equal "Colocar a semente na terra", saved.object.fetch("items")[1].fetch("label")
    assert_equal %w[ai-item-1 ai-item-2 ai-item-3], saved.object.fetch("correct_order")
  end

  test "manual ordering saves without entering AI-only fields" do
    get new_exercise_url

    assert_response :success
    assert_select "dialog[data-exercise-form-target='orderingAiModal']"
    assert_select "button[data-action='exercise-form#openOrderingAiModal']"
    assert_select "input[data-exercise-form-target='orderingAiTopic'][required]", count: 0
    assert_select "input[data-exercise-form-target='orderingAiCount'][required]", count: 0

    object = {
      "instructions" => "Ordene os números.",
      "item_type" => "numbers",
      "items" => [ { "id" => "n1", "label" => "1" }, { "id" => "n2", "label" => "2" } ],
      "correct_order" => %w[n1 n2]
    }
    assert_difference("Exercise.count") do
      post exercises_url, params: { exercise: { title: "Ordem manual", exercise_type: "ordering", object: object.to_json } }
    end
    assert_redirected_to exercise_url(@teacher.exercises.order(:id).last)
    assert_empty @client.calls
  end

  test "invalid parameters are rejected before calling the API" do
    [
      valid_params.merge(topic: " "),
      valid_params.merge(difficulty: "expert"),
      valid_params.merge(item_count: 1),
      valid_params.merge(item_count: 21),
      valid_params.merge(item_type: "sentences")
    ].each do |invalid_params|
      assert_no_difference("Exercise.count") do
        post generate_ordering_exercises_url, params: invalid_params, as: :json
      end
      assert_response :unprocessable_entity
    end
    assert_empty @client.calls
  end

  test "unauthenticated and student requests are rejected before generation" do
    delete logout_url
    post generate_ordering_exercises_url, params: valid_params, as: :json
    assert_response :unauthorized
    assert_empty @client.calls

    student = Student.create!(
      name: "Aluno Ordenação IA",
      username: "ordering-ai-student-#{SecureRandom.hex(6)}",
      email: "ordering-ai-student-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
    post generate_ordering_exercises_url, params: valid_params, as: :json
    assert_response :forbidden
    assert_empty @client.calls
  end

  test "provider failures do not save an exercise or expose internal details" do
    @client.response = ApiResult.new(error_code: :timeout, message: "A comunicação excedeu o tempo limite.")
    assert_no_difference("Exercise.count") do
      post generate_ordering_exercises_url, params: valid_params, as: :json
    end
    assert_response :gateway_timeout

    @client.response = ApiResult.new(error_code: :rate_limited, message: "Limite de requisições atingido.")
    post generate_ordering_exercises_url, params: valid_params, as: :json
    assert_response :too_many_requests
  end

  private

  def valid_params
    { topic: "Plantio", difficulty: "medium", item_count: 3, item_type: "words" }
  end
end
