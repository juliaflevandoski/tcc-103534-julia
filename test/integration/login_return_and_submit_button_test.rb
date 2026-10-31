require "test_helper"

class LoginReturnAndSubmitButtonTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "ret-teacher")
    @school_class = @teacher.school_classes.create!(name: "Turma retorno", active: true)
    @activity = @school_class.activities.create!(title: "Aula retorno", published: true)
    @student = create_user(Student, "ret-student")
    @school_class.class_students.create!(student: @student, active: true)
  end

  test "submit buttons of the four common players show a sending label" do
    login_as(@student, "student")
    {
      quiz: [ { "questions" => [ { "question_type" => "short_answer", "statement" => "P?", "correct_answer" => "R" } ] }, "Enviar respostas" ],
      fill_blanks: [ { "text_template" => "O {{1}}.", "blanks" => { "1" => "céu" } }, "Enviar respostas" ],
      ordering: [ { "instructions" => "Organize.", "item_type" => "words", "items" => [ { "id" => "a", "label" => "A" }, { "id" => "b", "label" => "B" } ], "correct_order" => %w[a b] }, "Enviar ordem" ],
      crossword: [ Exercises::CrosswordBuilder.call(instructions: "Complete", seed: 17, words: [ { word: "APPLE", clue: "Fruta" }, { word: "PEAR", clue: "Outra" } ]).object, "Conferir cruzadinha" ]
    }.each do |type, (object, label)|
      exercise = @teacher.exercises.create!(title: "Ex #{type}", exercise_type: type, object:)
      link = @activity.activity_exercises.create!(exercise:, position: @activity.activity_exercises.count + 1, points: 4)

      get exercise_path(exercise, activity_exercise_id: link.id)

      assert_select "input[type='submit'][value='#{label}'][data-turbo-submits-with='Enviando...']", count: 1
    end
  end

  test "multiple sentences ordering keeps its own submit protection untouched" do
    exercise = @teacher.exercises.create!(title: "Frases", exercise_type: :ordering, object: {
      "format" => "multiple_sentences", "instructions" => "Organize.",
      "sentences" => [
        { "id" => "s1", "items" => [ { "id" => "a", "label" => "I" }, { "id" => "b", "label" => "can" } ], "correct_order" => %w[a b] },
        { "id" => "s2", "items" => [ { "id" => "c", "label" => "We" }, { "id" => "d", "label" => "go" } ], "correct_order" => %w[c d] }
      ]
    })
    link = @activity.activity_exercises.create!(exercise:, position: 1, points: 4)
    login_as(@student, "student")

    get exercise_path(exercise, activity_exercise_id: link.id)

    assert_select "button[type='submit'][data-turbo-submits-with]", count: 0
  end

  test "rejected incomplete submission renders a fresh enabled button" do
    exercise = @teacher.exercises.create!(title: "Quiz", exercise_type: :quiz, object: { "questions" => [ { "question_type" => "short_answer", "statement" => "P?", "correct_answer" => "R" } ] })
    link = @activity.activity_exercises.create!(exercise:, position: 1, points: 4)
    login_as(@student, "student")

    assert_no_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answers: { "0" => "" } } }
    end

    assert_response :unprocessable_entity
    assert_select "input[type='submit'][value='Enviar respostas']:not([disabled])", count: 1
  end

  test "login returns to the originally requested GET page" do
    get exercises_url
    assert_redirected_to login_url

    login_as(@teacher, "teacher")

    assert_redirected_to exercises_url
  end

  test "return location keeps the query string" do
    get activity_url(@activity, exercise_id: 7)

    login_as(@teacher, "teacher")

    assert_redirected_to activity_url(@activity, exercise_id: 7)
  end

  test "login without a saved location goes to root" do
    login_as(@student, "student")

    assert_redirected_to root_url
  end

  test "visiting the login page does not store a return location and no loop is created" do
    get login_url(role: "student")
    get login_url

    login_as(@student, "student")

    assert_redirected_to root_url
  end

  test "failed login keeps the saved location for the next attempt" do
    get exercises_url
    post login_url, params: { role: "teacher", username: @teacher.username, password: "wrong" }
    assert_redirected_to login_url(role: "teacher")

    login_as(@teacher, "teacher")

    assert_redirected_to exercises_url
  end

  test "non GET, JSON and AJAX requests are never stored" do
    post exercises_url, params: { exercise: { title: "x" } }
    get exercises_url(format: :json)
    get exercises_url, xhr: true

    login_as(@teacher, "teacher")

    assert_redirected_to root_url
  end

  test "the saved location is consumed after login and cleared on logout" do
    get exercises_url
    login_as(@teacher, "teacher")
    assert_redirected_to exercises_url

    delete logout_url
    login_as(@teacher, "teacher")
    assert_redirected_to root_url
  end

  test "unsafe return paths are rejected" do
    controller = SessionsController.new
    [ "//evil.com", "http://evil.com", "https://evil.com/x", "evil.com", "/\\evil.com", "/login", "/login?role=student", "/logout", "/a\nb", nil, 123 ].each do |path|
      assert_not controller.send(:safe_return_path?, path), "#{path.inspect} should be unsafe"
    end
    [ "/", "/exercises", "/activities/1?x=//y", "/loginx" ].each do |path|
      assert controller.send(:safe_return_path?, path), "#{path.inspect} should be safe"
    end
  end

  test "returning after login still respects policies for the other profile" do
    get new_exercise_url
    assert_redirected_to login_url

    login_as(@student, "student")
    assert_redirected_to new_exercise_url
    follow_redirect!

    assert_redirected_to root_url
    follow_redirect!
    assert_includes response.body, "Você não tem permissão para acessar este recurso."
  end

  test "student reaching a teacher-only resource after login does not gain access and teacher can open it" do
    get new_exercise_url
    login_as(@teacher, "teacher")
    follow_redirect!

    assert_response :success
  end

  private

  def login_as(user, role)
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end

  def create_user(klass, prefix)
    id = "#{prefix}-#{SecureRandom.hex(6)}"
    klass.create!(name: prefix, username: id, email: "#{id}@example.com", password: "secret123")
  end
end
