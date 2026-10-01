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

  alias new? create?

  def memory_game_turn?
    owner? && record.activity_exercise.exercise.memory_game?
  end

  def update?
    owner? && !crossword_attempt?
  end

  alias edit? update?
  alias destroy? update?

  private

  def owner?
    student? && record.student_id == user.id
  end

  def teacher_owns_activity?
    teacher? && record.activity_exercise.activity.teacher_id == user.id
  end

  def crossword_attempt?
    record.activity_exercise.exercise.crossword?
  end
end
