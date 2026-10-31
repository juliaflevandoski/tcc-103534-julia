require "test_helper"

class RegistrationRolesTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  def attrs(suffix)
    { name: "Nome #{suffix}", username: "user_#{suffix}", email: "#{suffix}@example.com",
      password: "secret123", password_confirmation: "secret123" }
  end

  test "GET registration form for valid roles" do
    get register_url("teacher")
    assert_response :success
    assert_select "h1", /professor/
    get register_url("student")
    assert_response :success
    assert_select "h1", /aluno/
  end

  test "GET with invalid role redirects to login" do
    [ "qualquercoisa", "admin", "Teacher" ].each do |role|
      get register_url(role)
      assert_redirected_to login_url
      assert_equal "Perfil inválido.", flash[:alert]
    end
  end

  test "valid POST creates teacher only" do
    assert_difference -> { Teacher.count } => 1, -> { Student.count } => 0 do
      post register_url("teacher"), params: { registration: attrs("t1") }
    end
    assert_redirected_to root_url
    assert_equal "Cadastro realizado com sucesso.", flash[:notice]
  end

  test "valid POST creates student only" do
    assert_difference -> { Student.count } => 1, -> { Teacher.count } => 0 do
      post register_url("student"), params: { registration: attrs("s1") }
    end
    assert_redirected_to root_url
  end

  test "POST with invalid role creates no account" do
    [ "qualquercoisa", "admin", "TEACHER", "%20" ].each do |role|
      assert_no_difference [ "Teacher.count", "Student.count" ] do
        post "/register/#{role}", params: { registration: attrs("x#{role.hash.abs}") }
      end
      assert_redirected_to login_url
      assert_equal "Perfil inválido.", flash[:alert]
    end
  end

  test "POST without role in the route creates no account" do
    assert_no_difference [ "Teacher.count", "Student.count" ] do
      post "/register", params: { role: "student", registration: attrs("norole") }
    end
    assert_response :not_found
  end

  test "extra role params cannot override the route role" do
    assert_difference -> { Student.count } => 1, -> { Teacher.count } => 0 do
      post register_url("student"), params: { role: "teacher", registration: attrs("m1").merge(role: "teacher", type: "Teacher") }
    end
    assert_difference -> { Teacher.count } => 1, -> { Student.count } => 0 do
      post register_url("teacher"), params: { role: "student", registration: attrs("m2").merge(role: "student") }
    end
  end

  test "validation error for valid role still renders form without creating" do
    assert_no_difference [ "Teacher.count", "Student.count" ] do
      post register_url("student"), params: { registration: attrs("e1").merge(name: "") }
    end
    assert_response :unprocessable_entity
  end
end
