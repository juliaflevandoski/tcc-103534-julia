class SchoolClassPolicy < ApplicationPolicy
  def index?
    teacher? || student?
  end

  def show?
    teacher? ? record.teacher_id == user.id : enrolled?
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

  def join?
    student?
  end

  def leave?
    student? && enrolled?
  end

  private

  def enrolled?
    record.class_students.active.exists?(student_id: user.id)
  end
end
