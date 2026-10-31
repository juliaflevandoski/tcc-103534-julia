require "test_helper"

class DestructiveActionConfirmationsTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "dac-t")
    @student = create_user(Student, "dac-s")
    @school_class = @teacher.school_classes.create!(name: "Turma confirmação", active: true)
    @school_class.class_students.create!(student: @student, active: true)
    @activity = @school_class.activities.create!(title: "Aula confirmação", published: true)
    game = Exercises::MemoryGameBuilder.call(object: {
      instructions: "Combine os pares.",
      pair_type: "word_word",
      pairs: [
        { left: { type: "word", content: "DOG" }, right: { type: "word", content: "CACHORRO" } },
        { left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } }
      ]
    })
    @exercise = @teacher.exercises.create!(title: "Exercício confirmação", exercise_type: :memory_game, object: game.object)
    @link = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 5)
    started = Exercises::MemoryGamePlay.start(object: @exercise.object, points: 5)
    @attempt = ExerciseAttempt.create!(student: @student, activity_exercise: @link, answer: started.fetch("answer"), correct: started.fetch("correct"))
  end

  test "teacher forms ask for confirmation" do
    login(@teacher, "teacher")

    assert_confirmation school_classes_url, school_class_path(@school_class), "Desativar esta turma"
    assert_confirmation activities_url, activity_path(@activity), "Desativar esta aula"
    assert_confirmation exercises_url, exercise_path(@exercise), "Desativar este exercício"
    assert_confirmation activity_url(@activity), activity_exercise_path(@link), "Remover este exercício da aula"
    assert_confirmation exercise_attempts_url, exercise_attempt_path(@attempt), "Desativar esta tentativa"
  end

  test "student leave form asks for confirmation" do
    login(@student, "student")

    assert_confirmation school_classes_url, leave_school_class_path(@school_class), "Sair desta turma"
  end

  test "student does not get teacher destructive forms" do
    login(@student, "student")
    get school_classes_url

    assert_select "form[action='#{school_class_path(@school_class)}'] input[name='_method'][value='delete']", count: 0
  end

  test "confirmed actions keep working with the same methods" do
    login(@teacher, "teacher")

    delete exercise_attempt_path(@attempt)
    assert_not @attempt.reload.active?
    delete activity_exercise_path(@link)
    assert_not @link.reload.active?
    delete exercise_path(@exercise)
    assert_not @exercise.reload.active?
    delete activity_path(@activity)
    assert_not @activity.reload.active?
    delete school_class_path(@school_class)
    assert_not @school_class.reload.active?
  end

  test "student leave still works" do
    login(@student, "student")

    delete leave_school_class_path(@school_class)
    assert_not @school_class.class_students.find_by(student: @student).active?
  end

  test "other teacher is still not authorized" do
    other = create_user(Teacher, "dac-o")
    login(other, "teacher")

    delete school_class_path(@school_class)
    assert @school_class.reload.active?
    delete exercise_attempt_path(@attempt)
    assert @attempt.reload.active?
  end

  private

  def assert_confirmation(page_url, action, message_start)
    get page_url
    assert_response :success
    assert_select "form[action='#{action}'][data-turbo-confirm^='#{message_start}']", minimum: 1
  end

  def create_user(klass, prefix)
    id = "#{prefix}-#{SecureRandom.hex(6)}"
    klass.create!(name: id, username: id, email: "#{id}@example.com", password: "secret123")
  end

  def login(user, role)
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end
end
