require "test_helper"

class AccountCredentialsTest < ActiveSupport::TestCase
  ROLES = { "teacher" => Teacher, "student" => Student }.freeze

  ROLES.each do |role, klass|
    def build(klass, **attrs)
      suffix = SecureRandom.hex(4)
      klass.new({ name: "Nome", username: "u_#{suffix}", email: "#{suffix}@example.com",
                  password: "secret123", password_confirmation: "secret123" }.merge(attrs))
    end

    test "#{role} email accepts valid, trims and downcases it" do
      user = build(klass, email: "  Julia@Gmail.COM  ")

      assert user.valid?
      assert_equal "julia@gmail.com", user.email
      user.save!
      assert_equal "julia@gmail.com", user.reload.email
    end

    test "#{role} email rejects blank, nil and invalid formats in Portuguese" do
      [ nil, "", "   " ].each { |email| assert_not build(klass, email:).valid?, email.inspect }
      assert_includes build(klass, email: "").tap(&:valid?).errors.full_messages, "E-mail não pode ficar em branco"

      %w[abc @@ a@ @b.com].each do |email|
        user = build(klass, email:)
        assert_not user.valid?, email
        assert_equal [ "E-mail não é válido" ], user.errors.full_messages
      end
    end

    test "#{role} email length is limited to 150 characters" do
      assert build(klass, email: "#{'a' * 144}@b.com").valid?
      too_long = build(klass, email: "#{'a' * 145}@b.com")
      assert_not too_long.valid?
      assert_equal [ "E-mail é muito longo (máximo: 150 caracteres)" ], too_long.errors.full_messages
    end

    test "#{role} email uniqueness ignores case within the same role" do
      build(klass, email: "ana@example.com").save!

      duplicate = build(klass, email: "ANA@Example.com ")
      assert_not duplicate.valid?
      assert_equal [ "E-mail já está em uso" ], duplicate.errors.full_messages
    end

    test "#{role} password requires at least 8 characters" do
      assert build(klass, password: "12345678", password_confirmation: "12345678").valid?

      short = build(klass, password: "1234567", password_confirmation: "1234567")
      assert_not short.valid?
      assert_equal [ "Senha deve ter pelo menos 8 caracteres" ], short.errors.full_messages
    end

    test "#{role} password rejects nil, empty and blank-only values with a single message" do
      [ nil, "" ].each do |password|
        user = build(klass, password:, password_confirmation: password)
        assert_not user.valid?, password.inspect
        assert_equal [ "Senha não pode ficar em branco" ], user.errors.full_messages
      end

      [ " ", "        " ].each do |password|
        user = build(klass, password:, password_confirmation: password)
        assert_not user.valid?, password.inspect
        assert_equal [ "Senha não pode ficar em branco" ], user.errors.full_messages
      end
    end

    test "#{role} password keeps surrounding and inner spaces untouched" do
      user = build(klass, password: "  com espacos  ", password_confirmation: "  com espacos  ")

      assert user.save
      assert user.reload.authenticate("  com espacos  ")
      assert_not user.authenticate("com espacos")
    end

    test "#{role} password above 72 bytes is rejected with a Portuguese message" do
      assert build(klass, password: "a" * 72, password_confirmation: "a" * 72).valid?

      long = build(klass, password: "a" * 73, password_confirmation: "a" * 73)
      assert_not long.valid?
      assert_equal [ "Senha é muito longa (máximo de 72 bytes)" ], long.errors.full_messages
    end

    test "#{role} confirmation is required only when the registration flag is set" do
      user = build(klass, password_confirmation: nil)
      assert user.valid?

      user.require_password_confirmation = true
      assert_not user.valid?
      assert_equal [ "Confirmação da senha não pode ficar em branco" ], user.errors.full_messages

      user.password_confirmation = ""
      assert_not user.valid?
      assert_equal 1, user.errors.count
      assert_includes user.errors.full_messages.first, "Confirmação da senha"

      user.password_confirmation = "diferente1"
      assert_not user.valid?
      assert_equal [ "Confirmação da senha não é igual a Senha" ], user.errors.full_messages

      user.password_confirmation = "secret123"
      assert user.valid?
    end

    test "#{role} updates without a password change need neither password nor confirmation" do
      user = build(klass)
      user.require_password_confirmation = true
      user.save!

      reloaded = klass.find(user.id)
      reloaded.require_password_confirmation = true
      assert reloaded.update(name: "Novo nome", password_reset_token: "tok"), reloaded.errors.full_messages.inspect
      assert reloaded.reload.authenticate("secret123")
    end

    test "#{role} legacy account with a short password still authenticates and can be updated" do
      user = build(klass)
      user.save!
      user.update_column(:password_digest, BCrypt::Password.create("abc"))

      legacy = klass.find(user.id)
      assert legacy.authenticate("abc")
      assert legacy.update(name: "Atualizado")
      assert_not legacy.update(password: "abc", password_confirmation: "abc")
    end
  end

  test "same email is allowed for a teacher and a student" do
    build(Teacher, email: "mesmo@example.com").save!

    assert build(Student, email: "MESMO@example.com").save
  end
end
