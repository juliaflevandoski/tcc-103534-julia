class ExerciseAttemptPolicy < ApplicationPolicy
  def index?
    teacher? || student?
  end

  def show?
    owner? || teacher_owns_activity?
  end

  def create?
    student?
  end

  def new?
    false
  end

  def memory_game_turn?
    owner? && record.activity_exercise.exercise.memory_game?
  end

  def update?
    false
  end

  def edit?
    false
  end

  def destroy?
    owner? || teacher_owns_activity?
  end

  private

  def owner?
    student? && record.student_id == user.id
  end

  def teacher_owns_activity?
    teacher? && record.activity_exercise.activity.teacher_id == user.id
  end
end
