require "test_helper"

class RegistrationAndEnrollmentTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  def errors_list
    css_select(".errors li").map(&:text)
  end

  # Cadastro

  %w[teacher student].each do |role|
    test "#{role} invalid registration keeps non sensitive fields, empties passwords and uses the shared partial" do
      assert_no_difference -> { role.capitalize.constantize.count } do
        post register_url(role), params: { registration: { name: "Julia Silva", username: "julia_#{role}", email: "  Julia@Gmail.com ",
                                                          password: "SenhaSecreta1", password_confirmation: "Outra1234" } }
      end
      assert_response :unprocessable_entity
      assert_select "input[name='registration[name]'][value='Julia Silva']"
      assert_select "input[name='registration[username]'][value='julia_#{role}']"
      assert_select "input[name='registration[email]'][value='julia@gmail.com']"
      assert_select "input[name='registration[password]'][value]", 0
      assert_select "input[name='registration[password_confirmation]'][value]", 0
      assert_no_match(/SenhaSecreta1|Outra1234/, response.body)
      assert_select "div.errors h2", "1 erro impediu o salvamento:"
      assert_equal [ "Confirmação da senha não é igual a Senha" ], errors_list
      assert_select "form[action='#{register_path(role)}'][method='post']"
    end

    test "#{role} registration form renders empty and a valid registration still works" do
      get register_url(role)
      assert_response :success
      assert_select "div.errors", 0
      assert_difference -> { role.capitalize.constantize.count } => 1 do
        post register_url(role), params: { registration: { name: "Ok", username: "ok_#{role}", email: "ok_#{role}@example.com",
                                                          password: "secret123", password_confirmation: "secret123" } }
      end
      assert_redirected_to root_url
    end
  end

  # Matrícula por código

  setup do
    @teacher = Teacher.create!(name: "Prof", username: "prof_en", email: "prof_en@example.com", password: "secret123")
    @student = Student.create!(name: "Aluno", username: "aluno_en", email: "aluno_en@example.com", password: "secret123")
    @school_class = SchoolClass.create!(teacher: @teacher, name: "Turma EN", access_code: "ABC12345")
  end

  def login_as(role, user)
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end

  def join(code)
    post join_school_classes_url, params: { access_code: code }
  end

  def memberships
    ClassStudent.where(student: @student, school_class: @school_class)
  end

  test "original, lowercase and padded codes enroll the student" do
    [ "ABC12345", "abc12345", "  abc12345  " ].each do |code|
      memberships.delete_all
      login_as("student", @student)
      assert_difference -> { memberships.count } => 1 do
        join(code)
      end
      assert_redirected_to school_classes_url
      assert_equal "Você entrou na turma.", flash[:notice]
    end
    assert_equal "ABC12345", @school_class.reload.access_code
  end

  [ "", "   " ].each do |code|
    test "blank code #{code.inspect} asks for the code" do
      login_as("student", @student)
      assert_no_difference -> { ClassStudent.count } do
        join(code)
      end
      assert_redirected_to school_classes_url
      assert_equal "Informe o código da turma.", flash[:alert]
    end
  end

  test "unknown code is invalid" do
    login_as("student", @student)
    assert_no_difference -> { ClassStudent.count } do
      join("ZZZZ9999")
    end
    assert_redirected_to school_classes_url
    assert_equal "Código de turma inválido.", flash[:alert]
  end

  test "inactive class code is invalid" do
    @school_class.update!(active: false)
    login_as("student", @student)
    assert_no_difference -> { ClassStudent.count } do
      join("abc12345")
    end
    assert_equal "Código de turma inválido.", flash[:alert]
  end

  test "active enrollment is not duplicated" do
    ClassStudent.create!(student: @student, school_class: @school_class)
    login_as("student", @student)
    assert_no_difference -> { ClassStudent.count } do
      join("abc12345")
    end
    assert_redirected_to school_classes_url
    assert_equal "Você já está nesta turma.", flash[:notice]
    assert memberships.first.active?
  end

  test "inactive enrollment is reactivated" do
    membership = ClassStudent.create!(student: @student, school_class: @school_class, active: false)
    login_as("student", @student)
    assert_no_difference -> { ClassStudent.count } do
      join(" ABC12345")
    end
    assert_equal "Você entrou na turma.", flash[:notice]
    assert membership.reload.active?
  end

  test "teacher cannot use the student enrollment flow" do
    login_as("teacher", @teacher)
    assert_no_difference -> { ClassStudent.count } do
      join("ABC12345")
    end
    assert_redirected_to root_url
  end
end
