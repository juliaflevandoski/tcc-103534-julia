class TeacherPolicy < ApplicationPolicy
  def index?
    teacher?
  end

  def show?
    own_profile?
  end

  def create?
    false
  end

  alias new? create?

  def update?
    own_profile?
  end

  alias edit? update?
  alias destroy? update?

  private

  def own_profile?
    teacher? && record.id == user.id
  end
end
