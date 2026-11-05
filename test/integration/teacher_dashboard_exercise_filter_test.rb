require "test_helper"

class TeacherDashboardExerciseFilterTest < ActionDispatch::IntegrationTest
  RIGHT = { "0" => "a", "1" => "42" }.freeze
  WRONG = { "0" => "b", "1" => "0" }.freeze

  setup do
    @teacher = create_teacher("exfprof")
    @school_class = @teacher.school_classes.create!(name: "Turma Exercicio", active: true)
    @student_one = create_student("exfone")
    @student_two = create_student("exftwo")
    [ @student_one, @student_two ].each { |student| @school_class.class_students.create!(student:, active: true) }
    @lesson_a = @school_class.activities.create!(title: "Aula A", published: true)
    @lesson_b = @school_class.activities.create!(title: "Aula B", published: true)
    @link_a = link(@lesson_a, "Quiz A")
    @link_b1 = link(@lesson_b, "Quiz B1")
    @link_b2 = link(@lesson_b, "Quiz B2")
    [ @student_one, @student_two ].each { |student| submit(@link_a, student, RIGHT) }
    submit(@link_b1, @student_one, WRONG)
    sign_in(@teacher)
  end

  test "all exercises keeps the unfiltered results and lists every active link" do
    get dashboard_url(school_class_id: @school_class.id)

    assert_response :success
    assert_select "select#activity_exercise_id option", count: 4
    assert_select "select#activity_exercise_id option[selected]", count: 0
    assert_select "select#activity_exercise_id option", text: "Todos os exercícios"
    assert_select ".dashboard-metric--exercises dd", text: "3"
    assert_select ".dashboard-lesson", count: 2
    assert_select ".dashboard-filter-note", count: 0
    expected = ResultsDashboard.call(user: @teacher, school_class: @school_class)
    assert_select ".dashboard-metric--average dd", text: ActionController::Base.helpers.number_to_percentage(expected[:class_average], precision: 1)
  end

  test "a valid link filters indicators, rankings and keeps whole-lesson completion" do
    get dashboard_url(school_class_id: @school_class.id, activity_exercise_id: @link_b1.id)

    assert_response :success
    assert_select "select#activity_exercise_id option[selected][value='#{@link_b1.id}']", count: 1
    assert_select ".dashboard-filter-note", text: /Quiz B1.*Aula B/
    assert_select ".dashboard-metric--students dd", text: "2"
    assert_select ".dashboard-metric--activities dd", text: "1"
    assert_select ".dashboard-metric--exercises dd", text: "1"
    assert_select ".dashboard-metric--exercises .dashboard-metric-note", text: "1 exercício distinto"
    assert_select ".dashboard-metric--average dd", text: "0.0%"
    assert_select ".dashboard-metric--completion dd", text: "50.0%"
    assert_select ".dashboard-metric--completion .dashboard-metric-note", text: "1 / 2 resultados aluno-exercício"
    assert_equal [ "Aula B" ], css_select(".dashboard-lesson-title").map { |node| node.text.squish }
    assert_select ".dashboard-lesson-count", text: "0 de 2 alunos concluíram"
    assert_equal [ "Quiz B1" ], css_select("#dashboard-best-title ~ ol .dashboard-ranking-title").map { |node| node.text.squish }
    assert_equal [ "Quiz B1" ], css_select("#dashboard-worst-title ~ ol .dashboard-ranking-title").map { |node| node.text.squish }
  end

  test "a link without official attempts shows dashes and no bars or rankings" do
    get dashboard_url(school_class_id: @school_class.id, activity_exercise_id: @link_b2.id)

    assert_response :success
    assert_select ".dashboard-metric--average dd", text: "—"
    assert_select ".dashboard-metric--average progress", count: 0
    assert_select ".dashboard-metric--completion dd", text: "0.0%"
    assert_select ".dashboard-ranking .dashboard-empty", count: 2
  end

  test "combined with a lesson the link must belong to that lesson" do
    get dashboard_url(school_class_id: @school_class.id, activity_id: @lesson_b.id)

    assert_select "select#activity_exercise_id option", count: 3
    assert_select "select#activity_exercise_id option", text: /Quiz A/, count: 0

    get dashboard_url(school_class_id: @school_class.id, activity_id: @lesson_b.id, activity_exercise_id: @link_b1.id)
    assert_response :success
    assert_select ".dashboard-metric--exercises dd", text: "1"

    get dashboard_url(school_class_id: @school_class.id, activity_id: @lesson_b.id, activity_exercise_id: @link_a.id)
    assert_redirected_to root_path
    assert_equal "Exercício inválido.", flash[:alert]
  end

  test "the same exercise in two lessons gives distinct, separated options" do
    shared = @teacher.exercises.create!(title: "Quiz Compartilhado", exercise_type: :quiz, object: quiz_object)
    shared_a = @lesson_a.activity_exercises.create!(exercise: shared, position: 5, points: 10)
    shared_b = @lesson_b.activity_exercises.create!(exercise: shared, position: 5, points: 10)
    submit(shared_a, @student_one, RIGHT)

    get dashboard_url(school_class_id: @school_class.id)
    assert_select "select#activity_exercise_id option", text: "Quiz Compartilhado — Aula A"
    assert_select "select#activity_exercise_id option", text: "Quiz Compartilhado — Aula B"

    get dashboard_url(school_class_id: @school_class.id, activity_exercise_id: shared_a.id)
    assert_select ".dashboard-metric--completion .dashboard-metric-note", text: "1 / 2 resultados aluno-exercício"
    assert_select ".dashboard-metric--average dd", text: "100.0%"

    get dashboard_url(school_class_id: @school_class.id, activity_exercise_id: shared_b.id)
    assert_select ".dashboard-metric--completion .dashboard-metric-note", text: "0 / 2 resultados aluno-exercício"
    assert_select ".dashboard-metric--average dd", text: "—"
  end

  test "links from another class, another teacher, inactive links, inactive exercises and bad ids are rejected" do
    other_class = @teacher.school_classes.create!(name: "Outra Turma", active: true)
    own_other = link(other_class.activities.create!(title: "Aula Outra", published: true), "Quiz Outra")
    foreign_teacher = create_teacher("exfother")
    foreign_class = foreign_teacher.school_classes.create!(name: "Turma Alheia", active: true)
    foreign = link(foreign_class.activities.create!(title: "Aula Alheia", published: true), "Quiz Alheio")
    inactive_link = link(@lesson_a, "Quiz Vinculo Inativo")
    inactive_link.update!(active: false)
    inactive_exercise = link(@lesson_a, "Quiz Inativo")
    inactive_exercise.exercise.update!(active: false)
    inactive_lesson = @school_class.activities.create!(title: "Aula inativa", published: true, active: false)
    in_inactive_lesson = link(inactive_lesson, "Quiz em aula inativa")

    [ own_other.id, foreign.id, inactive_link.id, inactive_exercise.id, in_inactive_lesson.id, 0, "abc", 999_999 ].each do |id|
      get dashboard_url(school_class_id: @school_class.id, activity_exercise_id: id)

      assert_redirected_to root_path
      assert_equal "Exercício inválido.", flash[:alert]
    end
  end

  test "changing class lists only that class's links and wires the reset actions" do
    other_class = @teacher.school_classes.create!(name: "Zeta", active: true)
    link(other_class.activities.create!(title: "Aula Zeta", published: true), "Quiz Zeta")

    get dashboard_url(school_class_id: other_class.id)

    assert_select "select#activity_exercise_id option", count: 2
    assert_select "select#activity_exercise_id option", text: "Quiz Zeta — Aula Zeta"
    assert_select "select#activity_exercise_id option", text: /Quiz A/, count: 0
    assert_select ".dashboard-lesson, .dashboard-ranking", text: /Quiz A/, count: 0
    assert_select "select#activity_id[data-action='change->dashboard-filter#resetExercise']"
    assert_select "select#activity_exercise_id[data-dashboard-filter-target='exercise']"
  end

  test "a class with no links shows only the default option" do
    empty_class = @teacher.school_classes.create!(name: "Vazia", active: true)

    get dashboard_url(school_class_id: empty_class.id)

    assert_response :success
    assert_select "select#activity_exercise_id option", count: 1
  end

  test "service rejects links from another class or another lesson" do
    other_class = @teacher.school_classes.create!(name: "Outra", active: true)
    foreign = link(other_class.activities.create!(title: "Fora", published: true), "Quiz Fora")

    assert_raises(ArgumentError) { TeacherDashboard.call(teacher: @teacher, school_class: @school_class, activity_exercise: foreign) }
    assert_raises(ArgumentError) { TeacherDashboard.call(teacher: @teacher, school_class: @school_class, activity: @lesson_a, activity_exercise: @link_b1) }
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

  def create_student(prefix)
    username = "#{prefix}_#{SecureRandom.hex(5)}"
    Student.create!(name: prefix, username:, email: "#{username}@example.test", password: "secret123")
  end

  def sign_in(user)
    post login_url, params: { role: "teacher", username: user.username, password: "secret123" }
  end
end
