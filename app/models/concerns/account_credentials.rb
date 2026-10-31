module AccountCredentials
  extend ActiveSupport::Concern

  PASSWORD_MIN_LENGTH = 8

  included do
    # Ativado apenas no cadastro, onde a confirmação da senha é obrigatória.
    attr_accessor :require_password_confirmation

    normalizes :email, with: ->(email) { email.strip.downcase }

    validates :name, length: { maximum: 150 }
    validates :username, length: { maximum: 50 }

    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 150 },
      uniqueness: { case_sensitive: false }, allow_blank: true
    validate :password_meets_policy
    validate :password_confirmation_provided
  end

  private

  # Só valida senhas novas: has_secure_password mantém password nil quando a senha não é alterada.
  def password_meets_policy
    return if password.nil?

    if password.blank?
      errors.add(:password, :blank)
    elsif password.length < PASSWORD_MIN_LENGTH
      errors.add(:password, :password_too_short, count: PASSWORD_MIN_LENGTH)
    end
  end

  # Confirmação vazia ou diferente já é tratada por has_secure_password.
  def password_confirmation_provided
    return unless require_password_confirmation
    return if password.nil? || password_confirmation

    errors.add(:password_confirmation, :blank)
  end
end
