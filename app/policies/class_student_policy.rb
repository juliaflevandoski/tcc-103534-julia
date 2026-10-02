class ClassStudentPolicy < ApplicationPolicy
  def index?
    teacher?
  end

  def show?
    teacher? ? owns_class? : own_membership?
  end

  def create?
    teacher? && (record == ClassStudent || owns_class?)
  end

  def new?
    teacher?
  end

  def update?
    teacher? && owns_class?
  end

  alias edit? update?

  def destroy?
    (teacher? && owns_class?) || (student? && own_membership?)
  end

  private

  def owns_class?
    record.school_class.teacher_id == user.id
  end

  def own_membership?
    record.student_id == user.id
  end
end
