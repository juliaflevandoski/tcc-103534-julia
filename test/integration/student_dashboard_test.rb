require "test_helper"

class StudentDashboardTest < ActionDispatch::IntegrationTest
  RIGHT = { "0" => "a", "1" => "42" }.freeze
  WRONG = { "0" => "b", "1" => "0" }.freeze

  setup do
    @teacher = create_teacher("sdprof")
    @student = create_student("sdstud")
    @other_student = create_student("sdother")
    @class_a = @teacher.school_classes.create!(name: "Alfa", active: true)
    @class_b = @teacher.school_classes.create!(name: "Beta", active: true)
    [ @class_a, @class_b ].each do |school_class|
      school_class.class_students.create!(student: @student, active: true)
      school_class.class_students.create!(student: @other_student, active: true)
    end
    @lesson_a1 = @class_a.activities.create!(title: "A1", published: true)
    @lesson_a2 = @class_a.activities.create!(title: "A2", published: true)
    @draft = @class_a.activities.create!(title: "Rascunho A", published: false)
    @lesson_b = @class_b.activities.create!(title: "B1", published: true)
    @a1_x = link(@lesson_a1, "X")
    @a1_y = link(@lesson_a1, "Y")
    @a2_z = link(@lesson_a2, "Z")
    @draft_link = link(@draft, "D")
    @b_w = link(@lesson_b, "W")
    submit(@a1_x, @student, RIGHT)
    submit(@a1_y, @student, WRONG)
    submit(@a1_y, @student, RIGHT) # posterior, não oficial
    submit(@b_w, @student, RIGHT)
    submit(@a1_x, @other_student, WRONG)
  end

  test "student sees own indicators across all classes by default" do
    sign_in(@student)
    get dashboard_url

    assert_response :success
    assert_select "select#school_class_id option", count: 3
    assert_select "select#school_class_id option[selected]", count: 0
    assert_select "select#school_class_id option", text: "Todas as turmas"
    assert_select ".dashboard-metric--classes dd", text: "2"
    assert_select ".dashboard-metric--activities dd", text: "2 / 3"
    assert_select ".dashboard-metric--exercises dd", text: "3 / 4"
    assert_select ".dashboard-metric--average dd", text: "66.7%"
    assert_select ".dashboard-metric--completion dd", text: "75.0%"
    assert_select "a[href='#{exercise_attempts_path}']", text: "Meus resultados"
    assert_select ".internal-navigation-link[href='#{dashboard_path}'][aria-current='page']", text: "Dashboard"
    assert_select ".dashboard-empty a[href='#{school_classes_path}']", count: 0
  end

  test "class filter limits the indicators and the results link" do
    sign_in(@student)
    get dashboard_url(school_class_id: @class_a.id)

    assert_select "select#school_class_id option[selected][value='#{@class_a.id}']", count: 1
    assert_select "h2.dashboard-class-title", text: "Alfa"
    assert_select ".dashboard-metric--classes dd", text: "1"
    assert_select ".dashboard-metric--activities dd", text: "1 / 2"
    assert_select ".dashboard-metric--exercises dd", text: "2 / 3"
    assert_select ".dashboard-metric--average dd", text: "50.0%"
    assert_select "a[href='#{exercise_attempts_path(school_class_id: @class_a.id)}']", text: "Meus resultados"
  end

  test "lesson completion follows lesson_completed and ignores drafts" do
    submit(@a1_y, @other_student, RIGHT)
    submit(@a1_x, @student, RIGHT) # nova tentativa não muda nada
    sign_in(@student)
    get dashboard_url(school_class_id: @class_a.id)
    assert_select ".dashboard-metric--activities dd", text: "1 / 2"

    submit(@a2_z, @student, RIGHT)
    get dashboard_url(school_class_id: @class_a.id)
    assert_select ".dashboard-metric--activities dd", text: "2 / 2"
    assert_not_includes response.body, "Rascunho A"
  end

  test "values match the existing services" do
    sign_in(@student)
    get dashboard_url(school_class_id: @class_a.id)

    expected = ResultsDashboard.call(user: @student, school_class: @class_a)
    assert_select ".dashboard-metric--average dd", text: ActionController::Base.helpers.number_to_percentage(expected[:student_averages][@student.id], precision: 1)
    assert_select ".dashboard-metric--exercises dd", text: "#{expected[:completed_exercises]} / #{expected[:possible_exercises]}"
  end

  test "student never sees other students' data or other classes" do
    other_teacher = create_teacher("sdforeign")
    foreign_class = other_teacher.school_classes.create!(name: "Alheia", active: true)
    foreign_class.activities.create!(title: "Aula Alheia", published: true)
    left_class = @teacher.school_classes.create!(name: "Saiu", active: true)
    left_class.class_students.create!(student: @student, active: false)
    inactive_class = @teacher.school_classes.create!(name: "Inativa", active: false)
    inactive_class.class_students.create!(student: @student, active: true)
    sign_in(@student)

    get dashboard_url

    assert_equal [ "Todas as turmas", "Alfa", "Beta" ], css_select("select#school_class_id option").map { |node| node.text.squish }
    assert_not_includes response.body, @other_student.name

    [ foreign_class.id, left_class.id, inactive_class.id, 0, "abc" ].each do |school_class_id|
      get dashboard_url(school_class_id:)

      assert_redirected_to root_path
      assert_equal "Turma inválida.", flash[:alert]
    end
  end

  test "student without classes sees the empty state" do
    sign_in(@other_student)
    @other_student.class_students.update_all(active: false)

    get dashboard_url

    assert_response :success
    assert_select ".dashboard-empty[role='status']", text: /Você ainda não está em uma turma ativa\./
    assert_select ".dashboard-empty a[href='#{school_classes_path}']", text: "Entrar em uma turma"
    assert_select ".dashboard-metric", count: 0
    assert_select "form.dashboard-filter", count: 0

    get school_classes_url
    assert_response :success
    assert_select ".school-class-join-panel", count: 1
  end

  test "class without lessons or attempts shows zeros and dashes without bars" do
    empty = @teacher.school_classes.create!(name: "Vazia", active: true)
    empty.class_students.create!(student: @student, active: true)
    sign_in(@student)

    get dashboard_url(school_class_id: empty.id)

    assert_select ".dashboard-metric--activities dd", text: "0 / 0"
    assert_select ".dashboard-metric--exercises dd", text: "0 / 0"
    assert_select ".dashboard-metric--average dd", text: "—"
    assert_select ".dashboard-metric--completion dd", text: "—"
    assert_select ".dashboard-metric progress", count: 0
  end

  test "available lessons without attempts show 0 percent with a bar" do
    sign_in(@other_student)
    get dashboard_url(school_class_id: @class_b.id)

    assert_select ".dashboard-metric--average dd", text: "—"
    assert_select ".dashboard-metric--average progress", count: 0
    assert_select ".dashboard-metric--completion dd", text: "0.0%"
    assert_select ".dashboard-metric--completion progress", count: 1
  end

  test "student without xp sees level 1 and an empty progress" do
    StudentStat.where(student: @student).delete_all
    sign_in(@student)

    get dashboard_url

    assert_select ".dashboard-gamification-level", text: "1"
    assert_select ".dashboard-gamification-stats dd", text: "0"
    assert_select ".dashboard-gamification progress[value='0']", count: 1
    assert_select ".dashboard-gamification-progress", text: /0 \/ 100 XP neste nível · faltam 100 XP para o nível 2/
    assert_nil @student.reload.student_stat
  end

  test "gamification uses StudentLevel with own xp and stays global with a class selected" do
    StudentStat.find_or_create_by!(student: @student).update!(xp: 250, level: 3)
    StudentStat.find_or_create_by!(student: @other_student).update!(xp: 40, level: 1)
    sign_in(@student)

    [ {}, { school_class_id: @class_a.id } ].each do |params|
      get dashboard_url(params)

      info = StudentLevel.call(250)
      assert_select ".dashboard-gamification-level", text: info.level.to_s
      assert_select ".dashboard-gamification-stats dd", text: "250"
      assert_select ".dashboard-gamification progress[value='#{info.percent.round}']", count: 1
      assert_select ".dashboard-gamification-progress", text: /50 \/ 100 XP neste nível · faltam 50 XP para o nível 4/
      assert_select ".dashboard-gamification-scope", text: /toda a plataforma/
      assert_select ".gamification-badges, .gamification-badge", count: 0
    end
    assert_equal 250, @student.reload.student_stat.xp
  end

  test "gamification of another student is isolated" do
    StudentStat.find_or_create_by!(student: @other_student).update!(xp: 540, level: 6)
    sign_in(@student)

    get dashboard_url

    assert_select ".dashboard-gamification-level", text: "1"
    assert_select ".dashboard-gamification-stats dd", text: "540", count: 0
  end

  test "progress by class lists each class with its own numbers when all classes are shown" do
    sign_in(@student)
    get dashboard_url

    assert_select ".dashboard-progress-list--classes .dashboard-progress-card", count: 2
    assert_select ".dashboard-progress-card[data-school-class-id='#{@class_a.id}']" do
      assert_select "h3", text: "Alfa"
      assert_select ".dashboard-progress-detail", text: "1 / 2 aulas concluídas"
      assert_select ".dashboard-progress-detail", text: "2 / 3 exercícios realizados"
      assert_select ".dashboard-progress-detail", text: /Conclusão: 66.7%/
      assert_select ".dashboard-progress-detail", text: /Média: 50.0%/
    end
    assert_select ".dashboard-progress-card[data-school-class-id='#{@class_b.id}'] .dashboard-progress-detail", text: /Média: 100.0%/
  end

  test "selecting a class hides the class cards and keeps lessons of that class only" do
    sign_in(@student)
    get dashboard_url(school_class_id: @class_a.id)

    assert_select ".dashboard-progress-list--classes", count: 0
    assert_select "#dashboard-class-progress-title", count: 0
    assert_select ".dashboard-student-lesson", count: 2
    assert_select ".dashboard-student-lesson[data-activity-id='#{@lesson_b.id}']", count: 0
  end

  test "lessons show state, counts, bar and an authorized link; drafts and inactive lessons are hidden" do
    inactive = @class_a.activities.create!(title: "Inativa A", published: true, active: false)
    link(inactive, "I")
    sign_in(@student)
    get dashboard_url

    assert_select ".dashboard-student-lesson[data-activity-id='#{@lesson_a1.id}']" do
      assert_select "a[href='#{activity_path(@lesson_a1)}']", text: "A1"
      assert_select ".dashboard-lesson-status--done", text: "Concluída"
      assert_select ".dashboard-progress-detail", text: /2 \/ 2 exercícios realizados/
      assert_select "progress[value='100.0']", count: 1
    end
    assert_select ".dashboard-student-lesson[data-activity-id='#{@lesson_a2.id}']" do
      assert_select ".dashboard-lesson-status--pending", text: "Pendente"
      assert_select "progress[value='0.0']", count: 1
    end
    assert_select ".dashboard-student-lesson", count: 3
    assert_not_includes response.body, "Rascunho A"
    assert_not_includes response.body, "Inativa A"

    get activity_path(@lesson_a1)
    assert_response :success
  end

  test "reused exercise counts per lesson link" do
    reused = link(@lesson_a2, "X reutilizado")
    reused.update!(exercise: @a1_x.exercise)
    sign_in(@student)
    get dashboard_url(school_class_id: @class_a.id)

    assert_select ".dashboard-student-lesson[data-activity-id='#{@lesson_a1.id}'] .dashboard-progress-detail", text: /2 \/ 2 exercícios/
    assert_select ".dashboard-student-lesson[data-activity-id='#{@lesson_a2.id}'] .dashboard-progress-detail", text: /0 \/ 2 exercícios/
  end

  test "lesson without exercises is pending with no bar and student without attempts has zeros" do
    empty_lesson = @class_b.activities.create!(title: "Sem exercícios", published: true)
    sign_in(@other_student)
    get dashboard_url(school_class_id: @class_b.id)

    assert_select ".dashboard-student-lesson[data-activity-id='#{empty_lesson.id}']" do
      assert_select ".dashboard-progress-detail", text: /0 \/ 0 exercícios/
      assert_select ".dashboard-progress-detail", text: "Sem exercícios nesta aula."
      assert_select "progress", count: 0
    end
    assert_select ".dashboard-student-lesson[data-activity-id='#{@lesson_b.id}'] progress[value='0.0']", count: 1
    assert_select ".dashboard-lesson-status--done", count: 0
  end

  test "class without published lessons shows the empty lessons state" do
    empty = @teacher.school_classes.create!(name: "Vazia", active: true)
    empty.class_students.create!(student: @student, active: true)
    sign_in(@student)
    get dashboard_url(school_class_id: empty.id)

    assert_select ".dashboard-empty", text: "Nenhuma aula publicada disponível."
  end

  test "inactive enrollment removes the class from progress" do
    @class_b.class_students.find_by!(student: @student).update!(active: false)
    sign_in(@student)
    get dashboard_url

    assert_select ".dashboard-progress-list--classes .dashboard-progress-card", count: 1
    assert_select ".dashboard-student-lesson[data-activity-id='#{@lesson_b.id}']", count: 0
    assert_select ".dashboard-progress-card[data-school-class-id='#{@class_b.id}']", count: 0
  end

  test "progress never exposes data from other students" do
    sign_in(@other_student)
    get dashboard_url(school_class_id: @class_a.id)

    assert_select ".dashboard-student-lesson[data-activity-id='#{@lesson_a1.id}'] .dashboard-progress-detail", text: /1 \/ 2 exercícios/
    assert_select ".dashboard-lesson-status--done", count: 0
  end

  test "service lessons agree with ActivityResults.lesson_completed" do
    result = StudentDashboard.call(student: @student, school_classes: [ @class_a, @class_b ])

    result.classes.flat_map(&:lessons).each do |lesson|
      assert_equal ActivityResults.lesson_completed?(activity: lesson.activity, student: @student), lesson.completed
    end
    assert_equal result.lessons_completed, result.classes.sum(&:lessons_completed)
  end

  test "evolution section shows both charts with aggregated data across all classes" do
    date_attempts
    sign_in(@student)
    get dashboard_url

    assert_select "section.dashboard-evolution h2", text: "Sua evolução"
    assert_select "section.dashboard-evolution .dashboard-evolution-intro", text: /em todas as turmas/
    assert_select "figure#student-performance-chart.time-series-chart--line", count: 1
    assert_select "figure#student-exercises-chart.time-series-chart--line", count: 1

    performance = chart_payload("student-performance-chart")
    assert_equal "percent", performance["unit"]
    assert_equal [ "05/01", "12/01", "19/01", "26/01" ], performance["weeks"].map { |week| week["label"] }
    assert_equal [ 100.0, 50.0, 50.0 ], performance["series"][0]["values"].first(3)
    assert_in_delta 200.0 / 3, performance["series"][0]["values"].last

    exercises = chart_payload("student-exercises-chart")
    assert_equal "count", exercises["unit"]
    assert_equal [ 1, 2, 2, 3 ], exercises["series"][0]["values"]
    assert_select "#student-performance-chart details[open] table tbody tr", count: 4
  end

  test "evolution with a selected class only uses that class and ignores later attempts" do
    date_attempts
    sign_in(@student)
    get dashboard_url(school_class_id: @class_a.id)

    assert_select ".dashboard-evolution-intro", text: /na turma Alfa/
    assert_equal [ 100.0, 50.0 ], chart_payload("student-performance-chart")["series"][0]["values"]
    assert_equal [ 1, 2 ], chart_payload("student-exercises-chart")["series"][0]["values"]
    # a nova tentativa em Y (posterior) e a de X (posterior) não entram: só 2 tentativas oficiais em Alfa
  end

  test "evolution matches OfficialAttemptSeries and the existing indicators" do
    date_attempts
    sign_in(@student)
    get dashboard_url

    series = OfficialAttemptSeries.call(user: @student, school_classes: [ @class_a, @class_b ])
    assert_equal series.weeks.map(&:cumulative_attempts_count), chart_payload("student-exercises-chart")["series"][0]["values"]
    assert_equal series.weeks.map(&:cumulative_average), chart_payload("student-performance-chart")["series"][0]["values"]
    assert_select ".dashboard-metric--exercises dd", text: "3 / 4"
    assert_select ".dashboard-metric--average dd", text: "66.7%"
  end

  test "student without official attempts sees a friendly message and no chart canvas" do
    newcomer = create_student("sdnew")
    @class_a.class_students.create!(student: newcomer, active: true)
    sign_in(newcomer)
    get dashboard_url

    assert_select ".dashboard-evolution .time-series-chart-empty-message[role='status']", count: 2
    assert_select ".dashboard-evolution .time-series-chart-empty-message", text: /Você ainda não tem tentativas oficiais/
    assert_select ".time-series-chart-canvas", count: 0
    assert_select ".dashboard-metric--exercises dd", text: "0 / 3"
  end

  test "evolution never includes another student's attempts" do
    date_attempts
    sign_in(@other_student)
    get dashboard_url

    assert_equal [ 0.0 ], chart_payload("student-performance-chart")["series"][0]["values"]
    assert_equal [ 1 ], chart_payload("student-exercises-chart")["series"][0]["values"]
    assert_not_includes response.body, @student.name
  end

  test "viewing the dashboard with charts writes nothing" do
    sign_in(@student)

    assert_no_difference -> { ExerciseAttempt.count + StudentStat.count } do
      get dashboard_url
    end
  end

  test "teacher sees no student dashboard and unauthenticated users go to login" do
    sign_in_teacher
    get dashboard_url
    assert_select "#student-performance-chart, #student-exercises-chart", count: 0
    assert_response :success
    assert_select ".dashboard-student-lesson", count: 0
    assert_select "select#student_id", count: 1
    assert_select ".dashboard-gamification", count: 0

    delete logout_url
    get dashboard_url
    assert_redirected_to login_path
  end

  test "service rejects classes without active enrollment" do
    outsider = create_student("sdoutsider")

    assert_raises(ArgumentError) { StudentDashboard.call(student: outsider, school_classes: [ @class_a ]) }
  end

  private

  def chart_payload(id)
    JSON.parse(css_select("figure##{id}").first["data-time-series-chart-chart-value"])
  end

  # Fixa datas semanais: Alfa/X em 05/01, Alfa/Y em 12/01 (oficial, nota 0), Beta/W em 26/01.
  # Tentativas posteriores (Y certa e X do outro aluno) ficam depois e não são oficiais.
  def date_attempts
    stamp = lambda do |link, student, time, first: true|
      scope = ExerciseAttempt.where(activity_exercise: link, student:).order(:id)
      (first ? scope.first : scope.last).update_columns(created_at: time)
    end
    stamp.call(@a1_x, @student, Time.utc(2026, 1, 5, 12))
    stamp.call(@a1_y, @student, Time.utc(2026, 1, 12, 12))
    stamp.call(@a1_y, @student, Time.utc(2026, 1, 13, 12), first: false)
    stamp.call(@b_w, @student, Time.utc(2026, 1, 26, 12))
    stamp.call(@a1_x, @other_student, Time.utc(2026, 1, 6, 12))
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

  def sign_in(student)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
  end

  def sign_in_teacher
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
  end
end
