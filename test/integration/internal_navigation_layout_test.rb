require "test_helper"

class InternalNavigationLayoutTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = create_teacher
    @school_class = @teacher.school_classes.create!(name: "Turma da navegação")
    @student = create_student
    @school_class.class_students.create!(student: @student, active: true)
  end

  test "teacher sidebar exposes the full navigation and marks the active section" do
    sign_in(@teacher, "teacher")

    get school_classes_url

    assert_response :success
    assert_select ".internal-app-shell[data-controller='sidebar-navigation']"
    assert_select ".internal-navigation-link[href='#{school_classes_path}'][aria-current='page']", text: "Turmas"
    assert_select ".internal-navigation-link[href='#{activities_path}']", text: "Aulas"
    assert_select ".internal-navigation-link[href='#{exercises_path}']", text: "Exercícios"
    assert_select ".internal-navigation-link[href='#{exercise_attempts_path}']", text: "Resultados"
    assert_select ".internal-logout-button", text: "Sair"
    assert_select ".internal-menu-toggle[aria-controls='internal-sidebar'][aria-expanded='false']"

    get activities_url
    assert_select ".internal-navigation-link[href='#{activities_path}'][aria-current='page']", text: "Aulas"

    get exercises_url
    assert_select ".internal-navigation-link[href='#{exercises_path}'][aria-current='page']", text: "Exercícios"

    get exercise_attempts_url
    assert_select ".internal-navigation-link[href='#{exercise_attempts_path}'][aria-current='page']", text: "Resultados"
  end

  test "student sidebar exposes only classes and personal results" do
    sign_in(@student, "student")

    get school_classes_url

    assert_response :success
    assert_select ".internal-navigation-link[href='#{school_classes_path}'][aria-current='page']", text: "Minhas turmas"
    assert_select ".internal-navigation-link[href='#{exercise_attempts_path}']", text: "Meus resultados"
    assert_select ".internal-navigation-link[href='#{activities_path}']", count: 0
    assert_select ".internal-navigation-link[href='#{exercises_path}']", count: 0

    get exercise_attempts_url
    assert_select ".internal-navigation-link[href='#{exercise_attempts_path}'][aria-current='page']", text: "Meus resultados"
  end

  test "public authentication pages keep their existing layout without the sidebar" do
    get login_url(role: "student")

    assert_response :success
    assert_select ".login-page"
    assert_select ".internal-app-shell", count: 0

    get register_url("student")
    assert_response :success
    assert_select ".internal-app-shell", count: 0
  end

  test "logout clears the session and protected pages require authentication" do
    sign_in(@teacher, "teacher")
    delete logout_url

    assert_redirected_to login_url
    get school_classes_url
    assert_redirected_to login_url
  end

  private

  def sign_in(user, role)
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end

  def create_teacher
    identifier = "sidebar-teacher-#{SecureRandom.hex(6)}"
    Teacher.create!(name: "Professor", username: identifier, email: "#{identifier}@example.com", password: "secret123")
  end

  def create_student
    identifier = "sidebar-student-#{SecureRandom.hex(6)}"
    Student.create!(name: "Aluno", username: identifier, email: "#{identifier}@example.com", password: "secret123")
  end
end
