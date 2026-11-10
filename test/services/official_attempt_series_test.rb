require "test_helper"

class OfficialAttemptSeriesTest < ActiveSupport::TestCase
  RIGHT = { "0" => "a", "1" => "42" }.freeze
  WRONG = { "0" => "b", "1" => "0" }.freeze
  PARTIAL = { "0" => "a", "1" => "0" }.freeze

  W1 = Date.new(2026, 1, 5)
  W2 = Date.new(2026, 1, 12)
  W3 = Date.new(2026, 1, 19)
  W4 = Date.new(2026, 1, 26)

  setup do
    @teacher = create_teacher("serprof")
    @s1 = create_student("sers1")
    @s2 = create_student("sers2")
    @class_a = @teacher.school_classes.create!(name: "Alfa", active: true)
    @class_b = @teacher.school_classes.create!(name: "Beta", active: true)
    [ @class_a, @class_b ].each do |school_class|
      school_class.class_students.create!(student: @s1, active: true)
      school_class.class_students.create!(student: @s2, active: true)
    end
    @lesson_a1 = @class_a.activities.create!(title: "A1", published: true)
    @lesson_a2 = @class_a.activities.create!(title: "A2", published: true)
    @lesson_b = @class_b.activities.create!(title: "B1", published: true)
    @a1_x = link(@lesson_a1, "X")
    @a1_y = link(@lesson_a1, "Y")
    @a2_z = link(@lesson_a2, "Z")
    @b_w = link(@lesson_b, "W")

    submit(@a1_x, @s1, RIGHT, at(W1, 1))
    submit(@a1_x, @s2, RIGHT, at(W1, 2)).update_columns(active: false)
    submit(@a1_x, @s1, WRONG, at(W2, 1)) # posterior, não oficial
    submit(@a1_y, @s1, WRONG, at(W2, 2))
    submit(@a2_z, @s2, RIGHT, at(W4, 1))
    submit(@b_w, @s1, RIGHT, at(W1, 3))
    submit(@b_w, @s2, PARTIAL, at(W2, 3))
  end

  test "groups official attempts by week and fills empty weeks without inventing grades" do
    weeks = OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ]).weeks

    assert_equal [ W1, W2, W3, W4 ], weeks.map(&:week_start)
    assert_equal [ 2, 1, 0, 1 ], weeks.map(&:attempts_count)
    assert_equal [ 2, 3, 3, 4 ], weeks.map(&:cumulative_attempts_count)
    assert_equal [ 2, 1, 0, 1 ], weeks.map(&:distinct_students_count)
    assert_equal [ 100.0, 0.0, nil, 100.0 ], weeks.map(&:average)
    assert_equal [ 2, 1, 0, 1 ], weeks.map(&:rated_count)
    assert_nil weeks[2].average
  end

  test "cumulative average pools all grades instead of averaging weekly averages" do
    weeks = OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ]).weeks

    assert_in_delta 100.0, weeks[0].cumulative_average
    assert_in_delta 200.0 / 3, weeks[1].cumulative_average
    assert_in_delta 200.0 / 3, weeks[2].cumulative_average, 0.0001
    assert_in_delta 300.0 / 4, weeks[3].cumulative_average
  end

  test "later attempts are ignored and officially valid attempts deactivated later still count" do
    weeks = OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], student: @s2).weeks

    assert_equal [ 1, 0, 0, 1 ], weeks.map(&:attempts_count)
    assert_equal [ 100.0, nil, nil, 100.0 ], weeks.map(&:average)
    s1_weeks = OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], student: @s1).weeks
    assert_equal [ 1, 1 ], s1_weeks.first(2).map(&:attempts_count)
    assert_equal [ 100.0, 0.0 ], s1_weeks.first(2).map(&:average)
  end

  test "several classes share one axis and the overall series pools every class" do
    result = OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a, @class_b ])
    partial = ActivityResults.attempt_percentage(attempt: ExerciseAttempt.where(student: @s2, activity_exercise: @b_w).first)

    assert_equal [ W1, W2, W3, W4 ], result.weeks.map(&:week_start)
    assert_equal [ [ @class_a, [ W1, W2, W3, W4 ] ], [ @class_b, [ W1, W2, W3, W4 ] ] ],
                 result.classes.map { |series| [ series.school_class, series.weeks.map(&:week_start) ] }
    assert_equal [ 3, 2, 0, 1 ], result.weeks.map(&:attempts_count)
    assert_equal [ 2, 2, 0, 1 ], result.weeks.map(&:distinct_students_count)
    assert_in_delta 100.0, result.weeks[0].average
    assert_in_delta (0.0 + partial) / 2, result.weeks[1].average

    beta = result.classes.last.weeks
    assert_equal [ 1, 1, 0, 0 ], beta.map(&:attempts_count)
    assert_equal [ 100.0, partial, nil, nil ], beta.map(&:average)
    assert_in_delta (100.0 + partial) / 2, beta[3].cumulative_average
  end

  test "reused exercises count once per lesson link" do
    reused = @lesson_a2.activity_exercises.create!(exercise: @a1_x.exercise, position: 2, points: 10)
    submit(reused, @s1, RIGHT, at(W3, 1))

    weeks = OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], student: @s1).weeks

    assert_equal 1, weeks[2].attempts_count
    assert_equal 3, weeks.last.cumulative_attempts_count
  end

  test "a class with no official attempts has no weeks" do
    empty = @teacher.school_classes.create!(name: "Vazia", active: true)
    empty.class_students.create!(student: @s1, active: true)
    result = OfficialAttemptSeries.call(user: @teacher, school_classes: [ empty ])

    assert_equal [], result.weeks
    assert_equal [], result.classes.first.weeks
  end

  test "ineligible records are excluded" do
    @class_a.class_students.find_by!(student: @s2).update!(active: false)
    @a1_y.update!(active: false)
    @a2_z.update!(active: false)
    draft = @class_a.activities.create!(title: "Rascunho", published: false)
    submit(link(draft, "D"), @s1, RIGHT, at(W3, 1))
    inactive_lesson = @class_a.activities.create!(title: "Inativa", published: true, active: false)
    submit(link(inactive_lesson, "I"), @s1, RIGHT, at(W3, 2))

    student_weeks = OfficialAttemptSeries.call(user: @s1, school_classes: [ @class_a ]).weeks
    teacher_weeks = OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ]).weeks

    assert_equal [ W1 ], student_weeks.map(&:week_start)
    assert_equal 1, student_weeks.sum(&:attempts_count)
    # o professor vê rascunhos (como no TeacherDashboard), mas não aulas inativas nem alunos sem matrícula ativa
    assert_equal [ W1, W2, W3 ], teacher_weeks.map(&:week_start)
    assert_equal [ 1, 0, 1 ], teacher_weeks.map(&:attempts_count)
  end

  test "student series only contains the student's own attempts and matches the student dashboard" do
    result = OfficialAttemptSeries.call(user: @s1, school_classes: [ @class_a, @class_b ])
    dashboard = StudentDashboard.call(student: @s1, school_classes: [ @class_a, @class_b ])

    assert_equal [ 1, 1 ], result.weeks.map(&:distinct_students_count)
    assert_equal dashboard.exercises_completed, result.weeks.last.cumulative_attempts_count
    assert_in_delta dashboard.average, result.weeks.last.cumulative_average
  end

  test "weeks follow the application time zone" do
    other = ExerciseAttempt.where(student: @s2, activity_exercise: @a2_z).first
    other.update_columns(created_at: Time.utc(2026, 1, 26, 1)) # segunda 01:00 UTC

    utc_weeks = OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], student: @s2).weeks
    brasilia_weeks = Time.use_zone("Brasilia") { OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], student: @s2).weeks }

    assert_equal W4, utc_weeks.last.week_start
    assert_equal W3, brasilia_weeks.last.week_start # domingo 22:00 em Brasília
  end

  test "authorization rejects foreign classes, other students and unenrolled access" do
    other_teacher = create_teacher("serforeign")
    foreign = other_teacher.school_classes.create!(name: "Alheia", active: true)
    outsider = create_student("seroutsider")
    left = @teacher.school_classes.create!(name: "Saiu", active: true)
    left.class_students.create!(student: @s1, active: false)
    inactive = @teacher.school_classes.create!(name: "Inativa", active: false)
    inactive.class_students.create!(student: @s1, active: true)

    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: @teacher, school_classes: [ foreign ]) }
    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: other_teacher, school_classes: [ @class_a ]) }
    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: @teacher, school_classes: [ inactive ]) }
    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], student: outsider) }
    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: @s1, school_classes: [ foreign ]) }
    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: @s1, school_classes: [ left ]) }
    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: @s1, school_classes: [ inactive ]) }
    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: @s1, school_classes: [ @class_a ], student: @s2) }
    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: outsider, school_classes: [ @class_a ]) }
  end

  test "activity filter scopes all weekly metrics before constructing the axis" do
    result = OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], activity: @lesson_a1)

    assert_equal [ W1, W2 ], result.weeks.map(&:week_start)
    assert_equal [ 2, 1 ], result.weeks.map(&:attempts_count)
    assert_equal [ 2, 3 ], result.weeks.map(&:cumulative_attempts_count)
    assert_equal [ 2, 1 ], result.weeks.map(&:distinct_students_count)
    assert_equal [ 100.0, 0.0 ], result.weeks.map(&:average)
    assert_in_delta 200.0 / 3, result.weeks.last.cumulative_average
  end

  test "activity exercise filter works with or without its activity" do
    with_activity = OfficialAttemptSeries.call(
      user: @teacher, school_classes: [ @class_a ], activity: @lesson_a1, activity_exercise: @a1_x
    )
    without_activity = OfficialAttemptSeries.call(
      user: @teacher, school_classes: [ @class_a ], activity_exercise: @a1_x
    )

    assert_equal with_activity.weeks, without_activity.weeks
    assert_equal [ W1 ], without_activity.weeks.map(&:week_start)
    assert_equal [ 2 ], without_activity.weeks.map(&:attempts_count)
    assert_equal [ 2 ], without_activity.weeks.map(&:distinct_students_count)
    assert_equal [ 100.0 ], without_activity.weeks.map(&:average)
  end

  test "student activity and activity exercise filters combine" do
    result = OfficialAttemptSeries.call(
      user: @teacher, school_classes: [ @class_a ],
      student: @s1, activity: @lesson_a1, activity_exercise: @a1_y
    )

    assert_equal [ W2 ], result.weeks.map(&:week_start)
    assert_equal [ 1 ], result.weeks.map(&:attempts_count)
    assert_equal [ 1 ], result.weeks.map(&:distinct_students_count)
    assert_equal [ 0.0 ], result.weeks.map(&:average)
    assert_equal [ 0.0 ], result.weeks.map(&:cumulative_average)
  end

  test "exercise filter distinguishes the same exercise in different lessons" do
    reused = @lesson_a2.activity_exercises.create!(exercise: @a1_x.exercise, position: 2, points: 10)
    submit(reused, @s1, WRONG, at(W3, 1))

    original = OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], activity_exercise: @a1_x)
    other_link = OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], activity_exercise: reused)

    assert_equal [ W1 ], original.weeks.map(&:week_start)
    assert_equal [ W3 ], other_link.weeks.map(&:week_start)
    assert_equal [ 0.0 ], other_link.weeks.map(&:average)
  end

  test "filtered series fills empty weeks and empty selections have no axis" do
    submit(@a1_y, @s2, PARTIAL, at(W4, 1))
    result = OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], activity_exercise: @a1_y)
    empty_link = link(@lesson_a1, "Sem tentativas")
    empty = OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], activity_exercise: empty_link)

    assert_equal [ W2, W3, W4 ], result.weeks.map(&:week_start)
    assert_equal [ 1, 0, 1 ], result.weeks.map(&:attempts_count)
    assert_equal [ 1, 1, 2 ], result.weeks.map(&:cumulative_attempts_count)
    assert_equal [ 1, 0, 1 ], result.weeks.map(&:distinct_students_count)
    assert_equal [ 0.0, nil, 50.0 ], result.weeks.map(&:average)
    assert_equal [ 0.0, 0.0, 25.0 ], result.weeks.map(&:cumulative_average)
    assert_empty empty.weeks
    assert_empty empty.classes.first.weeks
  end

  test "filtered multi class results share an axis and leave other classes empty" do
    result = OfficialAttemptSeries.call(
      user: @teacher, school_classes: [ @class_a, @class_b ], activity: @lesson_a1
    )

    assert_equal [ W1, W2 ], result.weeks.map(&:week_start)
    assert_equal [ 0, 0 ], result.classes.last.weeks.map(&:attempts_count)
    assert_equal [ nil, nil ], result.classes.last.weeks.map(&:average)
  end

  test "rejects inactive activity link and exercise including an inactive parent activity" do
    @lesson_a1.update!(active: false)
    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], activity: @lesson_a1) }
    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], activity_exercise: @a1_x) }
    @lesson_a1.update!(active: true)
    @a1_x.update!(active: false)
    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], activity_exercise: @a1_x) }
    @a1_x.update!(active: true)
    @a1_x.exercise.update!(active: false)
    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], activity_exercise: @a1_x) }
  end

  test "rejects filters from another class lesson or teacher" do
    other_teacher = create_teacher("serfilterforeign")
    foreign_class = other_teacher.school_classes.create!(name: "Alheia", active: true)
    foreign_lesson = foreign_class.activities.create!(title: "Alheia", published: true)
    foreign_link = link(foreign_lesson, "Alheio")

    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], activity: @lesson_b) }
    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], activity_exercise: @b_w) }
    assert_raises(ArgumentError) do
      OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], activity: @lesson_a1, activity_exercise: @a2_z)
    end
    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], activity: foreign_lesson) }
    assert_raises(ArgumentError) { OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], activity_exercise: foreign_link) }
  end

  test "student filters preserve published only eligibility and unfiltered series" do
    draft = @class_a.activities.create!(title: "Rascunho", published: false)
    draft_link = link(draft, "Rascunho")
    submit(draft_link, @s1, RIGHT, at(W3, 1))

    student_unfiltered = OfficialAttemptSeries.call(user: @s1, school_classes: [ @class_a ])
    student_filtered = OfficialAttemptSeries.call(user: @s1, school_classes: [ @class_a ], activity: @lesson_a1)
    student_draft = OfficialAttemptSeries.call(user: @s1, school_classes: [ @class_a ], activity_exercise: draft_link)
    teacher_draft = OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a ], activity: draft)

    assert_equal [ W1, W2 ], student_unfiltered.weeks.map(&:week_start)
    assert_equal student_unfiltered.weeks, student_filtered.weeks
    assert_empty student_draft.weeks
    assert_equal [ W3 ], teacher_draft.weeks.map(&:week_start)
  end

  test "building the series does not write anything" do
    assert_no_difference -> { ExerciseAttempt.count + StudentStat.count } do
      OfficialAttemptSeries.call(user: @teacher, school_classes: [ @class_a, @class_b ])
      OfficialAttemptSeries.call(user: @s1, school_classes: [ @class_a ])
    end
  end

  private

  def at(week_start, day)
    Time.utc(week_start.year, week_start.month, week_start.day, 12) + day.days
  end

  def link(activity, title)
    exercise = @teacher.exercises.create!(title:, exercise_type: :quiz, object: quiz_object)
    activity.activity_exercises.create!(exercise:, position: activity.activity_exercises.active.maximum(:position).to_i + 1, points: 10)
  end

  def submit(activity_exercise, student, answers, created_at)
    attempt = Exercises::QuizSubmission.call(activity_exercise:, student:, answers:).attempt
    attempt.update_columns(created_at:)
    attempt
  end

  def quiz_object
    {
      "questions" => [
        { "question_type" => "multiple_choice", "statement" => "Escolha A.", "options" => [ { "id" => "a", "text" => "A" }, { "id" => "b", "text" => "B" } ], "correct_option_ids" => [ "a" ] },
        { "question_type" => "short_answer", "statement" => "Responda 42.", "correct_answer" => "42" }
      ]
    }
  end

  def create_teacher(prefix)
    username = "#{prefix}_#{SecureRandom.hex(5)}"
    Teacher.create!(name: prefix, username:, email: "#{username}@example.test", password: "secret123")
  end

  def create_student(prefix)
    username = "#{prefix}_#{SecureRandom.hex(5)}"
    Student.create!(name: prefix, username:, email: "#{username}@example.test", password: "secret123")
  end
end
