class ActivityPolicy < ApplicationPolicy
  def index?
    teacher? || student?
  end

  def show?
    teacher? ? record.teacher_id == user.id : student_can_access?
  end

  def create?
    teacher?
  end

  alias new? create?

  def update?
    show? && teacher?
  end

  alias edit? update?
  alias destroy? update?

  private

  def student_can_access?
    record.published? && record.school_class.class_students.active.exists?(student_id: user.id)
  end
end
