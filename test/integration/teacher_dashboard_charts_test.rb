require "test_helper"

class TeacherDashboardChartsTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = create_teacher("chartteacher")
    @class_a = @teacher.school_classes.create!(name: "Alfa", active: true)
    @class_b = @teacher.school_classes.create!(name: "Beta", active: true)
    @student_a = create_student("chartstudenta")
    @student_b = create_student("chartstudentb")
    [ @student_a, @student_b ].each { |student| @class_a.class_students.create!(student:, active: true) }
    @class_b.class_students.create!(student: @student_a, active: true)
    @lesson_a = @class_a.activities.create!(title: "Aula A", published: true)
    @lesson_b = @class_a.activities.create!(title: "Aula B", published: true)
    @link_a = create_link(@teacher, @lesson_a, "Quiz A")
    @link_b = create_link(@teacher, @lesson_b, "Quiz B")
    @link_beta = create_link(@teacher, @class_b.activities.create!(title: "Aula Beta", published: true), "Quiz Beta")
    submit(@link_a, @student_a, "42", Date.new(2026, 1, 5))
    submit(@link_a, @student_b, "wrong", Date.new(2026, 1, 5))
    submit(@link_a, @student_b, "42", Date.new(2026, 1, 12))
    submit(@link_b, @student_a, "42", Date.new(2026, 1, 19))
    submit(@link_beta, @student_a, "wrong", Date.new(2026, 2, 2))
    sign_in(@teacher)
  end

  test "renders weekly charts with gaps, official counts and accessible tables" do
    get dashboard_url(school_class_id: @class_a.id)

    assert_response :success
    assert_select "#teacher-evolution-title", text: "Evolução da turma"
    assert_select ".dashboard-evolution-intro", text: /elegibilidade atual/
    assert_select ".dashboard-evolution-intro", text: /Jogo da Memória.*anterior à conclusão/
    assert_select "#teacher-performance-chart .time-series-chart-description", text: /média das médias dos alunos/
    assert_chart "teacher-performance-chart", "line", "percent", [ 50.0, nil, 100.0 ]
    assert_chart "teacher-exercises-chart", "bar", "count", [ 2, 0, 1 ]
    assert_chart "teacher-participants-chart", "bar", "count", [ 2, 0, 1 ]
    assert_select "#teacher-performance-chart details[open] tbody tr", count: 3
    assert_select "#teacher-performance-chart td.time-series-chart-no-data", text: "Sem dados"
    assert_select "#teacher-exercises-chart tbody td", text: "0"
    assert_select "#teacher-participants-chart caption", text: "Alunos participantes"
  end

  test "class filter limits chart data to the selected class" do
    get dashboard_url(school_class_id: @class_b.id)

    assert_response :success
    assert_equal [ "Semana de 02/02/2026" ], chart("teacher-performance-chart").fetch("weeks").map { |week| week.fetch("full") }
    assert_chart "teacher-performance-chart", "line", "percent", [ 0.0 ]
    assert_chart "teacher-exercises-chart", "bar", "count", [ 1 ]
    assert_chart "teacher-participants-chart", "bar", "count", [ 1 ]
  end

  test "student filter limits results and hides participants chart" do
    get dashboard_url(school_class_id: @class_a.id, student_id: @student_a.id)

    assert_response :success
    assert_chart "teacher-performance-chart", "line", "percent", [ 100.0, nil, 100.0 ]
    assert_chart "teacher-exercises-chart", "bar", "count", [ 1, 0, 1 ]
    assert_select "#teacher-participants-chart", count: 0
  end

  test "lesson filter restricts all three charts" do
    get dashboard_url(school_class_id: @class_a.id, activity_id: @lesson_b.id)

    assert_response :success
    assert_chart "teacher-performance-chart", "line", "percent", [ 100.0 ]
    assert_chart "teacher-exercises-chart", "bar", "count", [ 1 ]
    assert_chart "teacher-participants-chart", "bar", "count", [ 1 ]
    assert_equal "Semana de 19/01/2026", chart("teacher-exercises-chart").fetch("weeks").first.fetch("full")
  end

  test "exercise link filter works without an explicit lesson" do
    get dashboard_url(school_class_id: @class_a.id, activity_exercise_id: @link_a.id)

    assert_response :success
    assert_chart "teacher-performance-chart", "line", "percent", [ 50.0 ]
    assert_chart "teacher-exercises-chart", "bar", "count", [ 2 ]
    assert_chart "teacher-participants-chart", "bar", "count", [ 2 ]
  end

  test "student lesson and exercise filters combine" do
    get dashboard_url(
      school_class_id: @class_a.id, student_id: @student_b.id,
      activity_id: @lesson_a.id, activity_exercise_id: @link_a.id
    )

    assert_response :success
    assert_chart "teacher-performance-chart", "line", "percent", [ 0.0 ]
    assert_chart "teacher-exercises-chart", "bar", "count", [ 1 ]
    assert_select "#teacher-participants-chart", count: 0
  end

  test "empty filtered results display a message for each visible chart" do
    empty_link = create_link(@teacher, @lesson_a, "Sem tentativas")
    get dashboard_url(school_class_id: @class_a.id, activity_exercise_id: empty_link.id)

    assert_response :success
    assert_select ".dashboard-evolution .time-series-chart-empty-message[role='status']",
      text: "Não há tentativas oficiais para os filtros selecionados.", count: 3
    assert_select ".dashboard-evolution .time-series-chart-table", count: 0
  end

  test "foreign teacher data is neither displayed nor available through filters" do
    foreign_teacher = create_teacher("foreigncharts")
    foreign_class = foreign_teacher.school_classes.create!(name: "Turma secreta", active: true)
    foreign_student = create_student("foreignstudent")
    foreign_class.class_students.create!(student: foreign_student, active: true)
    foreign_lesson = foreign_class.activities.create!(title: "Aula secreta", published: true)
    foreign_link = create_link(foreign_teacher, foreign_lesson, "Quiz secreto")
    submit(foreign_link, foreign_student, "42", Date.new(2027, 3, 1))

    get dashboard_url(school_class_id: @class_a.id)
    assert_response :success
    assert_not_includes response.body, "Turma secreta"
    assert_not_includes response.body, "Quiz secreto"
    assert_not_includes response.body, "01/03/2027"
    assert_chart "teacher-exercises-chart", "bar", "count", [ 2, 0, 1 ]

    [
      { school_class_id: foreign_class.id },
      { school_class_id: @class_a.id, student_id: foreign_student.id },
      { school_class_id: @class_a.id, activity_id: foreign_lesson.id },
      { school_class_id: @class_a.id, activity_exercise_id: foreign_link.id }
    ].each do |filters|
      get dashboard_url(filters)
      assert_redirected_to root_path
      assert_select ".time-series-chart", count: 0
    end
  end

  private

  def assert_chart(id, type, unit, values)
    assert_select "##{id}", count: 1
    payload = chart(id)
    assert_equal type, payload.fetch("type")
    assert_equal unit, payload.fetch("unit")
    assert_equal values, payload.fetch("series").first.fetch("values")
  end

  def chart(id)
    JSON.parse(css_select("##{id}").first["data-time-series-chart-chart-value"])
  end

  def create_teacher(prefix)
    username = "#{prefix}_#{SecureRandom.hex(5)}"
    Teacher.create!(name: prefix, username:, email: "#{username}@example.test", password: "secret123")
  end

  def create_student(prefix)
    username = "#{prefix}_#{SecureRandom.hex(5)}"
    Student.create!(name: prefix, username:, email: "#{username}@example.test", password: "secret123")
  end

  def create_link(teacher, activity, title)
    exercise = teacher.exercises.create!(
      title:, exercise_type: :quiz,
      object: { "questions" => [ { "question_type" => "short_answer", "statement" => "Responda 42.", "correct_answer" => "42" } ] }
    )
    activity.activity_exercises.create!(exercise:, position: activity.activity_exercises.active.maximum(:position).to_i + 1, points: 10)
  end

  def submit(link, student, answer, date)
    attempt = Exercises::QuizSubmission.call(activity_exercise: link, student:, answers: { "0" => answer }).attempt
    attempt.update_columns(created_at: Time.zone.local(date.year, date.month, date.day, 12))
  end

  def sign_in(teacher)
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }
  end
end
