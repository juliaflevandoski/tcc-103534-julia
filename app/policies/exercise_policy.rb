class ExercisePolicy < ApplicationPolicy
  def index?
    teacher?
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
    record.activity_exercises.active.joins(activity: :school_class).where(
      activities: { published: true },
      classes: { active: true }
    ).joins(activity: { school_class: :class_students }).where(
      classes_students: { student_id: user.id, active: true }
    ).exists?
  end
end
