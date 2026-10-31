require "test_helper"

class ActivityVisibleExercisesTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "vis-teacher")
    @school_class = @teacher.school_classes.create!(name: "Turma visível", active: true)
    @activity = @school_class.activities.create!(title: "Aula visível", published: true)
    @first = link("Primeiro", 1)
    @inactive_exercise_link = link("Exercício inativo", 2, exercise_active: false)
    @inactive_link = link("Vínculo inativo", 3, link_active: false)
    @last = link("Último", 4)
    @student = create_user(Student, "vis-student")
    @school_class.class_students.create!(student: @student, active: true)
  end

  test "teacher and student see only active links with active exercises" do
    [ @teacher, @student ].each do |user|
      login(user)
      get activity_url(@activity)

      assert_response :success
      assert_select "a", text: "Primeiro", count: 1
      assert_select "a", text: "Último", count: 1
      assert_select "a", text: "Exercício inativo", count: 0
      assert_select "a", text: "Vínculo inativo", count: 0
      assert_select "table.exercise-table tbody tr", count: 2
      delete logout_url
    end
  end

  test "class count matches the exercises shown in the activity" do
    login(@teacher)
    get activity_url(@activity)
    shown = css_select("table.exercise-table tbody tr").size

    get school_class_url(@school_class)

    assert_equal 2, shown
    assert_select "p", text: "#{shown} exercícios", count: 1
  end

  test "active exercises remain accessible and teacher controls remain for visible rows" do
    login(@teacher)
    get activity_url(@activity)

    assert_select "a[href='#{exercise_path(@first.exercise, activity_exercise_id: @first.id, activity_id: @activity.id)}']", text: "Primeiro"
    assert_select "tr[data-id='#{@first.id}'][draggable='true'] form[action='#{activity_exercise_path(@first)}']"
    assert_select "tr[data-id='#{@inactive_exercise_link.id}']", count: 0
    get exercise_url(@first.exercise, activity_exercise_id: @first.id)
    assert_response :success

    delete activity_exercise_url(@last)
    assert_redirected_to activity_url(@activity)
    assert_not @last.reload.active?
  end

  test "next exercise navigation keeps the teacher order and skips hidden links" do
    @first.update!(position: 1)
    @last.update!(position: 5)
    middle = link("Meio", 4)
    login(@student)

    assert_equal middle, ActivityExercises::NextExercise.call(activity_exercise: @first)
    assert_equal @last, ActivityExercises::NextExercise.call(activity_exercise: middle)
    assert_nil ActivityExercises::NextExercise.call(activity_exercise: @last)
  end

  private

  def link(title, position, exercise_active: true, link_active: true)
    exercise = @teacher.exercises.create!(title:, exercise_type: :quiz, active: exercise_active, object: {
      "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ]
    })
    @activity.activity_exercises.create!(exercise:, position:, points: 1, active: link_active)
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
