require "test_helper"

class ActivityExercisesIndexScopeTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher_a = create_user(Teacher, "aei-a")
    @teacher_b = create_user(Teacher, "aei-b")
    @student = create_user(Student, "aei-s")
    @activity_a = create_activity(@teacher_a, "Aula da Professora A")
    @activity_b = create_activity(@teacher_b, "Aula do Professor B")
    @exercise_a = create_exercise(@teacher_a, "Exercício da Professora A")
    @exercise_b = create_exercise(@teacher_b, "Exercício do Professor B")
    @link_a = @activity_a.activity_exercises.create!(exercise: @exercise_a, position: 1, points: 5)
    @link_b = @activity_b.activity_exercises.create!(exercise: @exercise_b, position: 1, points: 5)
  end

  test "teacher A sees only own links" do
    login(@teacher_a)
    get activity_exercises_url

    assert_response :success
    assert_includes response.body, "Aula da Professora A"
    assert_includes response.body, "Exercício da Professora A"
    assert_not_includes response.body, "Aula do Professor B"
    assert_not_includes response.body, "Exercício do Professor B"
    assert_not_includes response.body, activity_exercise_path(@link_b)
  end

  test "teacher B sees only own links" do
    login(@teacher_b)
    get activity_exercises_url

    assert_response :success
    assert_includes response.body, "Aula do Professor B"
    assert_not_includes response.body, "Aula da Professora A"
    assert_not_includes response.body, "Exercício da Professora A"
  end

  test "teacher does not see inactive own links" do
    @link_a.update!(active: false)
    login(@teacher_a)
    get activity_exercises_url

    assert_response :success
    assert_not_includes response.body, "Exercício da Professora A"
  end

  test "student cannot list links" do
    login(@student)
    get activity_exercises_url

    assert_redirected_to root_path
    assert_not_includes response.body, "Aula da Professora A"
  end

  test "anonymous user cannot list links" do
    get activity_exercises_url

    assert_redirected_to login_path
  end

  test "association actions keep working" do
    login(@teacher_a)
    other = create_exercise(@teacher_a, "Outro exercício A")

    assert_difference -> { @activity_a.activity_exercises.active.count }, 1 do
      post activity_exercises_url, params: { activity_exercise: { activity_id: @activity_a.id, exercise_id: other.id, points: 3 } }
    end
    assert_redirected_to activity_url(@activity_a)

    get activity_exercise_url(@link_a)
    assert_response :success

    delete activity_exercise_url(@link_a)
    assert_not @link_a.reload.active?
    assert @link_b.reload.active?
  end

  private

  def create_activity(teacher, title)
    school_class = teacher.school_classes.create!(name: "Turma #{title}", active: true)
    school_class.activities.create!(title:, published: true)
  end

  def create_exercise(teacher, title)
    teacher.exercises.create!(title:, exercise_type: :quiz, object: {
      "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ]
    })
  end

  def create_user(klass, prefix)
    id = "#{prefix}-#{SecureRandom.hex(6)}"
    klass.create!(name: id, username: id, email: "#{id}@example.com", password: "secret123")
  end

  def login(user)
    role = user.is_a?(Teacher) ? "teacher" : "student"
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end
end
