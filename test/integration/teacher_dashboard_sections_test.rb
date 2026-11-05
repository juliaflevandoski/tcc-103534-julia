require "test_helper"

class TeacherDashboardSectionsTest < ActionDispatch::IntegrationTest
  RIGHT = { "0" => "a", "1" => "42" }.freeze
  WRONG = { "0" => "b", "1" => "0" }.freeze

  setup do
    @teacher = create_teacher("secprof")
    @school_class = @teacher.school_classes.create!(name: "Turma Secoes", active: true)
    @student_one = create_student("secone")
    @student_two = create_student("sectwo")
  end

  test "lesson completion covers full, partial, none, no exercises and draft lessons" do
    enroll(@student_one, @student_two)
    full = create_activity("Aula completa")
    partial = create_activity("Aula parcial")
    none = create_activity("Aula sem conclusoes")
    create_activity("Aula sem exercicios")
    draft = create_activity("Aula rascunho", published: false)
    full_link = link(full, "Quiz completa")
    partial_link = link(partial, "Quiz parcial")
    link(none, "Quiz nenhuma")
    link(draft, "Quiz rascunho")
    [ @student_one, @student_two ].each { |student| submit(full_link, student, RIGHT) }
    submit(partial_link, @student_one, RIGHT)

    get_dashboard
    rows = lesson_rows

    assert_equal [ "2 de 2 alunos concluíram", "100.0%" ], rows.fetch("Aula completa")
    assert_equal [ "1 de 2 alunos concluíram", "50.0%" ], rows.fetch("Aula parcial")
    assert_equal [ "0 de 2 alunos concluíram", "0.0%" ], rows.fetch("Aula sem conclusoes")
    assert_equal [ "0 de 2 alunos concluíram", "0.0%" ], rows.fetch("Aula sem exercicios")
    assert_equal [ "Aula ainda não publicada para os alunos", "—" ], rows.fetch("Aula rascunho Rascunho")
    assert_select ".dashboard-lesson progress.dashboard-progress[value='100.0']", count: 1
    assert_select ".dashboard-lesson progress.dashboard-progress", count: 4
    assert_select ".dashboard-lesson-draft", text: "Rascunho", count: 1
    assert_select ".dashboard-metric", count: 5
    assert_select ".dashboard-metric--students dd", text: "2"
  end

  test "lessons without eligible students show a dash and no bar" do
    create_activity("Aula vazia")

    get_dashboard

    assert_equal [ "0 de 0 alunos concluíram", "—" ], lesson_rows.fetch("Aula vazia")
    assert_select ".dashboard-lesson progress", count: 0
  end

  test "rankings order by average, break ties by link id and exclude exercises without grades" do
    enroll(@student_one, @student_two)
    first = create_activity("Aula A")
    second = create_activity("Aula B")
    high_link = link(first, "Quiz alto")
    tied_link = link(second, "Quiz empatado")
    low_link = link(first, "Quiz baixo")
    link(second, "Quiz sem notas")
    [ @student_one, @student_two ].each { |student| submit(high_link, student, RIGHT) }
    submit(tied_link, @student_one, RIGHT)
    submit(low_link, @student_one, WRONG)

    get_dashboard

    assert_equal [ "Quiz alto", "Quiz empatado", "Quiz baixo" ], ranking_titles("dashboard-best-title")
    assert_equal [ "Quiz baixo", "Quiz alto", "Quiz empatado" ], ranking_titles("dashboard-worst-title")
    assert_select ".dashboard-rankings", text: /Quiz sem notas/, count: 0
    assert_select "#dashboard-best-title ~ ol .dashboard-ranking-average", text: "100.0%", count: 2
    assert_select "#dashboard-best-title ~ ol", text: /Aula: Aula A.*2 alunos com nota oficial/m
    assert_select "#dashboard-best-title ~ ol", text: /Aula: Aula B.*1 aluno com nota oficial/m
  end

  test "an exercise reused in two lessons is ranked per link with its lesson" do
    enroll(@student_one)
    first = create_activity("Aula Um")
    second = create_activity("Aula Dois")
    exercise = @teacher.exercises.create!(title: "Quiz reutilizado", exercise_type: :quiz, object: quiz_object)
    first_link = first.activity_exercises.create!(exercise:, position: 1, points: 10)
    second_link = second.activity_exercises.create!(exercise:, position: 1, points: 10)
    submit(first_link, @student_one, RIGHT)
    submit(second_link, @student_one, WRONG)

    get_dashboard

    assert_equal [ "Quiz reutilizado", "Quiz reutilizado" ], ranking_titles("dashboard-best-title")
    assert_select "#dashboard-best-title ~ ol li:first-child", text: /Aula: Aula Um.*100\.0%/m
    assert_select "#dashboard-worst-title ~ ol li:first-child", text: /Aula: Aula Dois.*0\.0%/m
  end

  test "a deactivated official attempt still counts and later attempts are not promoted" do
    enroll(@student_one)
    activity = create_activity("Aula oficial")
    activity_link = link(activity, "Quiz oficial")
    official = submit(activity_link, @student_one, WRONG)
    submit(activity_link, @student_one, RIGHT)
    official.update!(active: false)

    get_dashboard

    assert_equal [ "Quiz oficial" ], ranking_titles("dashboard-best-title")
    assert_select "#dashboard-best-title ~ ol .dashboard-ranking-average", text: "0.0%"
    assert_select "#dashboard-best-title ~ ol", text: /1 aluno com nota oficial/
  end

  test "rankings show an explanatory empty state without data and cap at three items" do
    get_dashboard

    assert_select ".dashboard-ranking .dashboard-empty[role='status']", count: 2
    assert_select ".dashboard-lessons .dashboard-empty", text: "Esta turma ainda não possui aulas ativas."

    enroll(@student_one)
    activity = create_activity("Aula muitos")
    4.times { |index| submit(link(activity, "Quiz #{index}"), @student_one, RIGHT) }

    get_dashboard

    assert_equal 3, ranking_titles("dashboard-best-title").length
    assert_equal 3, ranking_titles("dashboard-worst-title").length
  end

  test "other teachers' data never appears and the five indicators remain" do
    other_teacher = create_teacher("secother")
    other_class = other_teacher.school_classes.create!(name: "Turma Alheia", active: true)
    other_activity = other_class.activities.create!(title: "Aula Alheia", published: true)
    other_exercise = other_teacher.exercises.create!(title: "Quiz Alheio", exercise_type: :quiz, object: quiz_object)
    other_link = other_activity.activity_exercises.create!(exercise: other_exercise, position: 1, points: 10)
    other_class.class_students.create!(student: @student_two, active: true)
    submit(other_link, @student_two, RIGHT)
    enroll(@student_one)

    get_dashboard

    assert_not_includes response.body, "Aula Alheia"
    assert_not_includes response.body, "Quiz Alheio"
    assert_select ".dashboard-metric", count: 5
    assert_select ".dashboard-metric--students dd", text: "1"
  end

  private

  def get_dashboard
    sign_in(@teacher)
    get dashboard_url(school_class_id: @school_class.id)
    assert_response :success
  end

  def lesson_rows
    css_select(".dashboard-lesson").to_h do |node|
      [ node.at_css(".dashboard-lesson-title").text.squish,
        [ node.at_css(".dashboard-lesson-count").text.squish, node.at_css(".dashboard-lesson-percentage").text.squish ] ]
    end
  end

  def ranking_titles(heading_id)
    css_select("##{heading_id} ~ ol .dashboard-ranking-title").map { |node| node.text.squish }
  end

  def enroll(*students)
    students.each { |student| @school_class.class_students.create!(student:, active: true) }
  end

  def create_activity(title, published: true)
    @school_class.activities.create!(title:, published:)
  end

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

  def create_student(prefix)
    username = "#{prefix}_#{SecureRandom.hex(5)}"
    Student.create!(name: prefix, username:, email: "#{username}@example.test", password: "secret123")
  end

  def sign_in(user)
    post login_url, params: { role: "teacher", username: user.username, password: "secret123" }
  end
end
