require "test_helper"

class AccountCredentialsFlowTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  ROLES = { "teacher" => Teacher, "student" => Student }.freeze

  def register(role, **fields)
    params = { name: "Julia", username: "ju_#{SecureRandom.hex(4)}", email: "ju_#{SecureRandom.hex(4)}@example.com",
               password: "secret123", password_confirmation: "secret123" }.merge(fields)
    params.compact!
    post register_url(role), params: { registration: params }
  end

  ROLES.each do |role, klass|
    test "#{role} registration stores a normalized email and logs in" do
      assert_difference -> { klass.count }, 1 do
        register(role, email: "  Julia@Gmail.com ")
      end

      assert_redirected_to root_url
      assert_equal "julia@gmail.com", klass.order(:id).last.email
    end

    test "#{role} registration rejects a duplicate email with different case" do
      register(role, email: "dup@example.com")
      delete logout_url

      assert_no_difference -> { klass.count } do
        register(role, email: "DUP@Example.com")
      end

      assert_response :unprocessable_entity
      assert_includes response.body, "E-mail já está em uso"
    end

    {
      "short password" => [ { password: "1234567", password_confirmation: "1234567" }, "Senha deve ter pelo menos 8 caracteres" ],
      "blank password" => [ { password: "        ", password_confirmation: "        " }, "Senha não pode ficar em branco" ],
      "missing confirmation" => [ { password_confirmation: nil }, "Confirmação da senha não pode ficar em branco" ],
      "empty confirmation" => [ { password_confirmation: "" }, "Confirmação da senha não é igual a Senha" ],
      "different confirmation" => [ { password_confirmation: "outra1234" }, "Confirmação da senha não é igual a Senha" ],
      "invalid email" => [ { email: "abc" }, "E-mail não é válido" ]
    }.each do |label, (fields, message)|
      test "#{role} registration rejects #{label}" do
        assert_no_difference -> { klass.count } do
          register(role, **fields)
        end

        assert_response :unprocessable_entity
        assert_includes response.body, message
        assert_not_includes response.body, "secret123"
        assert_not_includes response.body, "Translation missing"
      end
    end

    test "#{role} registration rejects a password above 72 bytes in Portuguese" do
      assert_no_difference -> { klass.count } do
        register(role, password: "a" * 73, password_confirmation: "a" * 73)
      end

      assert_response :unprocessable_entity
      assert_includes response.body, "Senha é muito longa (máximo de 72 bytes)"
    end

    test "#{role} login still works and stays separated by role" do
      register(role, username: "login_#{role}", password: "secret123", password_confirmation: "secret123")
      delete logout_url
      other = role == "teacher" ? "student" : "teacher"

      post login_url, params: { role: other, username: "login_#{role}", password: "secret123" }
      assert_redirected_to login_url(role: other)

      post login_url, params: { role:, username: "login_#{role}", password: "secret123" }
      assert_redirected_to root_url
    end

    test "#{role} password recovery finds the account regardless of email case" do
      user = klass.create!(name: "N", username: "rec_#{role}", email: "rec@example.com", password: "secret123")

      post new_password_reset_url, params: { role:, email: "  REC@Example.com " }
      generic = flash[:notice]

      assert_redirected_to login_url(role:)
      assert user.reload[:password_reset_token].present?

      post new_password_reset_url, params: { role:, email: "ninguem@example.com" }
      assert_equal generic, flash[:notice]
    end

    test "#{role} reset with a valid 8 character password logs in with it" do
      token = SecureRandom.urlsafe_base64(24)
      user = klass.create!(name: "N", username: "rst_#{role}", email: "rst@example.com", password: "oldsecret",
        password_reset_token: token, password_reset_sent_at: Time.current)

      patch edit_password_reset_url(role, token), params: { user: { password: "12345678", password_confirmation: "12345678" } }
      assert_redirected_to login_url(role:)
      assert_nil user.reload[:password_reset_token]

      post login_url, params: { role:, username: user.username, password: "12345678" }
      assert_redirected_to root_url
    end

    test "#{role} reset with a short password shows a clear message and keeps the token" do
      token = SecureRandom.urlsafe_base64(24)
      user = klass.create!(name: "N", username: "rsh_#{role}", email: "rsh@example.com", password: "oldsecret",
        password_reset_token: token, password_reset_sent_at: Time.current)

      patch edit_password_reset_url(role, token), params: { user: { password: "abc1234", password_confirmation: "abc1234" } }

      assert_response :unprocessable_entity
      assert_includes response.body, "Senha deve ter pelo menos 8 caracteres"
      assert_equal token, user.reload[:password_reset_token]
      assert user.authenticate("oldsecret")
    end
  end

  test "registration with an invalid role still creates nothing" do
    assert_no_difference -> { Teacher.count + Student.count } do
      register("qualquercoisa")
    end
    assert_redirected_to login_url
  end
end
