require "test_helper"

class ActivityExerciseDuplicateTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  MESSAGE = "Este exercício já está associado a esta aula.".freeze

  setup do
    @teacher = create_user(Teacher, "aed-teacher")
    @other_teacher = create_user(Teacher, "aed-other")
    @activity = create_activity(@teacher, "Aula A")
    @activity_two = create_activity(@teacher, "Aula B")
    @exercise = create_exercise(@teacher, "Exercício 1")
    @exercise_two = create_exercise(@teacher, "Exercício 2")
    login(@teacher)
  end

  test "first association is accepted" do
    assert_difference -> { @activity.activity_exercises.active.count } => 1 do
      post activity_exercises_url, params: { activity_exercise: { activity_id: @activity.id, exercise_id: @exercise.id, points: 3 } }
    end
    assert_redirected_to activity_url(@activity)
  end

  test "same exercise cannot be associated twice to the same activity" do
    link = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 5)

    assert_no_difference -> { ActivityExercise.count } do
      post activity_exercises_url, params: { activity_exercise: { activity_id: @activity.id, exercise_id: @exercise.id, points: 9 } }
    end
    assert_redirected_to activity_url(@activity)
    assert_equal MESSAGE, flash[:alert]
    assert_equal [ @activity.id, @exercise.id, 1, 5, true ], snapshot(link)
  end

  test "same exercise can be associated to another activity of the same teacher" do
    @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 5)

    assert_difference -> { @activity_two.activity_exercises.active.count } => 1 do
      post activity_exercises_url, params: { activity_exercise: { activity_id: @activity_two.id, exercise_id: @exercise.id, points: 2 } }
    end
    assert_nil flash[:alert]
  end

  test "update cannot turn a link into a duplicate of another active link" do
    @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 5)
    other = @activity.activity_exercises.create!(exercise: @exercise_two, position: 2, points: 6)

    patch activity_exercise_url(other), params: { activity_exercise: { exercise_id: @exercise.id, position: 7, points: 99 } }

    assert_response :unprocessable_entity
    assert_includes response.body, MESSAGE
    assert_equal [ @activity.id, @exercise_two.id, 2, 6, true ], snapshot(other)
  end

  test "update cannot move a link into an activity that already has the exercise" do
    @activity_two.activity_exercises.create!(exercise: @exercise, position: 1, points: 5)
    link = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 4)

    patch activity_exercise_url(link), params: { activity_exercise: { activity_id: @activity_two.id, points: 50 } }

    assert_response :unprocessable_entity
    assert_equal [ @activity.id, @exercise.id, 1, 4, true ], snapshot(link)
  end

  test "updating position and points of a link keeps it valid" do
    link = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 5)

    patch activity_exercise_url(link), params: { activity_exercise: { exercise_id: @exercise.id, position: 3, points: 8 } }

    assert_redirected_to activity_exercise_url(link)
    assert_equal [ @activity.id, @exercise.id, 3, 8, true ], snapshot(link)
  end

  test "inactive link does not block a new association" do
    old = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 5)
    old.update!(active: false)

    assert_difference -> { @activity.activity_exercises.active.count } => 1 do
      post activity_exercises_url, params: { activity_exercise: { activity_id: @activity.id, exercise_id: @exercise.id, points: 4 } }
    end
    assert_equal [ @activity.id, @exercise.id, 1, 5, false ], snapshot(old)
  end

  test "activity page offers only exercises not yet linked" do
    @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 5)

    get activity_url(@activity)

    assert_select "select[name='activity_exercise[exercise_id]'] option[value='#{@exercise_two.id}']"
    assert_select "select[name='activity_exercise[exercise_id]'] option[value='#{@exercise.id}']", count: 0
  end

  test "activity page offers an exercise again after its link is removed" do
    link = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 5)
    link.update!(active: false)

    get activity_url(@activity)

    assert_select "select[name='activity_exercise[exercise_id]'] option[value='#{@exercise.id}']"
  end

  test "foreign teacher cannot create duplicates or links in this activity" do
    @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 5)
    delete logout_url
    login(@other_teacher)

    assert_no_difference -> { ActivityExercise.count } do
      post activity_exercises_url, params: { activity_exercise: { activity_id: @activity.id, exercise_id: @exercise.id, points: 1 } }
    end
    assert_redirected_to activities_url
  end

  test "student cannot create links" do
    student = create_user(Student, "aed-student")
    @activity.school_class.class_students.create!(student:, active: true)
    delete logout_url
    login(student)

    assert_no_difference -> { ActivityExercise.count } do
      post activity_exercises_url, params: { activity_exercise: { activity_id: @activity.id, exercise_id: @exercise.id, points: 1 } }
    end
    assert_redirected_to root_url
  end

  test "reordering still works" do
    first = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 5)
    second = @activity.activity_exercises.create!(exercise: @exercise_two, position: 2, points: 5)

    patch reorder_activity_exercises_url(@activity), params: { ordered_ids: [ second.id, first.id ] }, as: :json

    assert_response :success
    assert_equal [ second.id, first.id ], @activity.activity_exercises.active.order(:position).pluck(:id)
  end

  private

  def snapshot(record)
    record.reload.attributes.values_at("activity_id", "exercise_id", "position", "points", "active")
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
