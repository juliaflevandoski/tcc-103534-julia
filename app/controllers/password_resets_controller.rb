class PasswordResetsController < ApplicationController
  skip_before_action :require_authentication

  def new
    @role = normalized_role(params[:role])
  end

  def create
    role = normalized_role(params[:role])
    PasswordResetRequest.call(role: role, email: params[:email]) if role
    redirect_to login_path(role: role), notice: "Se os dados estiverem corretos, enviaremos instruções para redefinir sua senha."
  end

  def edit
    @role = normalized_role(params[:role])
    @token = params[:token]
    @user = find_user
    render :edit unless @user.nil?
    redirect_to login_path(role: @role), alert: "Token de recuperação inválido ou expirado." unless @user
  end

  def update
    @role = normalized_role(params[:role])
    @token = params[:token]
    @user = find_user
    return redirect_to login_path(role: @role), alert: "Não foi possível redefinir a senha." unless @user

    password_attributes = params.fetch(:user, {}).permit(:password, :password_confirmation)
    password = password_attributes[:password]
    confirmation = password_attributes[:password_confirmation]

    # has_secure_password ignora senha vazia e confirmação ausente, então validamos aqui.
    if password.blank?
      @user.errors.add(:base, "Informe a nova senha.")
    elsif confirmation != password
      @user.errors.add(:base, "A confirmação da senha deve ser igual à nova senha.")
    else
      @user.assign_attributes(password:, password_confirmation: confirmation, password_reset_token: nil, password_reset_sent_at: nil)
      return redirect_to login_path(role: @role), notice: "Senha redefinida com sucesso." if @user.save
    end

    render :edit, status: :unprocessable_entity
  end

  private

  def normalized_role(role)
    %w[teacher student].include?(role) ? role : nil
  end

  def model
    @role == "teacher" ? Teacher : Student
  end

  def find_user
    return unless @role

    user = model.active.find_by(password_reset_token: @token)
    user unless user&.password_reset_expired?
  end
end
