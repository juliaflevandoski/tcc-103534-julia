class ClassPostPolicy < ApplicationPolicy
  def index?
    class_access?
  end

  def show?
    class_access? && record.active?
  end

  def create?
    manages_class?
  end

  def update?
    manages_class? && record.active? && record.teacher_id == user.id
  end

  alias edit? update?
  alias destroy? update?

  private

  def school_class
    record.school_class
  end

  def class_access?
    school_class.present? && school_class.active? && SchoolClassPolicy.new(user, school_class).show?
  end

  def manages_class?
    teacher? && class_access?
  end
end
