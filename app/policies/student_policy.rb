class StudentPolicy < ApplicationPolicy
  def index?
    student?
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
    student? && record.id == user.id
  end
end
