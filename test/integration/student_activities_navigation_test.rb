require "test_helper"

class StudentActivitiesNavigationTest < ActionDispatch::IntegrationTest
  test "student is redirected from activities index to their classes" do
    _teacher, school_class, _activity, student, = create_published_activity
    sign_in_as_student(student)

    get activities_url

    assert_redirected_to school_classes_url
    follow_redirect!
    assert_response :success
    assert_select "h1", text: "Turmas"
    assert_includes response.body, school_class.name
    assert_select "a", text: "Nova aula", count: 0
  end

  test "student can open a published activity and sees exercises without teacher controls" do
    _teacher, school_class, activity, student, exercise = create_published_activity
    sign_in_as_student(student)

    get activity_url(activity)

    assert_response :success
    assert_select "h1", text: activity.title
    assert_select "table.exercise-table"
    assert_select "a", text: exercise.title
    assert_select "p a[href='#{school_class_path(school_class)}']", text: school_class.name, count: 1
    assert_select "form[action='#{activity_exercises_path}']", count: 0
    assert_select "tr[draggable='true']", count: 0
    assert_select "button", text: "Remover", count: 0
    assert_select "a", text: "Editar", count: 0
  end

  test "student without an active class membership cannot access activity or exercise links" do
    _teacher, _school_class, activity, _student, exercise = create_published_activity
    outsider = Student.create!(
      name: "Aluno externo",
      username: "activity-outsider-#{SecureRandom.hex(6)}",
      email: "activity-outsider-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    activity_exercise = activity.activity_exercises.active.find_by!(exercise:)
    sign_in_as_student(outsider)

    get activity_url(activity)
    assert_redirected_to root_url
    assert_not_includes response.body, "Voltar à aula"

    get exercise_url(exercise, activity_exercise_id: activity_exercise.id)
    assert_redirected_to root_url
    assert_not_includes response.body, "Voltar à aula"
  end

  test "student sees published activities inside a class without exercises or controls" do
    _teacher, school_class, activity, student, = create_published_activity
    sign_in_as_student(student)

    get school_class_url(school_class)

    assert_response :success
    assert_select "h3 a[href='#{activity_path(activity)}']", text: activity.title
    assert_select "table.exercise-table", count: 0
    assert_select "table[data-controller='sortable-exercises']", count: 0
    assert_select "tr[draggable='true']", count: 0
  end

  test "teacher still sees the activities management page" do
    teacher, = create_published_activity
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }

    get activities_url

    assert_response :success
    assert_select "a", text: "Nova aula"
    assert_select "a", text: "Editar"
    assert_select "button", text: "Desativar"
  end

  private

  def create_published_activity
    teacher_id = "activityteacher-#{SecureRandom.hex(6)}"
    teacher = Teacher.create!(name: "Professora", username: teacher_id, email: "#{teacher_id}@example.com", password: "secret123")
    school_class = teacher.school_classes.create!(name: "Ciências", active: true)
    activity = school_class.activities.create!(title: "Aula publicada", published: true)
    student_id = "activitystudent-#{SecureRandom.hex(6)}"
    student = Student.create!(name: "Aluno", username: student_id, email: "#{student_id}@example.com", password: "secret123")
    school_class.class_students.create!(student:, active: true)
    exercise = teacher.exercises.create!(title: "Exercício de ciências", exercise_type: :quiz, object: {
      "questions" => [ { "question_type" => "short_answer", "statement" => "Cite uma ciência.", "correct_answer" => "Física" } ]
    })
    activity.activity_exercises.create!(exercise:, position: 1, points: 5)
    [ teacher, school_class, activity, student, exercise ]
  end

  def sign_in_as_student(student)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
  end
end
