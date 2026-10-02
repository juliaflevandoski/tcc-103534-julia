class StudentStatPolicy < ApplicationPolicy
  def index?
    teacher? || student?
  end

  def show?
    own_student? || teacher_has_student?
  end

  def new?
    false
  end

  def create?
    false
  end

  def edit?
    false
  end

  def update?
    false
  end

  def destroy?
    false
  end

  private

  def own_student?
    student? && record.student_id == user.id
  end

  def teacher_has_student?
    return false unless teacher?

    ClassStudent.active.joins(:school_class).where(
      student_id: record.student_id,
      classes: { teacher_id: user.id, active: true }
    ).exists?
  end
end
