require "test_helper"

class ActivityExercisesReorderTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "ro-teacher")
    @school_class = @teacher.school_classes.create!(name: "Turma reorder", active: true)
    @activity = @school_class.activities.create!(title: "Aula reorder", published: true)
  end

  test "normal reorder without hidden links" do
    a, b, c = [ link("a", 1), link("b", 2), link("c", 3) ]

    assert ActivityExercises::Reorder.call(activity: @activity, ordered_ids: [ c.id, a.id, b.id ])

    assert_equal [ c.id, a.id, b.id ], ordered_ids
    assert_equal [ 1, 2, 3 ], positions
  end

  test "hidden link between visible ones moves to the end" do
    a = link("a", 1)
    hidden = link("hidden", 2, exercise_active: false)
    c = link("c", 3)

    assert ActivityExercises::Reorder.call(activity: @activity, ordered_ids: [ c.id, a.id ])

    assert_equal [ c.id, a.id, hidden.id ], ordered_ids
    assert_equal [ 1, 2, 3 ], positions
    assert hidden.reload.active?
    assert hidden.exercise.reload.attributes["active"] == false
  end

  test "hidden link in the last position" do
    a = link("a", 1)
    b = link("b", 2)
    hidden = link("hidden", 3, exercise_active: false)

    assert ActivityExercises::Reorder.call(activity: @activity, ordered_ids: [ b.id, a.id ])

    assert_equal [ b.id, a.id, hidden.id ], ordered_ids
  end

  test "multiple hidden links keep their relative order after visible ones" do
    h1 = link("h1", 1, exercise_active: false)
    a = link("a", 2)
    h2 = link("h2", 3, exercise_active: false)
    b = link("b", 4)
    h3 = link("h3", 6, exercise_active: false)

    assert ActivityExercises::Reorder.call(activity: @activity, ordered_ids: [ b.id, a.id ])

    assert_equal [ b.id, a.id, h1.id, h2.id, h3.id ], ordered_ids
    assert_equal [ 1, 2, 3, 4, 5 ], positions
  end

  test "non consecutive positions are normalized" do
    a = link("a", 5)
    b = link("b", 9)
    hidden = link("hidden", 20, exercise_active: false)

    assert ActivityExercises::Reorder.call(activity: @activity, ordered_ids: [ b.id, a.id ])

    assert_equal [ b.id, a.id, hidden.id ], ordered_ids
    assert_equal [ 1, 2, 3 ], positions
  end

  test "inactive links are untouched" do
    a = link("a", 1)
    b = link("b", 2)
    inactive = link("inactive", 3, link_active: false)

    assert ActivityExercises::Reorder.call(activity: @activity, ordered_ids: [ b.id, a.id ])

    assert_equal 3, inactive.reload.position
    assert_not inactive.active?
  end

  test "invalid lists fail without partial changes" do
    a = link("a", 1)
    b = link("b", 2)
    hidden = link("hidden", 3, exercise_active: false)
    other_activity = @school_class.activities.create!(title: "Outra", published: true)
    foreign = other_activity.activity_exercises.create!(exercise: a.exercise, position: 1, points: 1)

    [ [ a.id, foreign.id ], [ a.id, a.id ], [ a.id, 0 ] ].each do |ids|
      assert_not ActivityExercises::Reorder.call(activity: @activity, ordered_ids: ids)
    end

    assert_equal [ [ a.id, 1 ], [ b.id, 2 ], [ hidden.id, 3 ] ], @activity.activity_exercises.active.order(:position).pluck(:id, :position)
  end

  test "database error rolls back every position" do
    a = link("a", 1)
    b = link("b", 2)
    ActivityExercise.class_eval { before_update :boom_for_test, if: -> { position == 2 && position_changed? } }
    ActivityExercise.send(:define_method, :boom_for_test) { raise ActiveRecord::RecordInvalid, self }

    assert_not ActivityExercises::Reorder.call(activity: @activity, ordered_ids: [ b.id, a.id ])

    assert_equal [ [ a.id, 1 ], [ b.id, 2 ] ], @activity.activity_exercises.active.order(:position).pluck(:id, :position)
  ensure
    ActivityExercise.skip_callback(:update, :before, :boom_for_test, raise: false)
  end

  test "controller reorders with hidden links and still blocks unauthorized users" do
    a = link("a", 1)
    hidden = link("hidden", 2, exercise_active: false)
    c = link("c", 3)
    student = create_user(Student, "ro-student")
    @school_class.class_students.create!(student:, active: true)
    other_teacher = create_user(Teacher, "ro-other")

    login(student)
    patch reorder_activity_exercises_url(@activity), params: { ordered_ids: [ c.id, a.id ] }, as: :json
    assert_not_equal 200, response.status
    delete logout_url
    login(other_teacher)
    patch reorder_activity_exercises_url(@activity), params: { ordered_ids: [ c.id, a.id ] }, as: :json
    assert_not_equal 200, response.status
    assert_equal [ a.id, hidden.id, c.id ], ordered_ids
    delete logout_url

    login(@teacher)
    patch reorder_activity_exercises_url(@activity), params: { ordered_ids: [ c.id, a.id ] }, as: :json
    assert_response :success
    assert_equal [ c.id, a.id, hidden.id ], ordered_ids
  end

  private

  def ordered_ids
    @activity.activity_exercises.active.order(:position).pluck(:id)
  end

  def positions
    @activity.activity_exercises.active.order(:position).pluck(:position)
  end

  def link(title, position, exercise_active: true, link_active: true)
    exercise = @teacher.exercises.create!(title:, exercise_type: :quiz, active: exercise_active, object: {
      "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ]
    })
    @activity.activity_exercises.create!(exercise:, position:, points: 1, active: link_active)
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
