class ClassStudentPolicy < ApplicationPolicy
  def index?
    teacher?
  end

  def show?
    teacher? ? record.school_class.teacher_id == user.id : record.student_id == user.id
  end

  def create?
    teacher?
  end

  alias new? create?

  def update?
    show? && teacher?
  end

  alias edit? update?
  alias destroy? show?
end
