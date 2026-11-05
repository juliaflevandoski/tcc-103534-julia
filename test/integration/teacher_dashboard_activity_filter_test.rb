require "test_helper"

class TeacherDashboardActivityFilterTest < ActionDispatch::IntegrationTest
  RIGHT = { "0" => "a", "1" => "42" }.freeze
  WRONG = { "0" => "b", "1" => "0" }.freeze

  setup do
    @teacher = create_teacher("filtprof")
    @school_class = @teacher.school_classes.create!(name: "Turma Filtro", active: true)
    @student_one = create_student("filtone")
    @student_two = create_student("filttwo")
    [ @student_one, @student_two ].each { |student| @school_class.class_students.create!(student:, active: true) }
    @lesson_a = @school_class.activities.create!(title: "Aula A", published: true)
    @lesson_b = @school_class.activities.create!(title: "Aula B", published: true)
    @draft = @school_class.activities.create!(title: "Aula Rascunho", published: false)
    @link_a = link(@lesson_a, "Quiz A")
    @link_b1 = link(@lesson_b, "Quiz B1")
    @link_b2 = link(@lesson_b, "Quiz B2")
    [ @student_one, @student_two ].each { |student| submit(@link_a, student, RIGHT) }
    submit(@link_b1, @student_one, WRONG)
    sign_in(@teacher)
  end

  test "all lessons keeps the unfiltered indicators and selects the default option" do
    get dashboard_url(school_class_id: @school_class.id)

    assert_response :success
    assert_select "select#activity_id option", count: 4
    assert_select "select#activity_id option[selected]", count: 0
    assert_select "select#activity_id option", text: "Aula Rascunho (rascunho)"
    assert_select ".dashboard-filter-note", count: 0
    assert_select ".dashboard-metric--activities dd", text: "3"
    assert_select ".dashboard-metric--exercises dd", text: "3"
    assert_select ".dashboard-lesson", count: 3
    expected = ResultsDashboard.call(user: @teacher, school_class: @school_class)
    assert_select ".dashboard-metric--average dd", text: ActionController::Base.helpers.number_to_percentage(expected[:class_average], precision: 1)
  end

  test "a valid lesson filters indicators, completion and rankings" do
    get dashboard_url(school_class_id: @school_class.id, activity_id: @lesson_b.id)

    assert_response :success
    assert_select "select#activity_id option[selected][value='#{@lesson_b.id}']", count: 1
    assert_select ".dashboard-filter-note", text: /Aula B/
    assert_select ".dashboard-metric--students dd", text: "2"
    assert_select ".dashboard-metric--activities dd", text: "1"
    assert_select ".dashboard-metric--exercises dd", text: "2"
    assert_select ".dashboard-metric--average dd", text: "0.0%"
    assert_select ".dashboard-metric--completion dd", text: "25.0%"
    assert_select ".dashboard-metric--completion .dashboard-metric-note", text: "1 / 4 resultados aluno-exercício"
    assert_equal [ "Aula B" ], css_select(".dashboard-lesson-title").map { |node| node.text.squish }
    assert_equal [ "Quiz B1" ], css_select("#dashboard-best-title ~ ol .dashboard-ranking-title").map { |node| node.text.squish }
    assert_select ".dashboard-lesson, .dashboard-ranking, select#activity_exercise_id option", text: /Quiz A/, count: 0
  end

  test "a lesson without exercises shows zeros and dashes" do
    empty = @school_class.activities.create!(title: "Aula Vazia", published: true)

    get dashboard_url(school_class_id: @school_class.id, activity_id: empty.id)

    assert_response :success
    assert_select ".dashboard-metric--exercises dd", text: "0"
    assert_select ".dashboard-metric--average dd", text: "—"
    assert_select ".dashboard-metric--completion dd", text: "—"
    assert_select ".dashboard-ranking .dashboard-empty", count: 2
  end

  test "a draft lesson stays identified and has no completion bar" do
    get dashboard_url(school_class_id: @school_class.id, activity_id: @draft.id)

    assert_response :success
    assert_select ".dashboard-filter-note", text: /Aula Rascunho \(rascunho\)/
    assert_select ".dashboard-lesson-draft", text: "Rascunho", count: 1
    assert_select ".dashboard-lesson-percentage", text: "—"
    assert_select ".dashboard-lesson progress", count: 0
    assert_select ".dashboard-metric--students dd", text: "2"
  end

  test "lessons from another class or teacher and invalid ids are rejected" do
    other_class = @teacher.school_classes.create!(name: "Outra Turma", active: true)
    own_other_lesson = other_class.activities.create!(title: "Aula da outra turma", published: true)
    foreign_teacher = create_teacher("filtother")
    foreign_class = foreign_teacher.school_classes.create!(name: "Turma Alheia", active: true)
    foreign_lesson = foreign_class.activities.create!(title: "Aula Alheia", published: true)
    inactive = @school_class.activities.create!(title: "Aula inativa", published: true, active: false)

    [ own_other_lesson.id, foreign_lesson.id, inactive.id, 0, "abc" ].each do |activity_id|
      get dashboard_url(school_class_id: @school_class.id, activity_id:)

      assert_redirected_to root_path
      assert_equal "Aula inválida.", flash[:alert]
    end
  end

  test "changing class lists only that class's lessons and keeps the class filter" do
    other_class = @teacher.school_classes.create!(name: "Zeta", active: true)
    other_class.activities.create!(title: "Aula Zeta", published: true)

    get dashboard_url(school_class_id: other_class.id)

    assert_response :success
    assert_select "select#school_class_id option[selected][value='#{other_class.id}']", count: 1
    assert_select "select#activity_id option", count: 2
    assert_select "select#activity_id option", text: "Aula Zeta"
    assert_select "select#activity_id option", text: /Aula A/, count: 0
    assert_select "[data-controller='dashboard-filter'] select#school_class_id[data-action='change->dashboard-filter#resetActivity']"
  end

  test "service rejects a lesson from another class" do
    other_class = @teacher.school_classes.create!(name: "Outra", active: true)
    foreign = other_class.activities.create!(title: "Fora", published: true)

    assert_raises(ArgumentError) { TeacherDashboard.call(teacher: @teacher, school_class: @school_class, activity: foreign) }
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
