class ClassPostCommentPolicy < ApplicationPolicy
  def create?
    class_access? && record.class_post.active?
  end

  def show?
    create? && record.active?
  end

  def update?
    show? && own_comment?
  end

  alias edit? update?

  def destroy?
    show? && (own_comment? || moderator?)
  end

  private

  def school_class
    record.class_post&.school_class
  end

  def class_access?
    school_class.present? && school_class.active? && SchoolClassPolicy.new(user, school_class).show?
  end

  def own_comment?
    record.author_type == user.class.name && record.author_id == user.id
  end

  def moderator?
    teacher? && school_class.teacher_id == user.id
  end
end
