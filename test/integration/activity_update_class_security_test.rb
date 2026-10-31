require "test_helper"

class ActivityUpdateClassSecurityTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "upd-teacher")
    @class_a = @teacher.school_classes.create!(name: "Turma A", active: true)
    @class_b = @teacher.school_classes.create!(name: "Turma B", active: true)
    @inactive = @teacher.school_classes.create!(name: "Turma inativa", active: false)
    @other_teacher = create_user(Teacher, "upd-other")
    @foreign = @other_teacher.school_classes.create!(name: "Turma alheia", active: true)
    @activity = @class_a.activities.create!(title: "Aula original", published: false)
    @student = create_user(Student, "upd-student")
    @class_a.class_students.create!(student: @student, active: true)
  end

  test "teacher updates own activity keeping the class" do
    login(@teacher)

    patch activity_url(@activity), params: { activity: { class_id: @class_a.id, title: "Novo título", published: "1" } }

    assert_redirected_to activity_url(@activity)
    @activity.reload
    assert_equal "Novo título", @activity.title
    assert_equal @class_a.id, @activity.class_id
    assert @activity.published?
  end

  test "update without class_id keeps the class" do
    login(@teacher)

    patch activity_url(@activity), params: { activity: { title: "Só título" } }

    assert_redirected_to activity_url(@activity)
    assert_equal @class_a.id, @activity.reload.class_id
  end

  test "teacher moves the activity to another own active class" do
    login(@teacher)

    patch activity_url(@activity), params: { activity: { class_id: @class_b.id, title: "Movida" } }

    assert_redirected_to activity_url(@activity)
    assert_equal @class_b.id, @activity.reload.class_id
  end

  test "teacher cannot move the activity to foreign, inactive or missing classes" do
    login(@teacher)

    [ @foreign.id, @inactive.id, 0, "" ].each do |id|
      patch activity_url(@activity), params: { activity: { class_id: id, title: "Alterada", published: "1" } }

      assert_response :unprocessable_entity
      assert_not_includes response.body, @foreign.name
      @activity.reload
      assert_equal @class_a.id, @activity.class_id
      assert_equal "Aula original", @activity.title
      assert_not @activity.published?
    end
  end

  test "invalid update does not change persisted data" do
    login(@teacher)

    patch activity_url(@activity), params: { activity: { class_id: @class_b.id, title: "" } }

    assert_response :unprocessable_entity
    @activity.reload
    assert_equal "Aula original", @activity.title
    assert_equal @class_a.id, @activity.class_id
  end

  test "student cannot update activities directly" do
    login(@student)

    patch activity_url(@activity), params: { activity: { title: "Hack", class_id: @class_b.id } }

    assert_redirected_to root_url
    assert_equal "Aula original", @activity.reload.title
    assert_equal @class_a.id, @activity.class_id
  end

  test "other teacher cannot update the activity" do
    login(@other_teacher)

    patch activity_url(@activity), params: { activity: { title: "Hack", class_id: @foreign.id } }

    assert_redirected_to root_url
    assert_equal @class_a.id, @activity.reload.class_id
  end

  test "create and edit flows still work" do
    login(@teacher)

    get edit_activity_url(@activity)
    assert_response :success

    assert_difference("Activity.count", 1) do
      post activities_url, params: { activity: { class_id: @class_b.id, title: "Criada" } }
    end
    assert_equal @class_b.id, Activity.order(:id).last.class_id
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
