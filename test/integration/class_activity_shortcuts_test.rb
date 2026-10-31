require "test_helper"

class ClassActivityShortcutsTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "short-teacher")
    @school_class = @teacher.school_classes.create!(name: "Turma atalhos", active: true)
    @other_class = @teacher.school_classes.create!(name: "Outra turma", active: true)
    @student = create_user(Student, "short-student")
    @school_class.class_students.create!(student: @student, active: true)
    @other_teacher = create_user(Teacher, "short-other")
    @foreign_class = @other_teacher.school_classes.create!(name: "Turma alheia", active: true)
    @inactive_class = @teacher.school_classes.create!(name: "Turma inativa", active: false)
  end

  test "teacher sees the shortcuts on the class page and student does not" do
    login(@teacher)
    get school_class_url(@school_class)
    assert_select "a[href='#{new_activity_path(class_id: @school_class.id)}']", text: "Nova aula", count: 1
    assert_select "a[href='#{class_students_path}']", text: "Gerenciar alunos", count: 1
    delete logout_url

    login(@student)
    get school_class_url(@school_class)
    assert_response :success
    assert_select "a", text: "Nova aula", count: 0
    assert_select "a", text: "Gerenciar alunos", count: 0
  end

  test "new activity preselects the source class without creating anything" do
    login(@teacher)

    assert_no_difference("Activity.count") { get new_activity_url(class_id: @school_class.id) }

    assert_response :success
    assert_select "select[name='activity[class_id]'] option[selected][value='#{@school_class.id}']", count: 1
  end

  test "global new activity has no preselected class" do
    login(@teacher)

    get new_activity_url

    assert_response :success
    assert_select "select[name='activity[class_id]'] option[selected]", count: 0
  end

  test "invalid, inactive or foreign source classes are ignored" do
    login(@teacher)

    [ 0, @inactive_class.id, @foreign_class.id ].each do |id|
      get new_activity_url(class_id: id)
      assert_response :success
      assert_select "select[name='activity[class_id]'] option[selected]", count: 0
      assert_not_includes response.body, @foreign_class.name
    end
  end

  test "teacher creates an activity from the own class" do
    login(@teacher)

    assert_difference("Activity.count", 1) do
      post activities_url, params: { activity: { class_id: @school_class.id, title: "Aula atalho", published: "0" } }
    end

    activity = Activity.order(:id).last
    assert_redirected_to activity_url(activity)
    assert_equal @school_class.id, activity.class_id
    assert_equal @teacher.id, activity.teacher_id
    assert_not activity.published?
  end

  test "validation error keeps the authorized class selected" do
    login(@teacher)

    assert_no_difference("Activity.count") do
      post activities_url, params: { activity: { class_id: @school_class.id, title: "" } }
    end

    assert_response :unprocessable_entity
    assert_select "select[name='activity[class_id]'] option[selected][value='#{@school_class.id}']", count: 1
  end

  test "creation cannot use foreign, inactive or missing classes" do
    login(@teacher)

    [ @foreign_class.id, @inactive_class.id, 0 ].each do |id|
      assert_no_difference("Activity.count") do
        post activities_url, params: { activity: { class_id: id, title: "Aula indevida" } }
      end
      assert_response :unprocessable_entity
      assert_select "select[name='activity[class_id]'] option[selected]", count: 0
    end
  end

  test "student cannot open the form or create activities" do
    login(@student)

    get new_activity_url(class_id: @school_class.id)
    assert_redirected_to root_url

    assert_no_difference("Activity.count") do
      post activities_url, params: { activity: { class_id: @school_class.id, title: "Aula do aluno" } }
    end
    assert_redirected_to root_url
  end

  test "manage students link opens the existing enrollment flow scoped to the teacher" do
    login(@teacher)
    @school_class.class_students.find_by!(student: @student)
    foreign_student = create_user(Student, "short-foreign-student")
    @foreign_class.class_students.create!(student: foreign_student, active: true)

    get class_students_url

    assert_response :success
    assert_select "td", text: @student.name
    assert_select "td", text: foreign_student.name, count: 0
    delete logout_url

    login(@student)
    get class_students_url
    assert_redirected_to root_url
  end

  test "other teacher does not see the shortcuts on a foreign class" do
    login(@other_teacher)

    get school_class_url(@school_class)

    assert_redirected_to root_url
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
