require "test_helper"

# Documenta os contratos HTTP dos endpoints AJAX; o JavaScript depende deles para detectar falhas.
class AjaxHttpContractsTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  JSON_HEADERS = { "Accept" => "application/json" }.freeze

  setup do
    @teacher = create_user(Teacher, "aj-teacher")
    @student = create_user(Student, "aj-student")
    @school_class = @teacher.school_classes.create!(name: "Turma AJAX", active: true)
    @school_class.class_students.create!(student: @student, active: true)
    @activity = @school_class.activities.create!(title: "Aula AJAX", published: true)
    @first = link("Primeiro", quiz_object, 1)
    @second = link("Segundo", quiz_object, 2)
  end

  def create_user(klass, prefix)
    id = "#{prefix}-#{SecureRandom.hex(6)}"
    klass.create!(name: id, username: id, email: "#{id}@example.com", password: "secret123")
  end

  def login(user)
    post login_url, params: { role: user.is_a?(Teacher) ? "teacher" : "student", username: user.username, password: "secret123" }
  end

  def quiz_object
    { "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ] }
  end

  def link(title, object, position)
    exercise = @teacher.exercises.create!(title:, exercise_type: :quiz, object:)
    @activity.activity_exercises.create!(exercise:, position:, points: 10)
  end

  def positions
    @activity.activity_exercises.active.order(:position).pluck(:id)
  end

  def reorder(ids)
    patch reorder_activity_exercises_url(@activity), params: { ordered_ids: ids }, headers: JSON_HEADERS, as: :json
  end

  # Reordenação

  test "reorder without a session redirects to login and changes nothing" do
    reorder([ @second.id, @first.id ])
    assert_redirected_to login_url
    assert_equal [ @first.id, @second.id ], positions
  end

  test "reorder by a student redirects and changes nothing" do
    login(@student)
    reorder([ @second.id, @first.id ])
    assert_redirected_to root_url
    assert_equal [ @first.id, @second.id ], positions
  end

  test "reorder by the owner returns the JSON contract used by the sortable controller" do
    login(@teacher)
    reorder([ @second.id, @first.id ])
    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_equal({ "data" => { "positions" => "updated" }, "errors" => [] }, response.parsed_body)
    assert_equal [ @second.id, @first.id ], positions
  end

  test "reorder with invalid ids returns a JSON 422 error without data" do
    login(@teacher)
    reorder([ @first.id, 0 ])
    assert_response :unprocessable_entity
    assert_nil response.parsed_body["data"]
    assert_equal [ "Ordem inválida" ], response.parsed_body["errors"].map { |error| error["message"] }
    assert_equal [ @first.id, @second.id ], positions
  end

  # Jogo da Memória

  def memory_attempt
    exercise = @teacher.exercises.create!(title: "Memoria", exercise_type: :memory_game, object: Exercises::MemoryGameBuilder.call(object: {
      instructions: "Combine.", pair_type: "word_word",
      pairs: [
        { left: { type: "word", content: "DOG" }, right: { type: "word", content: "CACHORRO" } },
        { left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } }
      ]
    }).object)
    memory_link = @activity.activity_exercises.create!(exercise:, position: 3, points: 10)
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: memory_link.id } }
    ExerciseAttempt.order(:id).last
  end

  def turn(attempt, operation: "reset", **extra)
    post memory_game_turn_exercise_attempt_url(attempt), params: { operation:, **extra }, headers: JSON_HEADERS, as: :json
  end

  test "memory turn without a session redirects to login" do
    login(@student)
    attempt = memory_attempt
    delete logout_url
    turn(attempt)
    assert_redirected_to login_url
  end

  test "memory turn by another student redirects and keeps the attempt unchanged" do
    login(@student)
    attempt = memory_attempt
    before = attempt.reload.attributes
    delete logout_url
    login(create_user(Student, "aj-other"))
    turn(attempt)
    assert_redirected_to root_url
    assert_equal before, attempt.reload.attributes
  end

  test "memory turn for a missing attempt is a 404 without JSON" do
    login(@student)
    turn(ExerciseAttempt.new(id: 999_999))
    assert_response :not_found
  end

  test "memory turn keeps the JSON contract for success and for rejected moves" do
    login(@student)
    attempt = memory_attempt
    card = attempt.correct.fetch("deck").first
    turn(attempt, operation: "reveal", card_id: card.fetch("id"))
    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_equal [], response.parsed_body["errors"]
    assert response.parsed_body["data"].key?("card")

    turn(attempt, operation: "invalid")
    assert_response :unprocessable_entity
    assert_nil response.parsed_body["data"]
    assert_equal [ "Ação inválida." ], response.parsed_body["errors"].map { |error| error["message"] }
  end
end
