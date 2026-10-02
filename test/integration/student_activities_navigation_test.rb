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
    _teacher, _school_class, activity, student, exercise = create_published_activity
    sign_in_as_student(student)

    get activity_url(activity)

    assert_response :success
    assert_select "h1", text: activity.title
    assert_select "table.exercise-table"
    assert_select "a", text: exercise.title
    assert_select "form[action='#{activity_exercises_path}']", count: 0
    assert_select "tr[draggable='true']", count: 0
    assert_select "button", text: "Remover", count: 0
    assert_select "a", text: "Editar", count: 0
  end

  test "student sees published activities inside a class without reorder controls" do
    _teacher, school_class, activity, student, = create_published_activity
    sign_in_as_student(student)

    get school_class_url(school_class)

    assert_response :success
    assert_select "h3 a", text: activity.title
    assert_select "table.exercise-table"
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
    teacher = Teacher.create!(name: "Professora", username: "activityteacher", email: "activityteacher@example.com", password: "secret123")
    school_class = teacher.school_classes.create!(name: "Ciências", active: true)
    activity = school_class.activities.create!(title: "Aula publicada", published: true)
    student = Student.create!(name: "Aluno", username: "activitystudent", email: "activitystudent@example.com", password: "secret123")
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
