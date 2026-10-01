class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def teacher?
    user.is_a?(Teacher)
  end

  def student?
    user.is_a?(Student)
  end

  def own_record?
    teacher? && record.respond_to?(:teacher_id) && record.teacher_id == user.id
  end
end
