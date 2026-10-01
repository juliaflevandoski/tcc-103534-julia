class PasswordResetRequest
  TOKEN_EXPIRATION = 2.hours

  def self.call(role:, email:)
    new(role: role, email: email).call
  end

  def initialize(role:, email:)
    @role = role
    @email = email
  end

  def call
    user = model.active.find_by(email: @email)
    return unless user

    token = SecureRandom.urlsafe_base64(32)
    user.update!(password_reset_token: token, password_reset_sent_at: Time.current)
    Rails.logger.info("Password reset token for #{model.name} #{user.id}: #{token}") if Rails.env.development?
  end

  private

  def model
    @role == "teacher" ? Teacher : Student
  end
end
