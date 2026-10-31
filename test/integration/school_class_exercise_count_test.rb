require "test_helper"

class SchoolClassExerciseCountTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "cnt-teacher")
    @school_class = @teacher.school_classes.create!(name: "Turma contagem", active: true)
    @empty = @school_class.activities.create!(title: "Aula vazia", published: true)
    @single = @school_class.activities.create!(title: "Aula com um", published: true)
    @multi = @school_class.activities.create!(title: "Aula com vários", published: true)
    @draft = @school_class.activities.create!(title: "Aula rascunho", published: false)
    @single.activity_exercises.create!(exercise: new_exercise("Único"), position: 1, points: 1)
    3.times { |i| @multi.activity_exercises.create!(exercise: new_exercise("Vários #{i}"), position: i + 1, points: 1) }
    @multi.activity_exercises.create!(exercise: new_exercise("Vínculo inativo"), position: 4, points: 1, active: false)
    @multi.activity_exercises.create!(exercise: new_exercise("Exercício inativo", active: false), position: 5, points: 1)
    2.times { |i| @draft.activity_exercises.create!(exercise: new_exercise("Rascunho #{i}"), position: i + 1, points: 1) }
    @student = create_user(Student, "cnt-student")
    @school_class.class_students.create!(student: @student, active: true)
  end

  test "teacher sees counts for published and draft activities" do
    login(@teacher)

    get school_class_url(@school_class)

    assert_response :success
    assert_counts("Aula vazia" => "0 exercícios", "Aula com um" => "1 exercício", "Aula com vários" => "3 exercícios", "Aula rascunho" => "2 exercícios")
    assert_select "p", text: "Rascunho", count: 1
    assert_no_management_controls
  end

  test "student sees counts only for published activities" do
    login(@student)

    get school_class_url(@school_class)

    assert_response :success
    assert_counts("Aula vazia" => "0 exercícios", "Aula com um" => "1 exercício", "Aula com vários" => "3 exercícios")
    assert_select "h3 a", text: "Aula rascunho", count: 0
    assert_not_includes response.body, "2 exercícios"
    assert_no_management_controls
  end

  test "number of queries does not grow with the number of activities" do
    login(@teacher)
    get school_class_url(@school_class)
    baseline = count_queries { get school_class_url(@school_class) }

    5.times do |i|
      activity = @school_class.activities.create!(title: "Extra #{i}", published: true)
      activity.activity_exercises.create!(exercise: new_exercise("Extra #{i}"), position: 1, points: 1)
    end

    assert_equal baseline, count_queries { get school_class_url(@school_class) }
  end

  test "authorization rules still apply" do
    outsider = create_user(Student, "cnt-outsider")
    login(outsider)
    get school_class_url(@school_class)
    assert_redirected_to root_url
    delete logout_url

    login(create_user(Teacher, "cnt-other"))
    get school_class_url(@school_class)
    assert_redirected_to root_url
    delete logout_url

    @school_class.update!(active: false)
    login(@teacher)
    get school_class_url(@school_class)
    assert_response :not_found
  end

  private

  def assert_counts(expected)
    expected.each do |title, text|
      assert_select "h3 a", text: title, count: 1
      assert_select "h3:has(a)", text: title
      heading = css_select("h3").find { |h| h.text.strip == title }
      assert_equal text, heading.next_element.text.strip, "contagem de #{title}"
    end
  end

  def assert_no_management_controls
    assert_select "table", count: 0
    assert_select "form[action='#{activity_exercises_path}']", count: 0
    assert_select "tr[draggable='true']", count: 0
  end

  def count_queries
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  def new_exercise(title, active: true)
    @teacher.exercises.create!(title:, exercise_type: :quiz, active:, object: {
      "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ]
    })
  end

  def create_user(klass, prefix)
    id = "#{prefix}-#{SecureRandom.hex(6)}"
    klass.create!(name: id, username: id, email: "#{id}@example.com", password: "secret123")
  end

  def login(user)
    role = user.is_a?(Teacher) ? "teacher" : "student"
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end
end
