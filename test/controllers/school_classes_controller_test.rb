require "test_helper"

class SchoolClassesControllerTest < ActionDispatch::IntegrationTest
  test "lists active classes" do
    sign_in_as_teacher
    get school_classes_url

    assert_response :success
    assert_select "h1", "Turmas"
  end

  test "teacher sees only their classes with management actions" do
    teacher = Teacher.create!(name: "Ana", username: "ana_cards", email: "ana_cards@example.com", password: "secret123")
    own_class = teacher.school_classes.create!(name: "Turma própria", access_code: "OWN12345")
    other_teacher = Teacher.create!(name: "Bia", username: "bia_cards", email: "bia_cards@example.com", password: "secret123")
    other_class = other_teacher.school_classes.create!(name: "Turma de outra pessoa", access_code: "OTH12345")
    sign_in_as_teacher(teacher)

    get school_classes_url

    assert_response :success
    assert_select ".school-class-card", 1
    assert_select ".school-class-card h2", text: own_class.name
    assert_select ".school-class-card code", text: own_class.access_code
    assert_select ".school-class-card a[href='#{school_class_path(own_class)}']", text: "Ver turma"
    assert_select ".school-class-card a[href='#{edit_school_class_path(own_class)}']", text: "Editar"
    assert_select ".school-class-card form[action='#{school_class_path(own_class)}'][data-turbo-confirm^='Desativar esta turma'] input[name='_method'][value='delete']"
    assert_no_match(other_class.name, response.body)
    assert_no_match(other_class.access_code, response.body)
  end

  test "student sees enrolled classes and can only view or leave" do
    teacher = Teacher.create!(name: "Professora", username: "prof_cards", email: "prof_cards@example.com", password: "secret123")
    enrolled_class = teacher.school_classes.create!(name: "Turma da aluna", access_code: "STU12345")
    other_class = teacher.school_classes.create!(name: "Turma sem matrícula", access_code: "OUT12345")
    student = Student.create!(name: "Aluna", username: "aluna_cards", email: "aluna_cards@example.com", password: "secret123")
    enrolled_class.class_students.create!(student: student, active: true)
    sign_in_as_student(student)

    get school_classes_url

    assert_response :success
    assert_select ".school-class-join-panel form[action='#{join_school_classes_path}'][method='post'] input[name='access_code']"
    assert_select ".school-class-card", 1
    assert_select ".school-class-card h2", text: enrolled_class.name
    assert_select ".school-class-card .school-class-teacher", text: "Professor: #{teacher.name}"
    assert_select ".school-class-card a[href='#{school_class_path(enrolled_class)}']", text: "Ver turma"
    assert_select ".school-class-card form[action='#{leave_school_class_path(enrolled_class)}'][data-turbo-confirm^='Sair desta turma'] input[name='_method'][value='delete']"
    assert_select ".school-class-card a[href^='#{edit_school_class_path(enrolled_class)}']", count: 0
    assert_select ".school-class-card form[action='#{school_class_path(enrolled_class)}']", count: 0
    assert_no_match(other_class.name, response.body)
    assert_no_match("STU12345", response.body)
  end

  test "empty class lists show a role-appropriate message" do
    sign_in_as_teacher
    get school_classes_url
    assert_select ".school-class-empty-state", "Você ainda não criou nenhuma turma."

    student = Student.create!(name: "Aluna", username: "aluna_empty", email: "aluna_empty@example.com", password: "secret123")
    sign_in_as_student(student)
    get school_classes_url
    assert_select ".school-class-empty-state", "Você ainda não está matriculado em nenhuma turma."
    assert_select ".school-class-join-panel"
  end

  test "creates a class and assigns an access code" do
    teacher = Teacher.create!(name: "Ana", username: "ana", email: "ana@example.com", password: "secret123")
    sign_in_as_teacher(teacher)

    assert_difference("SchoolClass.count") do
      post school_classes_url, params: { school_class: { name: "História" } }
    end

    assert_redirected_to school_class_url(SchoolClass.order(:id).last)
    assert SchoolClass.order(:id).last.access_code.present?
  end

  private

  def sign_in_as_teacher(teacher = Teacher.create!(name: "Bia", username: "bia", email: "bia@example.com", password: "secret123"))
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }
  end

  def sign_in_as_student(student)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
  end
end
