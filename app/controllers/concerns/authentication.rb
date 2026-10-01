module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_teacher, :current_student, :current_user, :authenticated?
    before_action :require_authentication
  end

  def current_teacher
    @current_teacher ||= Teacher.active.find_by(id: session[:teacher_id])
  end

  def current_student
    @current_student ||= Student.active.find_by(id: session[:student_id])
  end

  def current_user
    current_teacher || current_student
  end

  def authenticated?
    current_user.present?
  end

  def require_authentication
    redirect_to login_path, alert: "Faça login para continuar." unless authenticated?
  end

  def sign_in(user)
    reset_session
    session["#{user.class.name.underscore}_id"] = user.id
  end

  def sign_out
    reset_session
  end
end
