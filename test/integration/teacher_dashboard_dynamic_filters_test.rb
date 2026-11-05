require "test_helper"

class TeacherDashboardDynamicFiltersTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = create_teacher("dynprof")
    @class_one = @teacher.school_classes.create!(name: "Alpha", active: true)
    @class_two = @teacher.school_classes.create!(name: "Beta", active: true)
    @student = create_student("dynstud")
    @class_one.class_students.create!(student: @student, active: true)
    @lesson_one = @class_one.activities.create!(title: "Aula Um", published: true)
    @draft_one = @class_one.activities.create!(title: "Aula Rascunho", published: false)
    @lesson_two = @class_two.activities.create!(title: "Aula Dois", published: true)
    @shared = @teacher.exercises.create!(title: "Compartilhado", exercise_type: :quiz, object: quiz_object)
    @shared_one = @lesson_one.activity_exercises.create!(exercise: @shared, position: 1, points: 10)
    @shared_draft = @draft_one.activity_exercises.create!(exercise: @shared, position: 1, points: 10)
    @only_two = @lesson_two.activity_exercises.create!(exercise: @teacher.exercises.create!(title: "Só Beta", exercise_type: :quiz, object: quiz_object), position: 1, points: 10)

    @foreign_teacher = create_teacher("dynother")
    foreign_class = @foreign_teacher.school_classes.create!(name: "Alheia", active: true)
    foreign_lesson = foreign_class.activities.create!(title: "Aula Alheia", published: true)
    foreign_lesson.activity_exercises.create!(exercise: @foreign_teacher.exercises.create!(title: "Quiz Alheio", exercise_type: :quiz, object: quiz_object), position: 1, points: 10)

    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
  end

  test "the page embeds authorized options per class for the Stimulus controller" do
    get dashboard_url(school_class_id: @class_one.id)

    assert_response :success
    form = css_select("form[data-controller='dashboard-filter']").first
    options = JSON.parse(form["data-dashboard-filter-options-value"])

    assert_equal [ @class_one.id.to_s, @class_two.id.to_s ].sort, options.keys.sort
    assert_equal [ "Aula Um", "Aula Rascunho (rascunho)" ], options[@class_one.id.to_s]["activities"].map { |a| a["label"] }
    assert_equal [ "Aula Dois" ], options[@class_two.id.to_s]["activities"].map { |a| a["label"] }
    assert_equal [ "Compartilhado — Aula Um", "Compartilhado — Aula Rascunho" ], options[@class_one.id.to_s]["exercises"].map { |e| e["label"] }
    assert_equal [ @lesson_one.id, @draft_one.id ], options[@class_one.id.to_s]["exercises"].map { |e| e["activityId"] }
    assert_equal [ "Só Beta — Aula Dois" ], options[@class_two.id.to_s]["exercises"].map { |e| e["label"] }
  end

  test "no option or payload exposes another teacher's data" do
    get dashboard_url(school_class_id: @class_one.id)

    assert_not_includes response.body, "Alheia"
    assert_not_includes response.body, "Quiz Alheio"
  end

  test "the form wires class and lesson changes to the dependent selects without submitting" do
    get dashboard_url(school_class_id: @class_one.id)

    assert_select "select#school_class_id[data-dashboard-filter-target='schoolClass'][data-action='change->dashboard-filter#resetActivity']"
    assert_select "select#activity_id[data-action='change->dashboard-filter#resetExercise']"
    assert_select "select#activity_exercise_id[data-dashboard-filter-target='exercise']"
    assert_select "select[onchange]", count: 0
  end

  test "without JavaScript the rendered options follow the submitted class and lesson, and stale selections are rejected" do
    get dashboard_url(school_class_id: @class_two.id)
    assert_select "select#activity_id option", count: 2
    assert_select "select#activity_exercise_id option", count: 2
    assert_select "select#activity_exercise_id option", text: "Só Beta — Aula Dois"

    get dashboard_url(school_class_id: @class_one.id, activity_id: @draft_one.id)
    assert_select "select#activity_exercise_id option", count: 2
    assert_select "select#activity_exercise_id option", text: "Compartilhado — Aula Rascunho"

    get dashboard_url(school_class_id: @class_two.id, activity_id: @lesson_one.id)
    assert_redirected_to root_path
    assert_equal "Aula inválida.", flash[:alert]

    get dashboard_url(school_class_id: @class_two.id, activity_exercise_id: @shared_one.id)
    assert_redirected_to root_path
    assert_equal "Exercício inválido.", flash[:alert]
  end

  test "results only change when the form is submitted with the new selection" do
    get dashboard_url(school_class_id: @class_one.id)
    assert_select ".dashboard-metric--activities dd", text: "2"

    get dashboard_url(school_class_id: @class_one.id, activity_id: @lesson_one.id)
    assert_select ".dashboard-metric--activities dd", text: "1"
  end

  test "the page loads the filter data with a fixed number of queries" do
    counts = [ 1, 4 ].map do |extra_classes|
      extra_classes.times { |i| @teacher.school_classes.create!(name: "Extra #{extra_classes}-#{i}", active: true).activities.create!(title: "A", published: true) }
      count = 0
      callback = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get dashboard_url(school_class_id: @class_one.id) }
      count
    end

    assert_operator counts.last, :<=, counts.first + 1
  end

  private

  def quiz_object
    { "questions" => [ { "question_type" => "short_answer", "statement" => "Responda 42.", "correct_answer" => "42" } ] }
  end

  def create_teacher(prefix)
    username = "#{prefix}_#{SecureRandom.hex(5)}"
    Teacher.create!(name: prefix, username:, email: "#{username}@example.test", password: "secret123")
  end

  def create_student(prefix)
    username = "#{prefix}_#{SecureRandom.hex(5)}"
    Student.create!(name: prefix, username:, email: "#{username}@example.test", password: "secret123")
  end
end
