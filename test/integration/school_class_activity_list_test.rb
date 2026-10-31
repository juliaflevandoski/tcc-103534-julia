require "test_helper"

class SchoolClassActivityListTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "list-teacher")
    @school_class = @teacher.school_classes.create!(name: "Turma lista", active: true)
    @published = @school_class.activities.create!(title: "Aula publicada", published: true)
    @draft = @school_class.activities.create!(title: "Aula rascunho", published: false)
    @inactive = @school_class.activities.create!(title: "Aula inativa", published: true, active: false)
    @exercise = @teacher.exercises.create!(title: "Exercício da lista", exercise_type: :quiz, object: {
      "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ]
    })
    @link = @published.activity_exercises.create!(exercise: @exercise, position: 1, points: 3)
    @student = create_user(Student, "list-student")
    @school_class.class_students.create!(student: @student, active: true)
  end

  test "teacher sees published and draft activities as links with status and no exercise management" do
    login(@teacher)

    get school_class_url(@school_class)

    assert_response :success
    assert_select "h3 a[href='#{activity_path(@published)}']", text: "Aula publicada"
    assert_select "h3 a[href='#{activity_path(@draft)}']", text: "Aula rascunho"
    assert_select "h3 a", text: "Aula inativa", count: 0
    assert_select "p", text: "Publicada", count: 1
    assert_select "p", text: "Rascunho", count: 1
    assert_select "strong", text: @school_class.access_code
    assert_select "a[href='#{edit_school_class_path(@school_class)}']", text: "Editar"
    assert_no_exercise_management
  end

  test "teacher still sees enrolled students" do
    login(@teacher)

    get school_class_url(@school_class)

    assert_select "h2", text: "Alunos matriculados"
    assert_select "li", text: /#{Regexp.escape(@student.name)}/
  end

  test "student sees only published activities as links without status or exercises" do
    login(@student)

    get school_class_url(@school_class)

    assert_response :success
    assert_select "h3 a[href='#{activity_path(@published)}']", text: "Aula publicada"
    assert_select "h3 a", text: "Aula rascunho", count: 0
    assert_select "h3 a", text: "Aula inativa", count: 0
    assert_select "p", text: "Rascunho", count: 0
    assert_select "strong", text: @school_class.access_code, count: 0
    assert_select "h2", text: "Alunos matriculados", count: 0
    assert_no_exercise_management
  end

  test "student without active enrollment cannot open the class" do
    outsider = create_user(Student, "list-outsider")
    login(outsider)

    get school_class_url(@school_class)

    assert_redirected_to root_url

    @school_class.class_students.find_by!(student: @student).update!(active: false)
    delete logout_url
    login(@student)
    get school_class_url(@school_class)
    assert_redirected_to root_url
  end

  test "inactive class is not accessible" do
    @school_class.update!(active: false)
    login(@teacher)

    get school_class_url(@school_class)

    assert_response :not_found
  end

  test "another teacher cannot open the class" do
    login(create_user(Teacher, "list-other-teacher"))

    get school_class_url(@school_class)

    assert_redirected_to root_url
  end

  test "activity page still shows exercises and teacher actions" do
    login(@teacher)

    get activity_url(@published)

    assert_response :success
    assert_select "form[action='#{activity_exercises_path}']", count: 1
    assert_select "a[href='#{new_exercise_path(activity_id: @published.id)}']", text: "Criar exercício"
    assert_select "table.exercise-table[data-controller='sortable-exercises']", count: 1
    assert_select "tr[draggable='true']", count: 1
    assert_select "a[href='#{exercise_path(@exercise, activity_exercise_id: @link.id, activity_id: @published.id)}']", text: @exercise.title

    delete logout_url
    login(@student)
    get activity_url(@published)

    assert_response :success
    assert_select "table.exercise-table", count: 1
    assert_select "a[href='#{exercise_path(@exercise, activity_exercise_id: @link.id)}']", text: @exercise.title
    assert_select "form[action='#{activity_exercises_path}']", count: 0
    assert_select "tr[draggable='true']", count: 0
  end

  test "following a listed activity link opens the activity for each profile" do
    login(@teacher)
    get school_class_url(@school_class)
    get css_select("h3 a").first["href"]
    assert_response :success

    delete logout_url
    login(@student)
    get school_class_url(@school_class)
    get css_select("h3 a").first["href"]
    assert_response :success
  end

  test "FL-2 and FL-3 flows still work from the activity" do
    second = @teacher.exercises.create!(title: "Segundo exercício", exercise_type: :quiz, object: {
      "questions" => [ { "question_type" => "short_answer", "statement" => "Outra?", "correct_answer" => "Sim" } ]
    })
    @published.activity_exercises.create!(exercise: second, position: 2, points: 2)
    login(@teacher)
    get new_exercise_url(activity_id: @published.id)
    assert_select "input[type='hidden'][name='activity_id'][value='#{@published.id}']", count: 1

    delete logout_url
    login(@student)
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: @link.id, answers: { "0" => "Resposta" } } }
    follow_redirect!
    assert_select "a[href='#{activity_path(@published)}']", text: "Voltar à aula", minimum: 1
    assert_select "a", text: "Próximo exercício", count: 1
  end

  private

  def assert_no_exercise_management
    assert_select "table.exercise-table", count: 0
    assert_select "table[data-controller='sortable-exercises']", count: 0
    assert_select "tr[draggable='true']", count: 0
    assert_select "form[action='#{activity_exercises_path}']", count: 0
    assert_select "a", text: "Criar exercício", count: 0
    assert_select "button", text: "Remover", count: 0
    assert_select "a", text: @exercise.title, count: 0
  end

  def create_user(klass, prefix)
    id = "#{prefix}-#{SecureRandom.hex(6)}"
    klass.create!(name: prefix, username: id, email: "#{id}@example.com", password: "secret123")
  end

  def login(user)
    role = user.is_a?(Teacher) ? "teacher" : "student"
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end
end
