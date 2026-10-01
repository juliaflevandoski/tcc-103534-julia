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
    password_attributes = params.require(:user).permit(:password, :password_confirmation)
    if @user
      @user.password = password_attributes["password"]
      @user.password_confirmation = password_attributes["password_confirmation"]
      @user.password_reset_token = nil
      @user.password_reset_sent_at = nil
    end

    if @user&.save
      redirect_to login_path(role: @role), notice: "Senha redefinida com sucesso."
    else
      redirect_to login_path(role: @role), alert: "Não foi possível redefinir a senha."
    end
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
