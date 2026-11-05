require "test_helper"

class ClassStudentContextTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "ctx-teacher")
    @school_class = @teacher.school_classes.create!(name: "Turma contexto", active: true)
    @other_class = @teacher.school_classes.create!(name: "Outra turma", active: true)
    @inactive_class = @teacher.school_classes.create!(name: "Turma inativa", active: false)
    @student = create_user(Student, "ctx-student")
    @other_student = create_user(Student, "ctx-other-student")
    @school_class.class_students.create!(student: @student, active: true)
    @other_class.class_students.create!(student: @other_student, active: true)
    @foreign_teacher = create_user(Teacher, "ctx-foreign")
    @foreign_class = @foreign_teacher.school_classes.create!(name: "Turma alheia", active: true)
    @foreign_student = create_user(Student, "ctx-foreign-student")
    @foreign_class.class_students.create!(student: @foreign_student, active: true)
  end

  test "index with a valid class_id lists only that class active enrollments" do
    login(@teacher)

    get class_students_url(class_id: @school_class.id)

    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "td", text: @student.name
    assert_select "td", text: @other_student.name, count: 0
    assert_select "td", text: @foreign_student.name, count: 0
  end

  test "index does not list inactive enrollments of the selected class" do
    login(@teacher)
    @school_class.class_students.find_by!(student: @student).update!(active: false)

    get class_students_url(class_id: @school_class.id)

    assert_response :success
    assert_select "tbody tr", count: 0
  end

  test "index without class_id keeps the general listing" do
    login(@teacher)

    get class_students_url

    assert_response :success
    assert_select "tbody tr", count: 2
    assert_select "td", text: @student.name
    assert_select "td", text: @other_student.name
    assert_select "td", text: @foreign_student.name, count: 0
  end

  test "index rejects invalid class contexts without widening the query" do
    login(@teacher)
    invalid_params = [
      { class_id: @foreign_class.id },
      { class_id: 0 },
      { class_id: @inactive_class.id },
      { class_id: "abc" },
      { class_id: "#{@school_class.id}abc" },
      { class_id: "" },
      { class_id: [@school_class.id] },
      { class_id: { id: @school_class.id } }
    ]

    invalid_params.each do |query|
      get class_students_url, params: query

      assert_redirected_to school_classes_url, "esperava redirecionamento para #{query.inspect}"
      assert_equal "Turma inválida ou sem permissão de acesso.", flash[:alert]
    end
  end

  test "new preselects the context class and keeps the select contract" do
    login(@teacher)

    get new_class_student_url(class_id: @school_class.id)

    assert_response :success
    assert_select "select[name='class_student[class_id]'][required]" do
      assert_select "option[selected][value='#{@school_class.id}']", count: 1
      assert_select "option[value='#{@other_class.id}']", count: 1
      assert_select "option[value='']", count: 1
    end
  end

  test "new without a valid context has no preselected class" do
    login(@teacher)

    [{}, { class_id: @foreign_class.id }, { class_id: "abc" }, { class_id: [@school_class.id] }].each do |query|
      get new_class_student_url, params: query

      assert_response :success
      assert_select "select[name='class_student[class_id]'] option[selected]", count: 0
    end
  end

  test "students cannot use the enrollment management with a class_id" do
    login(@student)

    get class_students_url(class_id: @school_class.id)

    assert_redirected_to root_url

    get new_class_student_url(class_id: @school_class.id)

    assert_redirected_to root_url
  end

  test "index propagates the context to new, view, edit and deactivate links" do
    login(@teacher)
    membership = @school_class.class_students.find_by!(student: @student)

    get class_students_url(class_id: @school_class.id)

    assert_select "a[href='#{new_class_student_path(class_id: @school_class.id)}']", text: "Nova matrícula", count: 1
    assert_select "a[href='#{class_student_path(membership, class_id: @school_class.id)}']", text: "Ver", count: 1
    assert_select "a[href='#{edit_class_student_path(membership, class_id: @school_class.id)}']", text: "Editar", count: 1
    assert_select "form[action='#{class_student_path(membership, class_id: @school_class.id)}']", count: 1
  end

  test "index without context keeps the original links" do
    login(@teacher)

    get class_students_url

    assert_select "a[href='#{new_class_student_path}']", text: "Nova matrícula", count: 1
  end

  test "new form keeps the context in cancel link and hidden field" do
    login(@teacher)

    get new_class_student_url(class_id: @school_class.id)

    assert_select "a[href='#{class_students_path(class_id: @school_class.id)}']", text: "Cancelar", count: 1
    assert_select "input[type=hidden][name='class_id'][value='#{@school_class.id}']", count: 1
    assert_select "select[name='class_student[class_id]'] option[selected][value='#{@school_class.id}']", count: 1
  end

  test "forms without context keep the original cancel link and no hidden field" do
    login(@teacher)

    get new_class_student_url

    assert_select "a[href='#{class_students_path}']", text: "Cancelar", count: 1
    assert_select "input[type=hidden][name='class_id']", count: 0
  end

  test "edit keeps the context in cancel link" do
    login(@teacher)
    membership = @school_class.class_students.find_by!(student: @student)

    get edit_class_student_url(membership, class_id: @school_class.id)

    assert_select "a[href='#{class_students_path(class_id: @school_class.id)}']", text: "Cancelar", count: 1
    assert_select "input[type=hidden][name='class_id'][value='#{@school_class.id}']", count: 1
  end

  test "show keeps the context and links back to enrollments and to the class" do
    login(@teacher)
    membership = @school_class.class_students.find_by!(student: @student)

    get class_student_url(membership, class_id: @school_class.id)

    assert_select "a[href='#{edit_class_student_path(membership, class_id: @school_class.id)}']", text: "Editar", count: 1
    assert_select "a[href='#{class_students_path(class_id: @school_class.id)}']", text: "Voltar às matrículas", count: 1
    assert_select "a[href='#{school_class_path(@school_class)}']", text: "Voltar à turma", count: 1

    get class_student_url(membership)

    assert_select "a", text: "Voltar à turma", count: 0
    assert_select "a[href='#{edit_class_student_path(membership)}']", text: "Editar", count: 1
  end

  test "create with context redirects to the saved enrollment keeping the class" do
    login(@teacher)
    new_student = create_user(Student, "ctx-new-student")

    assert_difference("ClassStudent.count", 1) do
      post class_students_url, params: { class_id: @school_class.id, class_student: { student_id: new_student.id, class_id: @school_class.id } }
    end

    membership = ClassStudent.find_by!(student: new_student)
    assert_redirected_to class_student_url(membership, class_id: @school_class.id)
  end

  test "create without context keeps the original redirect" do
    login(@teacher)
    new_student = create_user(Student, "ctx-plain-student")

    post class_students_url, params: { class_student: { student_id: new_student.id, class_id: @school_class.id } }

    assert_redirected_to class_student_url(ClassStudent.find_by!(student: new_student))
  end

  test "create with validation error keeps the context" do
    login(@teacher)

    assert_no_difference("ClassStudent.count") do
      post class_students_url, params: { class_id: @school_class.id, class_student: { student_id: @student.id, class_id: @school_class.id } }
    end

    assert_response :unprocessable_entity
    assert_select "input[type=hidden][name='class_id'][value='#{@school_class.id}']", count: 1
    assert_select "a[href='#{class_students_path(class_id: @school_class.id)}']", text: "Cancelar", count: 1
  end

  test "update with context keeps the class and follows a moved enrollment" do
    login(@teacher)
    membership = @school_class.class_students.find_by!(student: @student)

    patch class_student_url(membership), params: { class_id: @school_class.id, class_student: { student_id: @student.id, class_id: @school_class.id } }
    assert_redirected_to class_student_url(membership, class_id: @school_class.id)

    patch class_student_url(membership), params: { class_id: @school_class.id, class_student: { student_id: @student.id, class_id: @other_class.id } }
    assert_redirected_to class_student_url(membership, class_id: @other_class.id)
    assert_equal @other_class.id, membership.reload.class_id
  end

  test "update without context keeps the original redirect" do
    login(@teacher)
    membership = @school_class.class_students.find_by!(student: @student)

    patch class_student_url(membership), params: { class_student: { student_id: @student.id, class_id: @school_class.id } }

    assert_redirected_to class_student_url(membership)
  end

  test "update with validation error keeps the context" do
    login(@teacher)
    membership = @school_class.class_students.find_by!(student: @student)
    @school_class.class_students.create!(student: @other_student, active: true)

    patch class_student_url(membership), params: { class_id: @school_class.id, class_student: { student_id: @other_student.id, class_id: @school_class.id } }

    assert_response :unprocessable_entity
    assert_select "input[type=hidden][name='class_id'][value='#{@school_class.id}']", count: 1
  end

  test "destroy with context returns to the filtered list and without context to the general list" do
    login(@teacher)
    membership = @school_class.class_students.find_by!(student: @student)
    other_membership = @other_class.class_students.find_by!(student: @other_student)

    delete class_student_url(membership, class_id: @school_class.id)
    assert_redirected_to class_students_url(class_id: @school_class.id)
    assert_not membership.reload.active?

    delete class_student_url(other_membership)
    assert_redirected_to class_students_url
    assert_not other_membership.reload.active?
  end

  test "invalid context on write actions is ignored and never widens access" do
    login(@teacher)
    new_student = create_user(Student, "ctx-invalid-student")

    post class_students_url, params: { class_id: @foreign_class.id, class_student: { student_id: new_student.id, class_id: @school_class.id } }
    membership = ClassStudent.find_by!(student: new_student)
    assert_redirected_to class_student_url(membership)

    delete class_student_url(membership, class_id: @foreign_class.id)
    assert_redirected_to class_students_url

    post class_students_url, params: { class_id: @school_class.id, class_student: { student_id: new_student.id, class_id: @foreign_class.id } }
    assert_redirected_to root_url

    get class_student_url(@foreign_class.class_students.first, class_id: @foreign_class.id)
    assert_redirected_to root_url
  end

  test "index with context shows the class header, count and table" do
    login(@teacher)

    get class_students_url(class_id: @school_class.id)

    assert_select ".enrollment-index-page h1", text: @school_class.name
    assert_select ".enrollment-subtitle", text: "Gerenciamento de alunos da turma"
    assert_select ".enrollment-count", text: /1 matrícula ativa/
    assert_select "a[href='#{school_class_path(@school_class)}']", text: "Voltar à turma", count: 1
    assert_select "table th", count: 2
    assert_select "tbody tr td"
  end

  test "index without context shows the general header and class column" do
    login(@teacher)

    get class_students_url

    assert_select ".enrollment-index-page h1", text: "Matrículas"
    assert_select ".enrollment-subtitle", count: 0
    assert_select "a", text: "Voltar à turma", count: 0
    assert_select "table th", count: 3
  end

  test "index shows friendly empty state without a table" do
    login(@teacher)
    ClassStudent.where(class_id: @school_class.id).update_all(active: false)

    get class_students_url(class_id: @school_class.id)
    assert_select ".enrollment-empty", text: /Esta turma ainda não possui alunos matriculados\./
    assert_select "table", count: 0
    assert_select "a", text: "Nova matrícula", count: 1

    ClassStudent.update_all(active: false)
    get class_students_url
    assert_select ".enrollment-empty", text: /Nenhuma matrícula encontrada\./
    assert_select "table", count: 0
  end

  test "show renders the details card with student and class names" do
    login(@teacher)
    membership = @school_class.class_students.find_by!(student: @student)

    get class_student_url(membership, class_id: @school_class.id)

    assert_response :success
    assert_select ".enrollment-show-page h1", text: "Detalhes da matrícula"
    assert_select ".simple-form-badge", text: "Matrícula"
    assert_select ".enrollment-detail dd", text: @student.name
    assert_select ".enrollment-detail dd", text: @school_class.name

    get class_student_url(membership)

    assert_select ".enrollment-detail dd", text: @student.name
    assert_select "a[href='#{class_students_path}']", text: "Voltar às matrículas", count: 1
    assert_select "a", text: "Voltar à turma", count: 0
  end

  private

  def create_user(klass, prefix)
    id = "#{prefix}-#{SecureRandom.hex(6)}"
    klass.create!(name: id, username: id, email: "#{id}@example.com", password: "secret123")
  end

  def login(user)
    role = user.is_a?(Teacher) ? "teacher" : "student"
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end
end
