require "test_helper"

class TeacherDashboardTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = create_teacher("dashprof")
    @school_class = @teacher.school_classes.create!(name: "Turma Alfa", active: true)
    @other_teacher = create_teacher("dashother")
    @other_class = @other_teacher.school_classes.create!(name: "Turma Privada", active: true)
    @student = create_student("dashstudent")
  end

  test "teacher accesses the dashboard with the first class by name selected" do
    @teacher.school_classes.create!(name: "Turma Beta", active: true)
    @teacher.school_classes.create!(name: "Turma Inativa", active: false)

    sign_in(@teacher, "teacher")
    get dashboard_url

    assert_response :success
    assert_select "main.dashboard-page h1", text: "Dashboard"
    assert_select "h2.dashboard-class-title", text: "Turma Alfa"
    assert_select "select#school_class_id option", count: 2
    assert_select "select#school_class_id option[selected][value='#{@school_class.id}']", count: 1
    assert_select "a[href='#{exercise_attempts_path(school_class_id: @school_class.id)}']", text: "Ver resultados da turma"
    assert_not_includes response.body, "Turma Privada"
    assert_not_includes response.body, "Turma Inativa"
  end

  test "valid class filter selects that class" do
    beta = @teacher.school_classes.create!(name: "Turma Beta", active: true)

    sign_in(@teacher, "teacher")
    get dashboard_url(school_class_id: beta.id)

    assert_response :success
    assert_select "h2.dashboard-class-title", text: "Turma Beta"
    assert_select "select#school_class_id option[selected][value='#{beta.id}']", count: 1
  end

  test "teacher cannot select another teacher's or an unknown class" do
    sign_in(@teacher, "teacher")

    [ @other_class.id, 0, "abc" ].each do |school_class_id|
      get dashboard_url(school_class_id:)

      assert_redirected_to root_path
      assert_equal "Turma inválida.", flash[:alert]
    end
  end

  test "student cannot see the teacher dashboard content and gets their own" do
    sign_in(@student, "student")

    get dashboard_url

    assert_response :success
    assert_select "main.dashboard-page h1", text: "Dashboard"
    assert_select ".dashboard-ranking", count: 0
    assert_select "select#student_id", count: 0
  end

  test "unauthenticated user is sent to login" do
    get dashboard_url

    assert_redirected_to login_path
  end

  test "teacher without classes sees the empty state" do
    @other_class.update!(active: false)
    sign_in(@other_teacher, "teacher")

    get dashboard_url

    assert_response :success
    assert_select ".dashboard-empty[role='status']", text: "Você ainda não possui turmas ativas."
    assert_select ".dashboard-metric", count: 0
    assert_select "form.dashboard-filter", count: 0
  end

  test "class without students, lessons or attempts shows zeros and dashes" do
    sign_in(@teacher, "teacher")

    get dashboard_url

    assert_response :success
    assert_select ".dashboard-metric--students dd", text: "0"
    assert_select ".dashboard-metric--activities dd", text: "0"
    assert_select ".dashboard-metric--exercises dd", text: "0"
    assert_select ".dashboard-metric--average dd", text: "—"
    assert_select ".dashboard-metric--completion dd", text: "—"
    assert_select "progress.dashboard-progress", count: 0
    assert_select ".dashboard-metrics--general .dashboard-metric", count: 3
    assert_select ".dashboard-metrics--performance .dashboard-metric", count: 2
  end

  test "counts and indicators match the existing results services" do
    other_student = create_student("dashstudent2")
    inactive_student = create_student("dashstudent3")
    @school_class.class_students.create!(student: @student, active: true)
    @school_class.class_students.create!(student: other_student, active: true)
    @school_class.class_students.create!(student: inactive_student, active: false)
    first_activity = @school_class.activities.create!(title: "Aula 1", published: true)
    draft_activity = @school_class.activities.create!(title: "Rascunho", published: false)
    @school_class.activities.create!(title: "Aula inativa", published: true, active: false)
    exercise = @teacher.exercises.create!(title: "Quiz", exercise_type: :quiz, object: quiz_object)
    first_link = first_activity.activity_exercises.create!(exercise:, position: 1, points: 10)
    draft_activity.activity_exercises.create!(exercise:, position: 1, points: 10)
    Exercises::QuizSubmission.call(activity_exercise: first_link, student: @student, answers: { "0" => "a", "1" => "42" })
    Exercises::QuizSubmission.call(activity_exercise: first_link, student: other_student, answers: { "0" => "b", "1" => "0" })
    Exercises::QuizSubmission.call(activity_exercise: first_link, student: inactive_student, answers: { "0" => "a", "1" => "42" })

    expected = ResultsDashboard.call(user: @teacher, school_class: @school_class)
    sign_in(@teacher, "teacher")
    get dashboard_url(school_class_id: @school_class.id)

    assert_response :success
    assert_select ".dashboard-metric--students dd", text: "2"
    assert_select ".dashboard-metric--activities dd", text: "2"
    assert_select ".dashboard-metric--exercises dd", text: "2"
    assert_select ".dashboard-metric--exercises .dashboard-metric-note", text: "1 exercício distinto"
    assert_select ".dashboard-metric--average dd", text: ActionController::Base.helpers.number_to_percentage(expected[:class_average], precision: 1)
    assert_select ".dashboard-metric--completion dd", text: "50.0%"
    assert_select ".dashboard-metric--completion .dashboard-metric-note", text: "2 / 4 resultados aluno-exercício"
    assert_select ".dashboard-metric--completion progress.dashboard-progress[max='100'][value='50.0']", count: 1
    assert_select ".dashboard-metric--average progress.dashboard-progress[max='100'][value='#{expected[:class_average].to_f.clamp(0, 100)}']", count: 1
    assert_equal 2, expected[:completed_exercises]
    assert_equal 4, expected[:possible_exercises]
  end

  test "dashboard link is in the sidebar of both profiles" do
    sign_in(@teacher, "teacher")
    get dashboard_url

    assert_select ".internal-navigation-link[href='#{dashboard_path}'][aria-current='page']", text: "Dashboard"
    assert_select ".internal-navigation-link[href='#{exercise_attempts_path}']", text: "Resultados"

    sign_in(@student, "student")
    get exercise_attempts_url

    assert_select ".internal-navigation-link[href='#{dashboard_path}']", text: "Dashboard"
    assert_select ".internal-navigation-link[href='#{dashboard_path}'][aria-current]", count: 0
  end

  test "service rejects a class from another teacher" do
    assert_raises(ArgumentError) { TeacherDashboard.call(teacher: @teacher, school_class: @other_class) }
  end

  private

  def quiz_object
    {
      "questions" => [
        { "question_type" => "multiple_choice", "statement" => "Escolha A.", "options" => [ { "id" => "a", "text" => "A" }, { "id" => "b", "text" => "B" } ], "correct_option_ids" => [ "a" ] },
        { "question_type" => "short_answer", "statement" => "Responda 42.", "correct_answer" => "42" }
      ]
    }
  end

  def create_teacher(prefix)
    username = "#{prefix}_#{SecureRandom.hex(5)}"
    Teacher.create!(name: prefix, username:, email: "#{username}@example.test", password: "secret123")
  end

  def create_student(prefix)
    username = "#{prefix}_#{SecureRandom.hex(5)}"
    Student.create!(name: prefix, username:, email: "#{username}@example.test", password: "secret123")
  end

  def sign_in(user, role)
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end
end
