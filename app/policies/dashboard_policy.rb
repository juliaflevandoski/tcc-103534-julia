class DashboardPolicy < ApplicationPolicy
  def show?
    teacher? || student?
  end
end
