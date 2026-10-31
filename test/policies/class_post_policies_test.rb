require "test_helper"

class ClassPostPoliciesTest < ActiveSupport::TestCase
  setup do
    @teacher = Teacher.create!(name: "Ana", username: "anapol", email: "anapol@example.com", password: "secret123")
    @other_teacher = Teacher.create!(name: "Bia", username: "biapol", email: "biapol@example.com", password: "secret123")
    @student = Student.create!(name: "Caio", username: "caiopol", email: "caiopol@example.com", password: "secret123")
    @other_student = Student.create!(name: "Davi", username: "davipol", email: "davipol@example.com", password: "secret123")
    @outsider = Student.create!(name: "Eva", username: "evapol", email: "evapol@example.com", password: "secret123")
    @school_class = SchoolClass.create!(teacher: @teacher, name: "Turma")
    @membership = ClassStudent.create!(student: @student, school_class: @school_class)
    ClassStudent.create!(student: @other_student, school_class: @school_class)
    @other_class = SchoolClass.create!(teacher: @other_teacher, name: "Outra")
    @post = @school_class.class_posts.create!(body: "Aviso")
    @other_post = @other_class.class_posts.create!(body: "Outro aviso")
    @teacher_comment = @post.comments.create!(author: @teacher, body: "Professor")
    @student_comment = @post.comments.create!(author: @student, body: "Aluno")
    @other_student_comment = @post.comments.create!(author: @other_student, body: "Outro aluno")
  end

  def post_policy(user, record = @post) = ClassPostPolicy.new(user, record)
  def comment_policy(user, record) = ClassPostCommentPolicy.new(user, record)

  test "class teacher manages own posts" do
    policy = post_policy(@teacher)
    assert policy.index?
    assert policy.show?
    assert policy.create?
    assert policy.update?
    assert policy.edit?
    assert policy.destroy?
    assert post_policy(@teacher, @school_class.class_posts.build).create?
  end

  test "teacher cannot manage or see posts of another class" do
    policy = post_policy(@teacher, @other_post)
    assert_not policy.index?
    assert_not policy.show?
    assert_not policy.create?
    assert_not policy.update?
    assert_not policy.destroy?
    assert_not post_policy(@teacher, @other_class.class_posts.build).create?
    assert_not post_policy(@other_teacher).update?
  end

  test "enrolled student can view but not create, edit or delete posts" do
    policy = post_policy(@student)
    assert policy.index?
    assert policy.show?
    assert_not policy.create?
    assert_not policy.update?
    assert_not policy.destroy?
    assert_not post_policy(@student, @school_class.class_posts.build).create?
  end

  test "student not enrolled or who left has no access" do
    assert_not post_policy(@outsider).index?
    assert_not post_policy(@outsider).show?

    @membership.update!(active: false)
    assert_not post_policy(@student).index?
    assert_not post_policy(@student).show?
    assert_not comment_policy(@student, @student_comment).show?

    @membership.update!(active: true)
    assert post_policy(@student).show?
    assert comment_policy(@student, @student_comment).update?
  end

  test "inactive post is hidden and unmanageable, inactive class denies everything" do
    @post.update!(active: false)
    assert_not post_policy(@student).show?
    assert_not post_policy(@teacher).update?
    assert_not comment_policy(@student, @post.comments.build(author: @student, body: "x")).create?

    @school_class.update!(active: false)
    @post.reload
    assert_not post_policy(@teacher).index?
    assert_not post_policy(@student, @school_class.class_posts.build).index?
  end

  test "teacher and enrolled students can comment, others cannot" do
    [ @teacher, @student, @other_student ].each do |user|
      assert comment_policy(user, @post.comments.build(author: user, body: "Oi")).create?, user.class.name
    end
    [ @outsider, @other_teacher ].each do |user|
      assert_not comment_policy(user, @post.comments.build(author: user, body: "Oi")).create?
    end
    assert_not comment_policy(@teacher, @other_post.comments.build(author: @teacher, body: "Oi")).create?
  end

  test "authors edit and delete only their own comments" do
    assert comment_policy(@student, @student_comment).update?
    assert comment_policy(@student, @student_comment).destroy?
    assert_not comment_policy(@student, @other_student_comment).update?
    assert_not comment_policy(@student, @other_student_comment).destroy?
    assert_not comment_policy(@student, @teacher_comment).destroy?
    assert comment_policy(@teacher, @teacher_comment).update?
  end

  test "author identity checks the type as well as the id" do
    comment = @post.comments.create!(author: @other_student, body: "x")
    comment.update_columns(author_id: @teacher.id, author_type: "Student")

    assert_not comment_policy(@teacher, comment).update?
  end

  test "class teacher moderates students' comments but cannot edit them" do
    assert comment_policy(@teacher, @student_comment).destroy?
    assert_not comment_policy(@teacher, @student_comment).update?
  end

  test "teacher of another class cannot moderate" do
    assert_not comment_policy(@other_teacher, @student_comment).destroy?
    assert_not comment_policy(@other_teacher, @student_comment).show?
  end

  test "inactive comments cannot be shown, edited or deleted" do
    @student_comment.update!(active: false)

    assert_not comment_policy(@student, @student_comment).show?
    assert_not comment_policy(@student, @student_comment).update?
    assert_not comment_policy(@teacher, @student_comment).destroy?
  end
end
