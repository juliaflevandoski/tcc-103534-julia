require "test_helper"

class ActivityExerciseUpdateSecurityTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "aeu-teacher")
    @other_teacher = create_user(Teacher, "aeu-other")
    @activity = create_activity(@teacher, "Aula própria")
    @own_activity_two = create_activity(@teacher, "Segunda aula própria")
    @exercise = create_exercise(@teacher, "Exercício próprio")
    @own_exercise_two = create_exercise(@teacher, "Segundo exercício próprio")
    @foreign_activity = create_activity(@other_teacher, "Aula alheia")
    @foreign_exercise = create_exercise(@other_teacher, "Exercício alheio")
    @link = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 5)
    @foreign_link = @foreign_activity.activity_exercises.create!(exercise: @foreign_exercise, position: 1, points: 7)
    login(@teacher)
  end

  test "teacher updates points and position of own link keeping its targets" do
    patch activity_exercise_url(@link), params: { activity_exercise: { activity_id: @activity.id, exercise_id: @exercise.id, position: 4, points: 9 } }

    assert_redirected_to activity_exercise_url(@link)
    assert_equal [ @activity.id, @exercise.id, 4, 9 ], snapshot(@link)
  end

  test "teacher moves link to another own active activity and exercise" do
    patch activity_exercise_url(@link), params: { activity_exercise: { activity_id: @own_activity_two.id, exercise_id: @own_exercise_two.id } }

    assert_redirected_to activity_exercise_url(@link)
    assert_equal [ @own_activity_two.id, @own_exercise_two.id, 1, 5 ], snapshot(@link)
  end

  test "teacher cannot point the link to a foreign activity" do
    assert_no_change_for(activity_id: @foreign_activity.id)
  end

  test "teacher cannot point the link to a foreign exercise" do
    assert_no_change_for(exercise_id: @foreign_exercise.id)
  end

  test "teacher cannot point the link to a foreign activity and exercise" do
    assert_no_change_for(activity_id: @foreign_activity.id, exercise_id: @foreign_exercise.id)
  end

  test "foreign target is rejected even when other fields are valid" do
    assert_no_change_for(activity_id: @foreign_activity.id, position: 8, points: 99)
  end

  test "inactive targets are rejected" do
    inactive_activity = create_activity(@teacher, "Aula inativa")
    inactive_activity.update!(active: false)
    inactive_exercise = create_exercise(@teacher, "Exercício inativo")
    inactive_exercise.update!(active: false)

    assert_no_change_for(activity_id: inactive_activity.id)
    assert_no_change_for(exercise_id: inactive_exercise.id)
  end

  test "missing or invalid ids do not change the link partially" do
    [ 0, 999_999, "abc", "" ].each do |bad_id|
      assert_no_change_for(activity_id: bad_id, points: 50)
      assert_no_change_for(exercise_id: bad_id, position: 12)
    end
  end

  test "teacher cannot modify a link owned by another teacher" do
    patch activity_exercise_url(@foreign_link), params: { activity_exercise: { activity_id: @activity.id, exercise_id: @exercise.id, points: 1 } }

    assert_redirected_to root_url
    assert_equal [ @foreign_activity.id, @foreign_exercise.id, 1, 7 ], snapshot(@foreign_link)
  end

  test "student cannot update a link" do
    student = create_user(Student, "aeu-student")
    @activity.school_class.class_students.create!(student:, active: true)
    delete logout_url
    login(student)

    patch activity_exercise_url(@link), params: { activity_exercise: { activity_id: @own_activity_two.id, points: 1 } }

    assert_redirected_to root_url
    assert_equal [ @activity.id, @exercise.id, 1, 5 ], snapshot(@link)
  end

  test "legitimate association and reordering still work" do
    post activity_exercises_url, params: { activity_exercise: { activity_id: @activity.id, exercise_id: @own_exercise_two.id, points: 3 } }
    assert_redirected_to activity_url(@activity)
    second = @activity.activity_exercises.active.find_by!(exercise: @own_exercise_two)

    patch reorder_activity_exercises_url(@activity), params: { ordered_ids: [ second.id, @link.id ] }, as: :json

    assert_response :success
    assert_equal [ second.id, @link.id ], @activity.activity_exercises.active.order(:position).pluck(:id)
  end

  private

  def assert_no_change_for(attributes)
    before = snapshot(@link)
    patch activity_exercise_url(@link), params: { activity_exercise: attributes }

    assert_redirected_to activities_url
    assert_equal "Aula ou exercício inválido.", flash[:alert]
    assert_equal before, snapshot(@link)
  end

  def snapshot(record)
    record.reload.attributes.values_at("activity_id", "exercise_id", "position", "points")
  end

  def create_activity(teacher, title)
    school_class = teacher.school_classes.create!(name: "Turma #{title}", active: true)
    school_class.activities.create!(title:, published: true)
  end

  def create_exercise(teacher, title)
    teacher.exercises.create!(title:, exercise_type: :quiz, object: {
      "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ]
    })
  end

  def create_user(klass, prefix)
    id = "#{prefix}-#{SecureRandom.hex(6)}"
    klass.create!(name: id, username: id, email: "#{id}@example.com", password: "secret123")
  end

  def login(user)
    role = user.is_a?(Teacher) ? "teacher" : "student"
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end
end
