require "test_helper"

class TeacherDashboardStudentFilterTest < ActionDispatch::IntegrationTest
  RIGHT = { "0" => "a", "1" => "42" }.freeze
  WRONG = { "0" => "b", "1" => "0" }.freeze

  setup do
    @teacher = create_teacher("stfprof")
    @school_class = @teacher.school_classes.create!(name: "Turma Aluno", active: true)
    @ana = create_student("Ana")
    @bruno = create_student("Bruno")
    [ @ana, @bruno ].each { |student| @school_class.class_students.create!(student:, active: true) }
    @lesson = @school_class.activities.create!(title: "Aula A", published: true)
    @draft = @school_class.activities.create!(title: "Aula Rascunho", published: false)
    @link_one = link(@lesson, "Quiz Um")
    @link_two = link(@lesson, "Quiz Dois")
    @draft_link = link(@draft, "Quiz Rascunho")
    submit(@link_one, @ana, RIGHT)
    submit(@link_two, @ana, WRONG)
    submit(@link_two, @ana, RIGHT) # tentativa posterior, não oficial
    submit(@link_one, @bruno, WRONG)
    sign_in(@teacher)
  end

  test "all students keeps the current indicators" do
    get dashboard_url(school_class_id: @school_class.id)

    assert_response :success
    assert_select "select#student_id option", count: 3
    assert_select "select#student_id option[selected]", count: 0
    assert_select "select#student_id option", text: "Todos os alunos"
    assert_select ".dashboard-filter-note", count: 0
    assert_select ".dashboard-metric--students dd", text: "2"
    expected = ResultsDashboard.call(user: @teacher, school_class: @school_class)
    assert_select ".dashboard-metric--average dd", text: ActionController::Base.helpers.number_to_percentage(expected[:class_average], precision: 1)
  end

  test "a valid student filters average, completion, lessons and rankings" do
    get dashboard_url(school_class_id: @school_class.id, student_id: @ana.id)

    assert_response :success
    assert_select "select#student_id option[selected][value='#{@ana.id}']", count: 1
    assert_select ".dashboard-filter-note", text: /aluno: Ana/
    assert_select ".dashboard-metric--students dd", text: "1"
    assert_select ".dashboard-metric--activities dd", text: "2"
    assert_select ".dashboard-metric--exercises dd", text: "3"
    assert_select ".dashboard-metric--average dd", text: "50.0%"
    assert_select ".dashboard-metric--completion dd", text: "66.7%"
    assert_select ".dashboard-metric--completion .dashboard-metric-note", text: "2 / 3 resultados aluno-exercício"
    assert_select ".dashboard-lesson-count", text: "1 de 1 aluno concluiu"
    assert_equal [ "Quiz Um", "Quiz Dois" ], css_select("#dashboard-best-title ~ ol .dashboard-ranking-title").map { |node| node.text.squish }
    assert_equal [ "Quiz Dois", "Quiz Um" ], css_select("#dashboard-worst-title ~ ol .dashboard-ranking-title").map { |node| node.text.squish }
    assert_select "#dashboard-best-title ~ ol", text: /1 aluno com nota oficial/
  end

  test "another student sees only their own results" do
    get dashboard_url(school_class_id: @school_class.id, student_id: @bruno.id)

    assert_select ".dashboard-metric--average dd", text: "0.0%"
    assert_select ".dashboard-metric--completion .dashboard-metric-note", text: "1 / 3 resultados aluno-exercício"
    assert_select ".dashboard-lesson-count", text: "0 de 1 aluno concluiu"
    assert_equal [ "Quiz Um" ], css_select("#dashboard-best-title ~ ol .dashboard-ranking-title").map { |node| node.text.squish }
  end

  test "a student without results shows dashes and no bars" do
    newcomer = create_student("Carla")
    @school_class.class_students.create!(student: newcomer, active: true)

    get dashboard_url(school_class_id: @school_class.id, student_id: newcomer.id)

    assert_select ".dashboard-metric--average dd", text: "—"
    assert_select ".dashboard-metric--average progress", count: 0
    assert_select ".dashboard-ranking .dashboard-empty", count: 2
  end

  test "student filter combines with lesson and exercise and keeps a draft without completion" do
    get dashboard_url(school_class_id: @school_class.id, student_id: @ana.id, activity_id: @draft.id)
    assert_response :success
    assert_select ".dashboard-metric--activities dd", text: "1"
    assert_select ".dashboard-lesson-percentage", text: "—"
    assert_select ".dashboard-lesson progress", count: 0
    assert_select ".dashboard-lesson-draft", text: "Rascunho"

    get dashboard_url(school_class_id: @school_class.id, student_id: @ana.id, activity_exercise_id: @link_two.id)
    assert_select ".dashboard-metric--exercises dd", text: "1"
    assert_select ".dashboard-metric--average dd", text: "0.0%"
    assert_select ".dashboard-metric--completion .dashboard-metric-note", text: "1 / 1 resultados aluno-exercício"
    assert_select "select#student_id option[selected][value='#{@ana.id}']", count: 1
  end

  test "students from another class, another teacher, inactive enrollments and bad ids are rejected" do
    other_class = @teacher.school_classes.create!(name: "Outra", active: true)
    elsewhere = create_student("Elsewhere")
    other_class.class_students.create!(student: elsewhere, active: true)
    foreign_teacher = create_teacher("stfother")
    foreign_class = foreign_teacher.school_classes.create!(name: "Alheia", active: true)
    foreign = create_student("Foreign")
    foreign_class.class_students.create!(student: foreign, active: true)
    left = create_student("Left")
    @school_class.class_students.create!(student: left, active: false)
    inactive_student = create_student("Inactive")
    @school_class.class_students.create!(student: inactive_student, active: true)
    inactive_student.update!(active: false)

    [ elsewhere.id, foreign.id, left.id, inactive_student.id, 0, "abc", 999_999 ].each do |id|
      get dashboard_url(school_class_id: @school_class.id, student_id: id)

      assert_redirected_to root_path
      assert_equal "Aluno inválido.", flash[:alert]
    end
  end

  test "options list only active students of the class and embed per-class data without foreign students" do
    left = create_student("Left")
    @school_class.class_students.create!(student: left, active: false)
    other_class = @teacher.school_classes.create!(name: "Zeta", active: true)
    zeta = create_student("Zeta Student")
    other_class.class_students.create!(student: zeta, active: true)
    foreign_class = create_teacher("stfother").school_classes.create!(name: "Alheia", active: true)
    foreign_class.class_students.create!(student: create_student("Foreign"), active: true)

    get dashboard_url(school_class_id: @school_class.id)

    assert_equal [ "Todos os alunos", "Ana", "Bruno" ], css_select("select#student_id option").map { |node| node.text.squish }
    options = JSON.parse(css_select("form[data-controller='dashboard-filter']").first["data-dashboard-filter-options-value"])
    assert_equal [ "Ana", "Bruno" ], options[@school_class.id.to_s]["students"].map { |s| s["label"] }
    assert_equal [ "Zeta Student" ], options[other_class.id.to_s]["students"].map { |s| s["label"] }
    assert_not_includes response.body, "Foreign"
    assert_not_includes response.body, "Left"
  end

  test "class change renders that class's students and rejects the old student" do
    other_class = @teacher.school_classes.create!(name: "Zeta", active: true)
    other_class.class_students.create!(student: create_student("Zeta Student"), active: true)

    get dashboard_url(school_class_id: other_class.id)
    assert_equal [ "Todos os alunos", "Zeta Student" ], css_select("select#student_id option").map { |node| node.text.squish }

    get dashboard_url(school_class_id: other_class.id, student_id: @ana.id)
    assert_redirected_to root_path
    assert_equal "Aluno inválido.", flash[:alert]
  end

  test "student select is wired to the Stimulus controller and only changes lesson/exercise do not reset it" do
    get dashboard_url(school_class_id: @school_class.id)

    assert_select "select#student_id[data-dashboard-filter-target='student']"
    assert_select "select#student_id[data-action]", count: 0
    assert_select "select#activity_id[data-action='change->dashboard-filter#resetExercise']"
  end

  test "service rejects a student without active enrollment in the class" do
    outsider = create_student("Outsider")

    assert_raises(ArgumentError) { TeacherDashboard.call(teacher: @teacher, school_class: @school_class, student: outsider) }
  end

  private

  def link(activity, title)
    exercise = @teacher.exercises.create!(title:, exercise_type: :quiz, object: quiz_object)
    activity.activity_exercises.create!(exercise:, position: activity.activity_exercises.active.maximum(:position).to_i + 1, points: 10)
  end

  def submit(activity_exercise, student, answers)
    Exercises::QuizSubmission.call(activity_exercise:, student:, answers:).attempt
  end

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

  def create_student(name)
    username = "#{name.downcase.delete(' ')}_#{SecureRandom.hex(5)}"
    Student.create!(name:, username:, email: "#{username}@example.test", password: "secret123")
  end

  def sign_in(user)
    post login_url, params: { role: "teacher", username: user.username, password: "secret123" }
  end
end
