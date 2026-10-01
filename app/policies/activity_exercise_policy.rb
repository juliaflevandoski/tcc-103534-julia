class ActivityExercisePolicy < ApplicationPolicy
  def index?
    teacher?
  end

  def show?
    teacher? ? owner? : student_can_access?
  end

  def create?
    teacher?
  end

  alias new? create?

  def update?
    owner?
  end

  alias edit? update?
  alias destroy? update?

  private

  def owner?
    teacher? && record.activity.teacher_id == user.id
  end

  def student_can_access?
    record.active? && record.activity.active? && record.activity.published? && record.activity.school_class.active? &&
      record.activity.school_class.class_students.active.exists?(student_id: user.id)
  end
end
