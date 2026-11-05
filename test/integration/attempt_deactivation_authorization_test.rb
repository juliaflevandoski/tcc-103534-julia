require "test_helper"

class AttemptDeactivationAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    suffix = SecureRandom.hex(6)
    @teacher = Teacher.create!(name: "Prof", username: "deact_t_#{suffix}", email: "deact_t_#{suffix}@example.test", password: "secret123")
    @school_class = @teacher.school_classes.create!(name: "Turma desativação", active: true)
    @activity = @school_class.activities.create!(title: "Aula desativação", published: true)
    @student = create_student("deact_s1")
    @other_student = create_student("deact_s2")
    [ @student, @other_student ].each { |student| @school_class.class_students.create!(student:, active: true) }
    exercise = @teacher.exercises.create!(title: "Quiz desativação", exercise_type: :quiz, object: {
      "questions" => [
        {
          "question_type" => "multiple_choice",
          "statement" => "Escolha A.",
          "options" => [ { "id" => "a", "text" => "A" }, { "id" => "b", "text" => "B" } ],
          "correct_option_ids" => [ "a" ]
        }
      ]
    })
    @link = @activity.activity_exercises.create!(exercise:, position: 1, points: 10)
    @official = Exercises::QuizSubmission.call(activity_exercise: @link, student: @student, answers: { "0" => "b" }).attempt
    @later = Exercises::QuizSubmission.call(activity_exercise: @link, student: @student, answers: { "0" => "a" }).attempt
    @other_attempt = Exercises::QuizSubmission.call(activity_exercise: @link, student: @other_student, answers: { "0" => "a" }).attempt
  end

  test "teacher sees the history and details but no deactivate button" do
    login(@teacher, "teacher")

    get exercise_attempts_url(school_class_id: @school_class.id)

    assert_response :success
    assert_select "details.attempt-history", minimum: 1
    assert_select "a[href='#{exercise_attempt_path(@official)}']", text: "Detalhes"
    assert_select "button", text: "Desativar", count: 0
    assert_select "form[action='#{exercise_attempt_path(@official)}']", count: 0
  end

  test "student sees own history with details links and no deactivate button" do
    login(@student, "student")

    get exercise_attempts_url(school_class_id: @school_class.id)

    assert_response :success
    assert_select "section.results-class--student details.attempt-history li.attempt-history-item", count: 2
    assert_select "a[href='#{exercise_attempt_path(@official)}']", text: "Detalhes"
    assert_select "a[href='#{exercise_attempt_path(@later)}']", text: "Detalhes"
    assert_select "a[href='#{exercise_attempt_path(@other_attempt)}']", count: 0
    assert_select ".attempt-history-tag--official", text: "Nota oficial", count: 1
    assert_select "button", text: "Desativar", count: 0
    assert_select ".student-exercise-metric--score dd", text: "0 / 10"
  end

  test "teacher who owns the activity cannot deactivate a student attempt directly" do
    login(@teacher, "teacher")

    assert_no_difference("ExerciseAttempt.count") { delete exercise_attempt_path(@official) }

    assert_redirected_to root_url
    assert @official.reload.active?
  end

  test "student can still deactivate their own attempt without deleting it" do
    login(@student, "student")

    assert_no_difference("ExerciseAttempt.count") { delete exercise_attempt_path(@later) }

    assert_redirected_to exercise_attempts_url
    assert_not @later.reload.active?
  end

  test "student cannot deactivate another student's attempt" do
    login(@student, "student")

    delete exercise_attempt_path(@other_attempt)

    assert_redirected_to root_url
    assert @other_attempt.reload.active?
  end

  test "deactivating an attempt keeps history and does not promote another official attempt" do
    login(@student, "student")
    delete exercise_attempt_path(@official)
    assert_not @official.reload.active?

    assert_equal @official, ActivityResults.official_attempt(activity_exercise: @link, student: @student)
    assert_equal 0, @official.score

    login(@teacher, "teacher")
    get exercise_attempts_url(school_class_id: @school_class.id)

    assert_response :success
    assert_select "details.attempt-history", minimum: 1
    assert_select ".attempt-history-tag--inactive", text: "Desativada", count: 1
    assert_select ".attempt-history-tag--official", text: "Nota oficial", minimum: 1
    assert_select ".attempt-history li", minimum: 3
  end

  private

  def create_student(prefix)
    id = "#{prefix}_#{SecureRandom.hex(6)}"
    Student.create!(name: id, username: id, email: "#{id}@example.test", password: "secret123")
  end

  def login(user, role)
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end
end
