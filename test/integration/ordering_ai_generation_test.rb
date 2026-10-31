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
    assert_includes @client.calls.first.fetch(:input), "Plantio"
    assert_includes @client.calls.first.fetch(:input), "Dificuldade: medium"
    assert_includes @client.calls.first.fetch(:input), "Quantidade exata de itens: 3"
    assert_includes @client.calls.first.fetch(:input), "Tipo de item: words"

    draft["items"][1]["label"] = "Colocar a semente na terra"
    assert_difference("Exercise.count") do
      post exercises_url, params: { exercise: { title: "Plantio", exercise_type: "ordering", object: draft.to_json } }
    end

    saved = @teacher.exercises.order(:id).last
    assert_redirected_to exercise_url(saved)
    assert_equal "Colocar a semente na terra", saved.object.fetch("items")[1].fetch("label")
    assert_equal %w[ai-item-1 ai-item-2 ai-item-3], saved.object.fetch("correct_order")
  end

  test "teacher receives a validated multiple sentence draft through the endpoint without saving it" do
    @client.response = ApiResult.new(data: {
      "instructions" => "Organize as frases sobre aprendizagem.",
      "sentences" => [ "I think I can.", "A aprendizagem exige prática." ]
    })

    assert_no_difference("Exercise.count") do
      post generate_ordering_exercises_url, params: {
        topic: "Aprendizagem",
        difficulty: "hard",
        format: "multiple_sentences",
        sentence_count: 2
      }, as: :json
    end

    assert_response :success
    draft = response.parsed_body.dig("data", "draft")
    assert_equal "multiple_sentences", draft.fetch("format")
    assert_equal [ "I", "think", "I", "can." ], draft.fetch("sentences").first.fetch("items").pluck("label")
    word_ids = draft.fetch("sentences").flat_map { |sentence| sentence.fetch("items").pluck("id") }
    assert_equal word_ids.length, word_ids.uniq.length
    assert_equal draft.fetch("sentences").first.fetch("items").pluck("id"), draft.fetch("sentences").first.fetch("correct_order")
    assert_not draft.key?("items")
    assert_not draft.key?("correct_order")
    assert Exercises::ExerciseContentValidator.call(exercise_type: "ordering", object: draft).success?
    assert_equal 1, @client.calls.length
    call = @client.calls.first
    assert_includes call.fetch(:input), "Dificuldade: hard"
    assert_includes call.fetch(:input), "Quantidade exata de frases completas: 2"
    assert_equal "#{Exercises::OrderingGenerator::MULTIPLE_SENTENCES_SCHEMA_NAME}", call.fetch(:schema_name)
    assert_equal 2, call.fetch(:schema).dig("properties", "sentences", "minItems")
    assert_equal 2, call.fetch(:schema).dig("properties", "sentences", "maxItems")
  end

  test "teacher receives a validated multiple sentence draft from complete sentence text" do
    @client.response = ApiResult.new(data: {
      "instructions" => "Organize cada frase.",
      "sentences" => [ "I think I can.", "A aprendizagem exige prática." ]
    })

    assert_no_difference("Exercise.count") do
      post generate_ordering_exercises_url, params: {
        topic: "Aprendizagem",
        difficulty: "hard",
        format: "multiple_sentences",
        sentence_count: 2
      }, as: :json
    end

    assert_response :success
    draft = response.parsed_body.dig("data", "draft")
    assert_equal "multiple_sentences", draft.fetch("format")
    assert_equal [ "I", "think", "I", "can." ], draft.fetch("sentences").first.fetch("items").pluck("label")
    assert_equal [ "A", "aprendizagem", "exige", "prática." ], draft.fetch("sentences").last.fetch("items").pluck("label")
    assert_equal draft.fetch("sentences").first.fetch("items").pluck("id").length,
      draft.fetch("sentences").first.fetch("items").pluck("id").uniq.length
    assert_equal draft.fetch("sentences").first.fetch("items").pluck("id"), draft.fetch("sentences").first.fetch("correct_order")
    assert_not draft.key?("items")
    assert_not draft.key?("correct_order")
    assert Exercises::ExerciseContentValidator.call(exercise_type: "ordering", object: draft).success?
    assert_equal 1, @client.calls.length
    call = @client.calls.first
    assert_includes call.fetch(:input), "Dificuldade: hard"
    assert_includes call.fetch(:input), "Quantidade exata de frases completas: 2"
    assert_equal 2, call.fetch(:schema).dig("properties", "sentences", "minItems")
    assert_equal 2, call.fetch(:schema).dig("properties", "sentences", "maxItems")
  end

  test "endpoint rejects invalid multiple sentence count before calling the client" do
    [ 1, 21, "invalid" ].each do |sentence_count|
      assert_no_difference("Exercise.count") do
        post generate_ordering_exercises_url, params: {
          topic: "Aprendizagem",
          difficulty: "medium",
          format: "multiple_sentences",
          sentence_count:
        }, as: :json
      end
      assert_response :unprocessable_entity
    end
    assert_empty @client.calls
  end

  test "manual ordering saves without entering AI-only fields" do
    get new_exercise_url

    assert_response :success
    assert_select "select[data-exercise-form-target='orderingFormat'] option[value='single_sequence']"
    assert_select "select[data-exercise-form-target='orderingFormat'] option[value='multiple_sentences']"
    assert_select "div[data-exercise-form-target='orderingMultipleFields'][hidden]"
    assert_select "template[data-exercise-form-target='orderingSentenceTemplate'] textarea[data-ordering-sentence-text]"
    assert_select "button[data-action='exercise-form#addOrderingSentence']", text: "Adicionar frase"
    assert_select "div[data-exercise-form-target='orderingAiOpenWrapper'] button[data-action='exercise-form#openOrderingAiModal']"
    assert_select "dialog[data-exercise-form-target='orderingAiModal']"
    assert_select "button[data-action='exercise-form#openOrderingAiModal']"
    assert_select "input[data-exercise-form-target='orderingAiTopic'][required]", count: 0
    assert_select "input[data-exercise-form-target='orderingAiCount'][required]", count: 0
    assert_select "div[data-exercise-form-target='orderingAiSingleFields'] select[data-exercise-form-target='orderingAiItemType']"
    assert_select "div[data-exercise-form-target='orderingAiSingleFields'] input[data-exercise-form-target='orderingAiItemCount'][min='2'][max='20']"
    assert_select "div[data-exercise-form-target='orderingAiMultipleFields'][hidden] input[data-exercise-form-target='orderingAiSentenceCount'][min='2'][max='20']"
    assert_select "h3[data-exercise-form-target='orderingAiPreviewHeading']"
    assert_select "div[data-exercise-form-target='orderingAiSingleFields'] select[data-exercise-form-target='orderingAiItemType']"
    assert_select "div[data-exercise-form-target='orderingAiSingleFields'] input[data-exercise-form-target='orderingAiItemCount'][min='2'][max='20']"
    assert_select "div[data-exercise-form-target='orderingAiMultipleFields'][hidden] input[data-exercise-form-target='orderingAiSentenceCount'][min='2'][max='20']"
    assert_select "h3[data-exercise-form-target='orderingAiPreviewHeading']"

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

  test "teacher saves and reopens a validated multiple sentence ordering exercise" do
    object = {
      "format" => "multiple_sentences",
      "instructions" => "Organize as frases.",
      "sentences" => [
        { "id" => "sentence-one", "items" => [ { "id" => "word-one-a", "label" => "Olá," }, { "id" => "word-one-b", "label" => "mundo!" } ], "correct_order" => %w[word-one-a word-one-b] },
        { "id" => "sentence-two", "items" => [ { "id" => "word-two-a", "label" => "Olá," }, { "id" => "word-two-b", "label" => "mundo?" } ], "correct_order" => %w[word-two-a word-two-b] }
      ]
    }
    assert Exercises::ExerciseContentValidator.call(exercise_type: "ordering", object:).success?

    assert_difference("Exercise.count") do
      post exercises_url, params: { exercise: { title: "Frases embaralhadas", exercise_type: "ordering", object: object.to_json } }
    end

    saved = @teacher.exercises.order(:id).last
    assert_equal object, saved.object
    assert_redirected_to exercise_url(saved)
    follow_redirect!

    assert_response :success
    assert_select ".ordering-sentence-preview", count: 2
    assert_equal [ "Olá,", "mundo!", "Olá,", "mundo?" ], css_select(".ordering-sentence-preview li").map(&:text)
    assert_not_includes response.body, "word-one-a"
    assert_not_includes response.body, "correct_order"

    get edit_exercise_url(saved)

    assert_response :success
    assert_select "input[type='hidden'][name='exercise[object]']"
    assert_select "select[data-exercise-form-target='orderingFormat'] option[value='multiple_sentences']"
    assert_select "div[data-exercise-form-target='orderingSentencesList']"
    assert_empty @client.calls
  end

  test "teacher creates publishes associates and edits multiple sentence ordering through normal routes" do
    school_class = @teacher.school_classes.create!(name: "Turma de frases")
    post activities_url, params: { activity: { class_id: school_class.id, title: "Aula de frases", published: false } }
    assert_response :redirect
    draft_activity = @teacher.activities.order(:id).last

    assert_difference("Exercise.count") do
      post exercises_url, params: {
        exercise: { title: "Frases da turma", exercise_type: "ordering", object: multiple_sentence_object.to_json }
      }
    end
    exercise = @teacher.exercises.order(:id).last

    assert_difference("ActivityExercise.count") do
      post activity_exercises_url, params: { activity_exercise: { activity_id: draft_activity.id, exercise_id: exercise.id, points: 100 } }
    end
    assert_redirected_to activity_url(draft_activity)

    patch activity_url(draft_activity), params: { activity: { published: true } }
    assert_redirected_to activity_url(draft_activity)
    assert_predicate draft_activity.reload, :published?

    updated_object = multiple_sentence_object.merge("instructions" => "Reorganize as frases sem perder a pontuação.")
    patch exercise_url(exercise), params: { exercise: { object: updated_object.to_json } }
    assert_redirected_to exercise_url(exercise)
    assert_equal updated_object, exercise.reload.object

    post activities_url, params: { activity: { class_id: school_class.id, title: "Aula já publicada", published: true } }
    already_published = @teacher.activities.order(:id).last
    another_exercise = @teacher.exercises.create!(title: "Outra ordenação", exercise_type: :ordering, object: multiple_sentence_object)

    assert_difference("ActivityExercise.count") do
      post activity_exercises_url, params: {
        activity_exercise: { activity_id: already_published.id, exercise_id: another_exercise.id, points: 100 }
      }
    end
    assert_redirected_to activity_url(already_published)
    assert_equal another_exercise, already_published.activity_exercises.active.last.exercise
  end

  test "invalid parameters are rejected before calling the API" do
    [
      valid_params.merge(topic: " "),
      valid_params.merge(difficulty: "expert"),
      valid_params.merge(item_count: 1),
      valid_params.merge(item_count: 21),
      valid_params.merge(item_type: "sentences"),
      valid_params.merge(format: "multiple_sentences", sentence_count: 1),
      valid_params.merge(format: "multiple_sentences", sentence_count: 21),
      valid_params.merge(format: "unknown")
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

  def multiple_sentence_object
    {
      "format" => "multiple_sentences",
      "instructions" => "Organize as frases.",
      "sentences" => [
        { "id" => "sentence-one", "items" => [ { "id" => "word-one-a", "label" => "Olá," }, { "id" => "word-one-b", "label" => "mundo!" } ], "correct_order" => %w[word-one-a word-one-b] },
        { "id" => "sentence-two", "items" => [ { "id" => "word-two-a", "label" => "Olá," }, { "id" => "word-two-b", "label" => "mundo?" } ], "correct_order" => %w[word-two-a word-two-b] }
      ]
    }
  end

  def valid_params
    { topic: "Plantio", difficulty: "medium", item_count: 3, item_type: "words" }
  end
end
