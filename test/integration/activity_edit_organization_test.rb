require "test_helper"

class ActivityEditOrganizationTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "edit-teacher")
    @school_class = @teacher.school_classes.create!(name: "Turma edição", active: true)
    @activity = @school_class.activities.create!(title: "Aula original", published: true)
    @exercise = @teacher.exercises.create!(title: "Exercício da aula", exercise_type: :quiz, object: {
      "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ]
    })
    @spare = @teacher.exercises.create!(title: "Exercício avulso", exercise_type: :quiz, object: {
      "questions" => [ { "question_type" => "short_answer", "statement" => "Outra?", "correct_answer" => "Sim" } ]
    })
    @link = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 3)
    @student = create_user(Student, "edit-student")
    @school_class.class_students.create!(student: @student, active: true)
  end

  test "edit page has only the activity form and no exercise management" do
    login(@teacher)

    get edit_activity_url(@activity)

    assert_response :success
    assert_select "form[action='#{activity_path(@activity)}']", count: 1
    assert_select "form[action='#{activity_exercises_path}']", count: 0
    assert_select "table.exercise-table", count: 0
    assert_select "tr[draggable='true']", count: 0
    assert_select "a", text: "Criar exercício", count: 0
    assert_select "a", text: @exercise.title, count: 0
  end

  test "teacher updates the activity and invalid update re-renders edit without management" do
    login(@teacher)

    patch activity_url(@activity), params: { activity: { title: "Aula nova", published: "0" } }
    assert_redirected_to activity_url(@activity)
    assert_equal "Aula nova", @activity.reload.title
    assert_not @activity.published?

    patch activity_url(@activity), params: { activity: { title: "" } }
    assert_response :unprocessable_entity
    assert_select "form[action='#{activity_exercises_path}']", count: 0
    assert_equal "Aula nova", @activity.reload.title
  end

  test "activity page keeps all teacher management controls" do
    login(@teacher)

    get activity_url(@activity, exercise_id: @spare.id)

    assert_response :success
    assert_select "form[action='#{activity_exercises_path}']", count: 1
    assert_select "select[name='activity_exercise[exercise_id]'] option[selected][value='#{@spare.id}']", count: 1
    assert_select "a[href='#{new_exercise_path(activity_id: @activity.id)}']", text: "Criar exercício"
    assert_select "table.exercise-table[data-controller='sortable-exercises']", count: 1
    assert_select "tr[data-id='#{@link.id}'][draggable='true']", count: 1
    assert_select "tr[data-id='#{@link.id}'] form[action='#{activity_exercise_path(@link)}'] input[name='_method'][value='delete']"
    assert_no_difference("ActivityExercise.count") { get activity_url(@activity, exercise_id: @spare.id) }
  end

  test "student sees exercises without administrative controls" do
    login(@student)

    get activity_url(@activity)

    assert_response :success
    assert_select "a[href='#{exercise_path(@exercise, activity_exercise_id: @link.id)}']", text: @exercise.title
    assert_select "form[action='#{activity_exercises_path}']", count: 0
    assert_select "tr[draggable='true']", count: 0
    assert_select "a", text: "Criar exercício", count: 0
    assert_select "a", text: "Editar", count: 0
  end

  test "back to class link works for teacher and student" do
    [ @teacher, @student ].each do |user|
      login(user)
      get activity_url(@activity)
      assert_select "a[href='#{school_class_path(@school_class)}']", text: "Voltar à turma", count: 1
      get school_class_url(@school_class)
      assert_response :success
      delete logout_url
    end
  end

  test "access rules still block improper access" do
    outsider = create_user(Student, "edit-outsider")
    other_teacher = create_user(Teacher, "edit-other")

    login(outsider)
    get activity_url(@activity)
    assert_redirected_to root_url
    delete logout_url

    login(@student)
    get edit_activity_url(@activity)
    assert_redirected_to root_url
    patch activity_url(@activity), params: { activity: { title: "Hack" } }
    assert_redirected_to root_url
    delete logout_url

    login(other_teacher)
    get edit_activity_url(@activity)
    assert_redirected_to root_url
    assert_equal "Aula original", @activity.reload.title
  end

  test "FL-2 and FL-3 flows keep working" do
    login(@teacher)
    get new_exercise_url(activity_id: @activity.id)
    assert_select "input[type='hidden'][name='activity_id'][value='#{@activity.id}']", count: 1
    assert_difference("ActivityExercise.count", 1) do
      post activity_exercises_url, params: { activity_exercise: { activity_id: @activity.id, exercise_id: @spare.id, points: 2 } }
    end
    assert_redirected_to activity_url(@activity)
    delete logout_url

    login(@student)
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: @link.id, answers: { "0" => "Resposta" } } }
    follow_redirect!
    assert_select "a[href='#{activity_path(@activity)}']", text: "Voltar à aula", minimum: 1
    assert_select "a", text: "Próximo exercício", count: 1
  end

  private

  def create_user(klass, prefix)
    id = "#{prefix}-#{SecureRandom.hex(6)}"
    klass.create!(name: prefix, username: id, email: "#{id}@example.com", password: "secret123")
  end

  def login(user)
    role = user.is_a?(Teacher) ? "teacher" : "student"
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end
end
