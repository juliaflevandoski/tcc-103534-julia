class RegistrationsController < ApplicationController
  skip_before_action :require_authentication

  def new
    @role = normalized_role(params[:role])
    redirect_to login_path, alert: "Perfil inválido." unless @role
  end

  def create
    @role = normalized_role(params[:role])
    @user = model_for(@role).new(registration_params)

    if @user.save
      sign_in(@user)
      redirect_to root_path, notice: "Cadastro realizado com sucesso."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def normalized_role(role)
    %w[teacher student].include?(role) ? role : nil
  end

  def model_for(role)
    role == "teacher" ? Teacher : Student
  end

  def registration_params
    params.require(:registration).permit(:username, :email, :name, :password, :password_confirmation)
  end
end
