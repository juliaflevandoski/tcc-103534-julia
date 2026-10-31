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
    return if authenticated?

    store_return_location
    redirect_to login_path, alert: "Faça login para continuar."
  end

  def sign_in(user)
    reset_session
    session["#{user.class.name.underscore}_id"] = user.id
  end

  def sign_out
    reset_session
  end

  private

  # Lê e remove o destino salvo; deve ser chamado antes de sign_in, que reinicia a sessão.
  def consume_return_location
    path = session.delete(:return_to)
    path if safe_return_path?(path)
  end

  def store_return_location
    return unless request.get? && !request.xhr? && request.format.html?

    path = request.fullpath
    session[:return_to] = path if safe_return_path?(path)
  end

  def safe_return_path?(path)
    path.is_a?(String) && path.start_with?("/") && !path.start_with?("//") &&
      !path.match?(/[\\\x00-\x1f]/) && !path.match?(%r{\A/(login|logout)(\z|[/?#])})
  end
end
