require "test_helper"

class ResultsDashboardBatchLoadingTest < ActiveSupport::TestCase
  setup do
    @teacher = create_teacher("batchprof")
    @school_class = @teacher.school_classes.create!(name: "Lote", active: true)
    @published = @school_class.activities.create!(title: "Publicada", published: true)
    @draft = @school_class.activities.create!(title: "Rascunho", published: false)
    @s1 = create_student("batchs1")
    @s2 = create_student("batchs2")
    @s3 = create_student("batchs3")
    [ @s1, @s2, @s3 ].each { |student| @school_class.class_students.create!(student:, active: true) }
  end

  test "first valid attempt stays official despite earlier invalid, later and deactivated attempts, and history is complete" do
    link = create_link(@published, "Quiz")
    invalid = ExerciseAttempt.create!(
      student: @s1, activity_exercise: link,
      answer: { "answers" => { "0" => "" } }, correct: { "questions" => [ { "correct" => false } ] }, score: 0
    )
    invalid.update_columns(created_at: 2.days.ago)
    first = submit(link, @s1, "wrong")
    later = submit(link, @s1, "x")
    first.update!(active: false)

    result = exercise_result(link)

    assert_equal first, result[:official_by_student][@s1.id]
    assert_equal [ invalid, first, later ], result[:attempts_by_student][@s1.id]
    assert_in_delta 0.0, result[:percentage_by_student][@s1.id]
    assert_equal ActivityResults.official_attempts(activity_exercise: link), result[:official_by_student]
  end

  test "several students and links get independent official attempts equal to the individual lookup" do
    first_link = create_link(@published, "Primeiro")
    second_link = create_link(@published, "Segundo")
    s1_first = submit(first_link, @s1, "wrong")
    submit(first_link, @s1, "x")
    s2_first = submit(first_link, @s2, "x")
    s1_second = submit(second_link, @s1, "x")

    data = dashboard(@teacher)

    first_result = exercise_result(first_link, data)
    second_result = exercise_result(second_link, data)
    assert_equal({ @s1.id => s1_first, @s2.id => s2_first }, first_result[:official_by_student])
    assert_equal({ @s1.id => s1_second }, second_result[:official_by_student])
    assert_equal [ @s1.id, @s2.id ], first_result[:attempts_by_student].keys.sort
    assert_equal 2, first_result[:attempts_by_student][@s1.id].length
    assert_in_delta 50.0, first_result[:average_percentage]
    [ first_link, second_link ].each do |link|
      assert_equal ActivityResults.official_attempts(activity_exercise: link), exercise_result(link, data)[:official_by_student]
    end
    assert_equal 3, data[:completed_exercises]
    assert_equal 6, data[:possible_exercises]
  end

  test "the same exercise reused in two lessons keeps one result per link" do
    exercise = @teacher.exercises.create!(title: "Reusado", exercise_type: :quiz, object: quiz_object)
    published_link = @published.activity_exercises.create!(exercise:, position: 1, points: 10)
    draft_link = @draft.activity_exercises.create!(exercise:, position: 1, points: 10)
    right = submit(published_link, @s1, "x")
    wrong = submit(draft_link, @s1, "wrong")
    submit(draft_link, @s2, "x")

    data = dashboard(@teacher)

    published_result = exercise_result(published_link, data)
    draft_result = exercise_result(draft_link, data)
    assert_equal({ @s1.id => right }, published_result[:official_by_student])
    assert_equal [ @s1.id ], published_result[:attempts_by_student].keys
    assert_equal wrong, draft_result[:official_by_student][@s1.id]
    assert_equal [ @s1.id, @s2.id ], draft_result[:attempts_by_student].keys.sort
    assert_in_delta 50.0, draft_result[:average_percentage]
  end

  test "students, links and classes without attempts have empty results" do
    link = create_link(@published, "Sem tentativas")

    data = dashboard(@teacher)
    result = exercise_result(link, data)

    assert_equal({}, result[:official_by_student])
    assert_equal({}, result[:attempts_by_student])
    assert_equal({}, result[:percentage_by_student])
    assert_nil result[:average_percentage]
    assert_equal 0, data[:completed_exercises]
    assert_equal 3, data[:possible_exercises]

    empty_class = @teacher.school_classes.create!(name: "Vazia", active: true)
    empty = ResultsDashboard.call(user: @teacher, school_class: empty_class)
    assert_equal [], empty[:students]
    assert_equal [], empty[:activities]
    assert_equal 0, empty[:possible_exercises]
  end

  test "teachers see drafts while students only see published lessons and their own attempts" do
    published_link = create_link(@published, "Publicado")
    draft_link = create_link(@draft, "Rascunho")
    submit(published_link, @s1, "x")
    submit(published_link, @s2, "x")
    draft_attempt = submit(draft_link, @s1, "x")

    teacher_data = dashboard(@teacher)
    student_data = dashboard(@s1)

    assert_equal [ @published.id, @draft.id ], teacher_data[:activities].map { |activity| activity[:activity].id }
    assert_equal draft_attempt, exercise_result(draft_link, teacher_data)[:official_by_student][@s1.id]
    assert_equal [ @published.id ], student_data[:activities].map { |activity| activity[:activity].id }
    assert_equal [ @s1.id ], student_data[:students].map(&:id)
    assert_equal [ @s1.id ], exercise_result(published_link, student_data)[:attempts_by_student].keys
    assert_equal [ @s1.id ], exercise_result(published_link, student_data)[:official_by_student].keys
  end

  test "attempts from unenrolled students, other classes and other teachers never leak in" do
    link = create_link(@published, "Isolado")
    mine = submit(link, @s1, "x")
    outsider = create_student("batchoutsider")
    submit(link, outsider, "x")
    left = create_student("batchleft")
    @school_class.class_students.create!(student: left, active: false)
    submit(link, left, "x")

    other_teacher = create_teacher("batchother")
    other_class = other_teacher.school_classes.create!(name: "Alheia", active: true)
    other_class.class_students.create!(student: @s1, active: true)
    other_link = create_link(other_class.activities.create!(title: "Alheia", published: true), "Alheio", teacher: other_teacher)
    submit(other_link, @s1, "wrong")

    teacher_data = dashboard(@teacher)
    result = exercise_result(link, teacher_data)

    assert_equal [ @s1.id ], result[:attempts_by_student].keys
    assert_equal({ @s1.id => mine }, result[:official_by_student])
    assert_nil teacher_data[:activities].flat_map { |activity| activity[:exercises] }.find { |entry| entry[:activity_exercise] == other_link }
    other_data = ResultsDashboard.call(user: other_teacher, school_class: other_class)
    assert_equal [ @s1.id ], other_data[:students].map(&:id)
    assert_equal [ other_link.id ], other_data[:activities].flat_map { |activity| activity[:exercises].map { |entry| entry[:activity_exercise].id } }
  end

  test "attempt queries do not grow with the number of links" do
    counts = [ 1, 4 ].map do |link_count|
      school_class = @teacher.school_classes.create!(name: "Consultas #{link_count}", active: true)
      school_class.class_students.create!(student: @s1, active: true)
      lesson = school_class.activities.create!(title: "Aula", published: true)
      link_count.times { |index| submit(create_link(lesson, "Q#{link_count}-#{index}"), @s1, "x") }
      count_attempt_queries { ResultsDashboard.call(user: @teacher, school_class: SchoolClass.find(school_class.id)) }
    end

    assert_equal [ 1, 1 ], counts
  end

  private

  def dashboard(user)
    ResultsDashboard.call(user:, school_class: @school_class)
  end

  def exercise_result(link, data = dashboard(@teacher))
    data.fetch(:activities).flat_map { |activity| activity.fetch(:exercises) }.find { |entry| entry.fetch(:activity_exercise) == link }
  end

  def count_attempt_queries
    count = 0
    callback = lambda do |*, payload|
      count += 1 if !payload[:cached] && payload[:name] != "SCHEMA" && payload[:sql].match?(/FROM "exercise_attempts"/)
    end
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    end
    count
  end

  def quiz_object
    { "questions" => [ { "question_type" => "short_answer", "statement" => "Responda x.", "correct_answer" => "x" } ] }
  end

  def create_link(activity, title, teacher: @teacher)
    exercise = teacher.exercises.create!(title:, exercise_type: :quiz, object: quiz_object)
    activity.activity_exercises.create!(exercise:, position: activity.activity_exercises.active.maximum(:position).to_i + 1, points: 10)
  end

  def submit(link, student, answer)
    Exercises::QuizSubmission.call(activity_exercise: link, student:, answers: { "0" => answer }).attempt
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
