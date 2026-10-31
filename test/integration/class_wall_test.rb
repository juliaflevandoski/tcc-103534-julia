require "test_helper"

class ClassWallTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "Prof Ana")
    @other_teacher = create_user(Teacher, "Prof Bia")
    @student = create_user(Student, "Aluno Caio")
    @other_student = create_user(Student, "Aluno Davi")
    @outsider = create_user(Student, "Aluno Eva")
    @school_class = @teacher.school_classes.create!(name: "Turma mural")
    @school_class.class_students.create!(student: @student)
    @school_class.class_students.create!(student: @other_student)
    @other_class = @other_teacher.school_classes.create!(name: "Outra turma")
    @post = @school_class.class_posts.create!(body: "Aviso um", created_at: 2.days.ago)
    @other_post = @other_class.class_posts.create!(body: "Aviso alheio")
  end

  def wall = school_class_class_posts_path(@school_class)

  test "class page links to the wall and the wall links back" do
    [ @teacher, @student ].each do |user|
      login(user)
      get school_class_url(@school_class)
      assert_select "a[href='#{wall}']", text: "Mural"
      get wall
      assert_response :success
      assert_select "a[href='#{school_class_path(@school_class)}']", text: "Voltar à turma"
    end
  end

  test "posts are listed newest first and comments chronologically, with names but no emails" do
    newer = @school_class.class_posts.create!(body: "Aviso novo")
    @post.comments.create!(author: @student, body: "Segundo", created_at: 1.hour.ago)
    @post.comments.create!(author: @teacher, body: "Primeiro", created_at: 5.hours.ago)
    login(@student)

    get wall

    assert_response :success
    assert_operator response.body.index("Aviso novo"), :<, response.body.index("Aviso um")
    assert_operator response.body.index("Primeiro"), :<, response.body.index("Segundo")
    assert_includes response.body, "Aluno Caio"
    assert_not_includes response.body, @student.email
    assert_not_includes response.body, @teacher.email
    assert_not_includes response.body, "Aviso alheio"
    assert newer.persisted?
  end

  test "student does not see post management or the new post form" do
    login(@student)
    get wall

    assert_select "form[action='#{wall}']", count: 0
    assert_select "a[href='#{edit_school_class_class_post_path(@school_class, @post)}']", count: 0
    assert_select "form[action='#{school_class_class_post_path(@school_class, @post)}']", count: 0
    assert_select "form[action='#{school_class_class_post_comments_path(@school_class, @post)}']", count: 1
  end

  test "teacher creates, edits and logically deletes a post" do
    login(@teacher)

    assert_difference -> { @school_class.class_posts.count }, 1 do
      post wall, params: { class_post: { body: "  Novo aviso  " } }
    end
    assert_redirected_to wall
    created = @school_class.class_posts.order(:id).last
    assert_equal "Novo aviso", created.body
    assert_equal @teacher, created.teacher

    patch school_class_class_post_path(@school_class, created), params: { class_post: { body: "Editado" } }
    assert_redirected_to wall
    assert_equal "Editado", created.reload.body

    assert_no_difference -> { ClassPost.count } do
      delete school_class_class_post_path(@school_class, created)
    end
    assert_redirected_to wall
    assert_not created.reload.active?
    get wall
    assert_not_includes response.body, "Editado"
  end

  test "post validations return 422 with messages and keep the text" do
    login(@teacher)

    assert_no_difference -> { ClassPost.count } do
      post wall, params: { class_post: { body: "   " } }
    end
    assert_response :unprocessable_entity
    assert_select ".errors"

    post wall, params: { class_post: { body: "a" * 2001 } }
    assert_response :unprocessable_entity

    patch school_class_class_post_path(@school_class, @post), params: { class_post: { body: "" } }
    assert_response :unprocessable_entity
    assert_equal "Aviso um", @post.reload.body
  end

  test "student cannot create, edit or delete posts" do
    login(@student)

    assert_no_difference -> { ClassPost.count } do
      post wall, params: { class_post: { body: "Intruso" } }
    end
    assert_redirected_to root_path
    patch school_class_class_post_path(@school_class, @post), params: { class_post: { body: "Intruso" } }
    get edit_school_class_class_post_path(@school_class, @post)
    assert_redirected_to root_path
    delete school_class_class_post_path(@school_class, @post)
    assert_equal "Aviso um", @post.reload.body
    assert @post.active?
  end

  test "student and teacher comment, edit and delete their own comments" do
    login(@student)
    assert_difference -> { @post.comments.count }, 1 do
      post school_class_class_post_comments_path(@school_class, @post), params: { class_post_comment: { body: " Oi " } }
    end
    assert_redirected_to wall
    comment = @post.comments.order(:id).last
    assert_equal [ "Oi", @student ], [ comment.body, comment.author ]

    get edit_school_class_class_post_comment_path(@school_class, @post, comment)
    assert_response :success
    patch school_class_class_post_comment_path(@school_class, @post, comment), params: { class_post_comment: { body: "Editado" } }
    assert_equal "Editado", comment.reload.body
    delete school_class_class_post_comment_path(@school_class, @post, comment)
    assert_not comment.reload.active?

    login(@teacher)
    post school_class_class_post_comments_path(@school_class, @post), params: { class_post_comment: { body: "Do professor" } }
    teacher_comment = @post.comments.order(:id).last
    assert_equal @teacher, teacher_comment.author
    patch school_class_class_post_comment_path(@school_class, @post, teacher_comment), params: { class_post_comment: { body: "Prof editado" } }
    assert_equal "Prof editado", teacher_comment.reload.body
    delete school_class_class_post_comment_path(@school_class, @post, teacher_comment)
    assert_not teacher_comment.reload.active?
  end

  test "teacher moderates a student's comment but cannot edit it" do
    comment = @post.comments.create!(author: @student, body: "Texto do aluno")
    login(@teacher)

    get wall
    assert_select "form[action='#{school_class_class_post_comment_path(@school_class, @post, comment)}']", count: 1
    assert_select "a[href='#{edit_school_class_class_post_comment_path(@school_class, @post, comment)}']", count: 0

    patch school_class_class_post_comment_path(@school_class, @post, comment), params: { class_post_comment: { body: "Adulterado" } }
    assert_redirected_to root_path
    assert_equal "Texto do aluno", comment.reload.body

    assert_no_difference -> { ClassPostComment.count } do
      delete school_class_class_post_comment_path(@school_class, @post, comment)
    end
    assert_not comment.reload.active?
  end

  test "student cannot edit or delete another student's or the teacher's comment" do
    theirs = @post.comments.create!(author: @other_student, body: "Do colega")
    teachers = @post.comments.create!(author: @teacher, body: "Do professor")
    login(@student)

    [ theirs, teachers ].each do |comment|
      patch school_class_class_post_comment_path(@school_class, @post, comment), params: { class_post_comment: { body: "Hack" } }
      assert_redirected_to root_path
      delete school_class_class_post_comment_path(@school_class, @post, comment)
      assert comment.reload.active?
      assert_not_equal "Hack", comment.body
    end
  end

  test "comment validations return 422 and keep the wall rendered" do
    login(@student)

    assert_no_difference -> { ClassPostComment.count } do
      post school_class_class_post_comments_path(@school_class, @post), params: { class_post_comment: { body: " " } }
      assert_response :unprocessable_entity
      assert_select ".errors"
      post school_class_class_post_comments_path(@school_class, @post), params: { class_post_comment: { body: "a" * 501 } }
      assert_response :unprocessable_entity
    end
    comment = @post.comments.create!(author: @student, body: "Ok")
    patch school_class_class_post_comment_path(@school_class, @post, comment), params: { class_post_comment: { body: "" } }
    assert_response :unprocessable_entity
    assert_equal "Ok", comment.reload.body
  end

  test "outsider student and other teacher have no access" do
    comment = @post.comments.create!(author: @student, body: "Interno")

    [ @outsider, @other_teacher ].each do |user|
      login(user)
      get wall
      assert_redirected_to root_path
      post wall, params: { class_post: { body: "x" } }
      assert_redirected_to root_path
      post school_class_class_post_comments_path(@school_class, @post), params: { class_post_comment: { body: "x" } }
      assert_redirected_to root_path
      delete school_class_class_post_comment_path(@school_class, @post, comment)
      assert_redirected_to root_path
      delete school_class_class_post_path(@school_class, @post)
      assert_redirected_to root_path
    end
    assert_equal 1, @post.comments.count
    assert @post.reload.active? && comment.reload.active?
  end

  test "student who left loses access and regains the history when re-enrolled" do
    membership = @school_class.class_students.find_by(student: @student)
    membership.update!(active: false)
    login(@student)
    get wall
    assert_redirected_to root_path

    membership.update!(active: true)
    get wall
    assert_response :success
    assert_includes response.body, "Aviso um"
  end

  test "forged ownership parameters are ignored" do
    login(@student)
    post school_class_class_post_comments_path(@school_class, @post), params: { class_post_comment: {
      body: "Forjado", author_id: @teacher.id, author_type: "Teacher", class_post_id: @other_post.id, active: false
    }, author_id: @teacher.id }
    comment = ClassPostComment.order(:id).last
    assert_equal [ @student, @post, true ], [ comment.author, comment.class_post, comment.active ]

    login(@teacher)
    post wall, params: { class_post: { body: "Meu", teacher_id: @other_teacher.id, class_id: @other_class.id, active: false } }
    created = ClassPost.order(:id).last
    assert_equal [ @teacher, @school_class, true ], [ created.teacher, created.school_class, created.active ]

    patch school_class_class_post_path(@school_class, created), params: { class_post: { body: "Meu 2", class_id: @other_class.id, active: false } }
    created.reload
    assert_equal [ "Meu 2", @school_class.id, true ], [ created.body, created.class_id, created.active ]
  end

  test "posts and comments of another class cannot be reached by changing ids in the url" do
    foreign_comment = @other_post.comments.create!(author: @other_teacher, body: "Alheio")
    login(@teacher)

    get edit_school_class_class_post_path(@school_class, @other_post)
    assert_response :not_found
    patch school_class_class_post_path(@school_class, @other_post), params: { class_post: { body: "Hack" } }
    assert_response :not_found
    delete school_class_class_post_path(@school_class, @other_post)
    assert_response :not_found
    post school_class_class_post_comments_path(@school_class, @other_post), params: { class_post_comment: { body: "Hack" } }
    assert_response :not_found
    delete school_class_class_post_comment_path(@school_class, @post, foreign_comment)
    assert_response :not_found
    get wall.sub(@school_class.id.to_s, @other_class.id.to_s)
    assert_redirected_to root_path

    assert @other_post.reload.active?
    assert_equal "Aviso alheio", @other_post.body
    assert foreign_comment.reload.active?
  end

  test "inactive posts, comments and classes are not shown or reachable" do
    hidden = @school_class.class_posts.create!(body: "Post oculto", active: false)
    @post.comments.create!(author: @student, body: "Comentário oculto", active: false)
    login(@student)

    get wall
    assert_not_includes response.body, "Post oculto"
    assert_not_includes response.body, "Comentário oculto"

    assert_no_difference -> { ClassPostComment.count } do
      post school_class_class_post_comments_path(@school_class, hidden), params: { class_post_comment: { body: "x" } }
    end
    assert_response :not_found

    @school_class.update!(active: false)
    get wall
    assert_response :not_found
    post school_class_class_post_comments_path(@school_class, @post), params: { class_post_comment: { body: "x" } }
    assert_response :not_found
  end

  test "text is escaped" do
    @post.update!(body: "<script>alert(1)</script>")
    login(@student)
    get wall

    assert_not_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  test "wall requires authentication" do
    get wall
    assert_redirected_to login_path
  end

  private

  def create_user(klass, name)
    id = "#{name.parameterize}-#{SecureRandom.hex(6)}"
    klass.create!(name:, username: id, email: "#{id}@example.com", password: "secret123")
  end

  def login(user)
    role = user.is_a?(Teacher) ? "teacher" : "student"
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end
end
