require "test_helper"

class QuizAiGenerationTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  class FakeGenerator
    attr_reader :calls
    attr_accessor :result, :exception

    def initialize(result)
      @result = result
      @calls = []
    end

    def call(**arguments)
      @calls << arguments
      raise exception if exception

      result
    end
  end

  GenerationResult = Struct.new(:quiz, :error_code, :message, keyword_init: true) do
    def success?
      error_code.nil?
    end
  end

  setup do
    @quiz = {
      "questions" => [
        {
          "question_type" => "multiple_choice",
          "statement" => "Qual é o resultado de 2 + 2?",
          "options" => [ { "id" => "four", "text" => "4" }, { "id" => "five", "text" => "5" } ],
          "correct_option_ids" => [ "four" ]
        },
        {
          "question_type" => "multiple_choice",
          "statement" => "Qual número vem depois de 4?",
          "options" => [ { "id" => "five-next", "text" => "5" }, { "id" => "six-next", "text" => "6" } ],
          "correct_option_ids" => [ "five-next" ]
        },
        { "question_type" => "true_false", "statement" => "2 + 2 é igual a 5?", "correct_option_ids" => [ "false" ] },
        { "question_type" => "short_answer", "statement" => "Escreva quatro.", "correct_answer" => "Quatro" }
      ]
    }
    @generator = FakeGenerator.new(GenerationResult.new(quiz: @quiz))
    @original_generator = ExercisesController.quiz_generator_service
    ExercisesController.quiz_generator_service = @generator
    @teacher = Teacher.create!(
      name: "Professor Quiz IA",
      username: "quizai-#{SecureRandom.hex(6)}",
      email: "quizai-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
  end

  teardown do
    ExercisesController.quiz_generator_service = @original_generator
  end

  test "teacher receives a validated draft without saving and can submit edited content normally" do
    assert_no_difference("Exercise.count") do
      post generate_quiz_exercises_url, params: valid_generation_params, as: :json
    end

    assert_response :success
    generated_quiz = response.parsed_body.dig("data", "quiz")
    assert_equal @quiz, generated_quiz
    assert_equal 1, @generator.calls.length
    assert_equal "Biologia", @generator.calls.first.fetch(:topic)
    assert_equal [ "multiple_choice", "true_false", "short_answer" ], @generator.calls.first.fetch(:question_types)

    generated_quiz["questions"][0]["statement"] = "Enunciado revisado pelo professor."
    generated_quiz["questions"].delete_at(1)
    assert_difference("Exercise.count") do
      post exercises_url, params: {
        exercise: { title: "Quiz revisado", exercise_type: "quiz", object: generated_quiz.to_json }
      }
    end

    exercise = @teacher.exercises.order(:id).last
    assert_redirected_to exercise_url(exercise)
    assert_equal [ "multiple_choice", "true_false", "short_answer" ], exercise.object.fetch("questions").pluck("question_type")
    assert_equal "Enunciado revisado pelo professor.", exercise.object.fetch("questions").first.fetch("statement")
    assert_equal [ "four" ], exercise.object.fetch("questions").first.fetch("correct_option_ids")

    school_class = @teacher.school_classes.create!(name: "Quiz IA", active: true)
    activity = school_class.activities.create!(title: "Quiz gerado", published: true)
    student = Student.create!(
      name: "Aluno do Quiz IA",
      username: "quizai-solver-#{SecureRandom.hex(6)}",
      email: "quizai-solver-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    school_class.class_students.create!(student:, active: true)
    activity_exercise = activity.activity_exercises.create!(exercise:, position: 1, points: 10)
    delete logout_url
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
    get exercise_url(exercise, activity_exercise_id: activity_exercise.id)

    assert_response :success
    assert_select "legend", text: "Enunciado revisado pelo professor."
    assert_select "input[type='text'][name='exercise_attempt[answers][2]']"
    post exercise_attempts_url, params: {
      exercise_attempt: {
        activity_exercise_id: activity_exercise.id,
        answers: { "0" => "four", "1" => "true", "2" => "  QUATRO  " }
      }
    }

    attempt = ExerciseAttempt.order(:id).last
    assert_redirected_to exercise_attempt_url(attempt)
    assert_equal 6, attempt.score
    assert_equal [ true, false, true ], attempt.correct.fetch("questions").pluck("correct")
    assert_equal [ "4", "Falso", "Quatro" ], attempt.correct.fetch("questions").pluck("correct_answer")
  end

  test "new exercise form presents generation controls beside the existing quiz editor" do
    get new_exercise_url

    assert_response :success
    assert_select "button.quiz-ai-open[data-action='exercise-form#openQuizAiModal']" do
      assert_select "i.fa-solid.fa-wand-magic-sparkles[aria-hidden='true']"
    end
    assert_select "dialog.quiz-ai-modal[data-exercise-form-target='quizAiModal']:not([open])"
    assert_select "input[data-exercise-form-target='quizAiTopic'][required]", count: 0
    assert_select "select[data-exercise-form-target='quizAiDifficulty'][required]", count: 0
    assert_select "select[data-exercise-form-target='quizAiDifficulty'] option[value='easy']", text: "Fácil"
    assert_select "select[data-exercise-form-target='quizAiDifficulty'] option[value='medium']", text: "Médio"
    assert_select "select[data-exercise-form-target='quizAiDifficulty'] option[value='hard']", text: "Difícil"
    assert_select "input[data-exercise-form-target='quizAiQuestionCount'][min='1'][max='20'][required]", count: 0
    assert_select "input[data-exercise-form-target='quizAiQuestionType'][value='multiple_choice']"
    assert_select "input[data-exercise-form-target='quizAiQuestionType'][value='true_false']"
    assert_select "input[data-exercise-form-target='quizAiQuestionType'][value='short_answer']"
    assert_select "button[data-action='exercise-form#generateQuiz']"
    assert_select "button[data-action='exercise-form#applyGeneratedQuiz'][hidden]"
    assert_select "button[data-action='exercise-form#addQuestion']", text: "Adicionar pergunta"
  end

  test "editing a quiz can be saved without entering AI generation fields" do
    exercise = @teacher.exercises.create!(title: "Quiz existente", exercise_type: :quiz, object: @quiz)
    get edit_exercise_url(exercise)

    assert_response :success
    assert_select "input[data-exercise-form-target='quizAiTopic'][required]", count: 0
    assert_select "select[data-exercise-form-target='quizAiDifficulty'][required]", count: 0
    assert_select "input[data-exercise-form-target='quizAiQuestionCount'][required]", count: 0

    patch exercise_url(exercise), params: {
      exercise: { object: exercise.object.to_json }
    }

    assert_redirected_to exercise_url(exercise)
    assert_equal @quiz, exercise.reload.object
  end

  test "backend rejects invalid generation inputs before invoking the generator" do
    ExercisesController.quiz_generator_service = Exercises::QuizGenerator
    invalid_params = [
      valid_generation_params.merge(topic: " "),
      valid_generation_params.merge(difficulty: "expert"),
      valid_generation_params.merge(question_count: 0),
      valid_generation_params.merge(question_count: 21),
      valid_generation_params.merge(question_types: [ "essay" ]),
      valid_generation_params.merge(question_types: [])
    ]

    invalid_params.each do |generation_params|
      assert_no_difference("Exercise.count") do
        post generate_quiz_exercises_url, params: generation_params, as: :json
      end

      assert_response :unprocessable_entity
      assert_equal "generation", response.parsed_body.dig("errors", 0, "field")
    end

    assert_empty @generator.calls
  end

  test "unauthenticated requests receive JSON 401 and are not passed to generation" do
    delete logout_url

    post generate_quiz_exercises_url, params: valid_generation_params, as: :json

    assert_response :unauthorized
    assert_equal "Faça login como professor para gerar quizzes.", response.parsed_body.dig("errors", 0, "message")
    assert_empty @generator.calls
  end

  test "students receive JSON 403 and are not passed to generation" do
    student = Student.create!(
      name: "Aluno Quiz IA",
      username: "quizai-student-#{SecureRandom.hex(6)}",
      email: "quizai-student-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    delete logout_url
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    post generate_quiz_exercises_url, params: valid_generation_params, as: :json

    assert_response :forbidden
    assert_equal "Somente professores podem gerar quizzes.", response.parsed_body.dig("errors", 0, "message")
    assert_empty @generator.calls
  end

  test "provider failures map to controlled statuses without exposing sensitive details" do
    @generator.result = GenerationResult.new(error_code: :timeout, message: "A comunicação excedeu o tempo limite.")
    post generate_quiz_exercises_url, params: valid_generation_params, as: :json

    assert_response :gateway_timeout
    assert_equal "A comunicação excedeu o tempo limite.", response.parsed_body.dig("errors", 0, "message")
    assert_nil response.parsed_body["data"]

    @generator.result = GenerationResult.new(error_code: :rate_limited, message: "O limite de requisições da API OpenAI foi atingido.")
    post generate_quiz_exercises_url, params: valid_generation_params, as: :json

    assert_response :too_many_requests

    @generator.result = GenerationResult.new(error_code: :service_unavailable, message: "A API OpenAI está temporariamente indisponível.")
    post generate_quiz_exercises_url, params: valid_generation_params, as: :json

    assert_response :service_unavailable

    @generator.exception = RuntimeError.new("Bearer test-secret-key")
    post generate_quiz_exercises_url, params: valid_generation_params, as: :json

    assert_response :internal_server_error
    assert_not_includes response.body, "test-secret-key"
    assert_includes response.body, "Não foi possível gerar o quiz agora. Tente novamente."
  end

  private

  def valid_generation_params
    {
      topic: "Biologia",
      difficulty: "medium",
      question_count: 4,
      question_types: %w[multiple_choice true_false short_answer]
    }
  end
end
