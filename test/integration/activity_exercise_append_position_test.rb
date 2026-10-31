require "test_helper"

class ActivityExerciseAppendPositionTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "aap-teacher")
    @other = create_user(Teacher, "aap-other")
    @activity = create_activity(@teacher, "Aula")
    @exercises = (1..9).map { |i| create_exercise(@teacher, "Ex #{i}") }
    login(@teacher)
  end

  test "association without hidden links goes to the end" do
    link_all(@exercises[0, 3])

    add(@exercises[3])

    assert_redirected_to activity_url(@activity)
    assert_equal [ 1, 2, 3, 4 ], visible_positions
  end

  test "hidden links at the end stay after the new visible one" do
    links = link_all(@exercises[0, 8])
    hide(@exercises[6], @exercises[7])

    add(@exercises[8])

    assert_equal [ 1, 2, 3, 4, 5, 6, 7 ], visible_positions
    assert_equal @exercises[8].id, visible_links.last.exercise_id
    assert_equal [ links[6].id, links[7].id ], hidden_links.pluck(:id)
    assert_equal [ 8, 9 ], hidden_links.pluck(:position)
    get activity_url(@activity)
    assert_equal %w[1 2 3 4 5 6 7], css_select("span[data-position]").map(&:text)
  end

  test "hidden link in the middle is moved after the visible ones keeping relative order" do
    links = link_all(@exercises[0, 6])
    hide(@exercises[1], @exercises[3])

    add(@exercises[6])

    assert_equal [ 1, 2, 3, 4, 5 ], visible_positions
    assert_equal [ links[0].id, links[2].id, links[4].id, links[5].id ], visible_links.first(4).pluck(:id)
    assert_equal [ links[1].id, links[3].id ], hidden_links.pluck(:id)
    assert_equal [ 6, 7 ], hidden_links.pluck(:position)
  end

  test "inactive links and existing data are preserved" do
    links = link_all(@exercises[0, 3], points: 7)
    links[1].update!(active: false)
    inactive_before = links[1].reload.attributes
    hide(@exercises[2])

    assert_difference -> { ActivityExercise.count } => 1 do
      add(@exercises[3], points: 4)
    end

    assert_equal inactive_before, links[1].reload.attributes
    assert_equal [ links[0].id, @activity.activity_exercises.active.find_by!(exercise: @exercises[3]).id ], visible_links.pluck(:id)
    assert_equal [ 7, 7, 7 ], [ links[0], links[1], links[2] ].map { |l| l.reload.points }
    assert_equal 4, visible_links.last.points
    assert_equal [ @exercises[0].id, @exercises[2].id ].sort, [ links[0], links[2] ].map(&:exercise_id).sort
    assert_equal [ true, false, true ], [ links[0], links[1], links[2] ].map { |l| l.reload.active }
  end

  test "manual reorder still works after a new association" do
    link_all(@exercises[0, 2])
    hide(@exercises[1])
    add(@exercises[2])
    ids = visible_links.pluck(:id)

    patch reorder_activity_exercises_url(@activity), params: { ordered_ids: ids.reverse }, as: :json

    assert_response :success
    assert_equal ids.reverse, visible_links.pluck(:id)
    assert_equal [ 1, 2 ], visible_positions
  end

  test "duplicate association is rejected without changing positions" do
    link_all(@exercises[0, 3])
    hide(@exercises[2])
    before = snapshot

    assert_no_difference -> { ActivityExercise.count } do
      add(@exercises[0])
    end

    assert_equal "Este exercício já está associado a esta aula.", flash[:alert]
    assert_equal before, snapshot
  end

  test "unauthorized association does not change positions" do
    link_all(@exercises[0, 3])
    hide(@exercises[2])
    before = snapshot
    foreign = create_exercise(@other, "Alheio")

    assert_no_difference -> { ActivityExercise.count } do
      add(foreign)
    end

    assert_redirected_to activities_url
    assert_equal before, snapshot
  end

  test "persistence failure rolls everything back" do
    link_all(@exercises[0, 3])
    hide(@exercises[2])
    before = snapshot
    link = @activity.activity_exercises.build(exercise: @exercises[3], points: 1)

    result = with_override(ActivityExercises::Reorder, :call, ->(**) { false }) { ActivityExercises::Append.call(link) }

    assert_not result
    assert_not link.persisted?
    assert_equal before, snapshot
  end

  test "position conflict is reported without raising" do
    link_all(@exercises[0, 2])
    link = @activity.activity_exercises.build(exercise: @exercises[3], points: 1)
    before = snapshot

    result = with_override(link, :save, ->(*) { raise ActiveRecord::RecordNotUnique, "conflict" }) { ActivityExercises::Append.call(link) }

    assert_not result
    assert link.errors[:base].any?
    assert_equal before, snapshot
  end

  test "new link respects the partial unique index on active positions" do
    link_all(@exercises[0, 3])
    hide(@exercises[0])

    add(@exercises[3])

    positions = @activity.activity_exercises.active.pluck(:position)
    assert_equal positions.uniq.size, positions.size
    assert_equal [ 1, 2, 3, 4 ], positions.sort
  end

  private

  def with_override(target, name, implementation)
    original = target.method(name)
    target.define_singleton_method(name, &implementation)
    yield
  ensure
    target.define_singleton_method(name, original)
  end

  def add(exercise, points: 1)
    post activity_exercises_url, params: { activity_exercise: { activity_id: @activity.id, exercise_id: exercise.id, points: } }
  end

  def link_all(exercises, points: 1)
    exercises.each_with_index.map { |e, i| @activity.activity_exercises.create!(exercise: e, position: i + 1, points:) }
  end

  def hide(*exercises)
    exercises.each { |e| e.update!(active: false) }
  end

  def visible_links
    @activity.activity_exercises.active.joins(:exercise).merge(Exercise.active).order(:position)
  end

  def hidden_links
    @activity.activity_exercises.active.joins(:exercise).merge(Exercise.where(active: false)).order(:position)
  end

  def visible_positions
    visible_links.pluck(:position)
  end

  def snapshot
    ActivityExercise.order(:id).pluck(:id, :activity_id, :exercise_id, :position, :points, :active)
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
    post login_url, params: { role: "teacher", username: user.username, password: "secret123" }
  end
end
