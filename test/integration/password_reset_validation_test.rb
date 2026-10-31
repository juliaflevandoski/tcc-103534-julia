require "test_helper"

class PasswordResetValidationTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  ROLES = { "teacher" => Teacher, "student" => Student }.freeze

  ROLES.each do |role, klass|
    test "#{role} resets password with valid password and confirmation" do
      user, token = user_with_token(klass)

      get edit_password_reset_url(role, token)
      assert_response :success
      reset(role, token, "newsecret", "newsecret")

      assert_redirected_to login_url(role:)
      assert_equal "Senha redefinida com sucesso.", flash[:notice]
      user.reload
      assert_nil user[:password_reset_token]
      assert_nil user.password_reset_sent_at
      assert user.authenticate("newsecret")
      assert_not user.authenticate("oldsecret")
      login_ok?(role, user, "newsecret")
    end

    {
      "empty password" => [ "", "" ],
      "blank-only password" => [ "   ", "   " ],
      "7-character password" => [ "abc1234", "abc1234" ],
      "empty confirmation" => [ "newsecret", "" ],
      "missing confirmation" => [ "newsecret", nil ],
      "mismatched confirmation" => [ "newsecret", "other123" ]
    }.each do |label, (password, confirmation)|
      test "#{role} rejects #{label} keeping token and old password, then accepts a retry" do
        user, token = user_with_token(klass)
        sent_at = user.password_reset_sent_at
        digest = user.password_digest

        reset(role, token, password, confirmation)

        assert_response :unprocessable_entity
        assert_select ".errors li"
        user.reload
        assert_equal token, user[:password_reset_token]
        assert_equal sent_at.to_i, user.password_reset_sent_at.to_i
        assert_equal digest, user.password_digest
        assert user.authenticate("oldsecret")

        reset(role, token, "newsecret", "newsecret")

        assert_redirected_to login_url(role:)
        user.reload
        assert_nil user[:password_reset_token]
        assert user.authenticate("newsecret")
      end
    end

    test "#{role} token is single use" do
      user, token = user_with_token(klass)
      reset(role, token, "newsecret", "newsecret")

      reset(role, token, "another123", "another123")

      assert_redirected_to login_url(role:)
      assert user.reload.authenticate("newsecret")
    end

    test "#{role} rejects invalid and expired tokens without changing the password" do
      user, token = user_with_token(klass)

      reset(role, "invalid-token", "newsecret", "newsecret")
      assert_redirected_to login_url(role:)
      assert user.reload.authenticate("oldsecret")

      user.update!(password_reset_sent_at: 3.hours.ago)
      get edit_password_reset_url(role, token)
      assert_redirected_to login_url(role:)
      reset(role, token, "newsecret", "newsecret")
      assert_redirected_to login_url(role:)
      assert user.reload.authenticate("oldsecret")
      assert_equal token, user[:password_reset_token]
    end

    test "#{role} request without password fields does not consume the token" do
      user, token = user_with_token(klass)

      patch edit_password_reset_url(role, token), params: {}

      assert_response :unprocessable_entity
      assert_equal token, user.reload[:password_reset_token]
      assert user.authenticate("oldsecret")
    end
  end

  private

  def user_with_token(klass)
    id = "pr-#{klass.name.downcase}-#{SecureRandom.hex(6)}"
    token = SecureRandom.urlsafe_base64(24)
    user = klass.create!(name: id, username: id, email: "#{id}@example.com", password: "oldsecret",
      password_reset_token: token, password_reset_sent_at: Time.current)
    [ user, token ]
  end

  def reset(role, token, password, confirmation)
    fields = { password: }
    fields[:password_confirmation] = confirmation unless confirmation.nil?
    patch edit_password_reset_url(role, token), params: { user: fields }
  end

  def login_ok?(role, user, password)
    post login_url, params: { role:, username: user.username, password: }
    assert_redirected_to root_url
  end
end
