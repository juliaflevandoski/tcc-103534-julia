require "test_helper"

class ClassPostTest < ActiveSupport::TestCase
  setup do
    @teacher = Teacher.create!(name: "Ana", username: "anapost", email: "anapost@example.com", password: "secret123")
    @other_teacher = Teacher.create!(name: "Bia", username: "biapost", email: "biapost@example.com", password: "secret123")
    @student = Student.create!(name: "Caio", username: "caiopost", email: "caiopost@example.com", password: "secret123")
    @school_class = SchoolClass.create!(teacher: @teacher, name: "Turma")
  end

  test "post takes the class teacher and strips the body" do
    post = @school_class.class_posts.create!(body: "  Aviso importante  ")

    assert_equal @teacher, post.teacher
    assert_equal "Aviso importante", post.body
    assert post.active?
  end

  test "post requires a body of at most 2000 characters" do
    assert_not @school_class.class_posts.build(body: "   ").valid?
    assert @school_class.class_posts.build(body: "a" * 2000).valid?

    post = @school_class.class_posts.build(body: "a" * 2001)
    assert_not post.valid?
    assert post.errors.of_kind?(:body, :too_long)
  end

  test "post teacher must be the class teacher" do
    post = ClassPost.new(school_class: @school_class, teacher: @other_teacher, body: "Oi")

    assert_not post.valid?
    assert_equal [ "deve ser o professor responsável pela turma" ], post.errors[:teacher]
  end

  test "post requires a class" do
    assert_not ClassPost.new(teacher: @teacher, body: "Oi").valid?
  end

  test "active scope and recent first ordering" do
    old = @school_class.class_posts.create!(body: "Antiga", created_at: 2.days.ago)
    recent = @school_class.class_posts.create!(body: "Nova", created_at: 1.hour.ago)
    hidden = @school_class.class_posts.create!(body: "Oculta", active: false)

    assert_equal [ recent, old ], @school_class.class_posts.active.recent_first.to_a
    assert_not_includes ClassPost.active, hidden
  end

  test "comments accept teacher and student authors and are chronological" do
    post = @school_class.class_posts.create!(body: "Aviso")
    second = post.comments.create!(author: @student, body: "Segundo", created_at: 1.minute.ago)
    first = post.comments.create!(author: @teacher, body: "Primeiro", created_at: 1.hour.ago)

    assert_equal [ first, second ], post.comments.active.chronological.to_a
    assert_equal [ first ], @teacher.class_post_comments.to_a
    assert_equal [ second ], @student.class_post_comments.to_a
  end

  test "comment requires body up to 500 characters" do
    post = @school_class.class_posts.create!(body: "Aviso")

    assert_not post.comments.build(author: @student, body: " ").valid?
    assert post.comments.build(author: @student, body: "a" * 500).valid?
    assert_not post.comments.build(author: @student, body: "a" * 501).valid?
  end

  test "comment author must be a teacher or a student" do
    post = @school_class.class_posts.create!(body: "Aviso")

    comment = post.comments.build(author: @school_class, body: "Oi")
    assert_not comment.valid?
    assert_equal [ "deve ser um professor ou um aluno" ], comment.errors[:author_type]
    assert_not post.comments.build(body: "Oi").valid?
  end

  test "existing associations are preserved" do
    assert_respond_to @school_class, :class_students
    assert_respond_to @teacher, :school_classes
    assert_respond_to @student, :exercise_attempts
  end
end
