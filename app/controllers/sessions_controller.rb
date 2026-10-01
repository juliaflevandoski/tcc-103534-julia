class SessionsController < ApplicationController
  skip_before_action :require_authentication

  def new
    @role = normalized_role(params[:role])
  end

  def create
    role = normalized_role(params[:role])
    user = authenticate_user(role)

    if user
      sign_in(user)
      redirect_to root_path, notice: "Login realizado com sucesso."
    else
      redirect_to login_path(role: role), alert: "Usuário ou senha inválidos."
    end
  end

  def destroy
    sign_out
    redirect_to login_path, notice: "Você saiu da sua conta."
  end

  private

  def normalized_role(role)
    %w[teacher student].include?(role) ? role : nil
  end

  def authenticate_user(role)
    return unless role

    model = role == "teacher" ? Teacher : Student
    model.active.find_by(username: params[:username])&.authenticate(params[:password])
  end
end
