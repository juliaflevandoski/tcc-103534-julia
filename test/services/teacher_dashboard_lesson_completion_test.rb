require "test_helper"

class TeacherDashboardLessonCompletionTest < ActiveSupport::TestCase
  setup do
    @teacher = create_teacher("lcprof")
    @school_class = @teacher.school_classes.create!(name: "Conclusão", active: true)
    @s1 = create_student("lcs1")
    @s2 = create_student("lcs2")
    @s3 = create_student("lcs3")
    [ @s1, @s2, @s3 ].each { |student| @school_class.class_students.create!(student:, active: true) }
  end

  test "a lesson completed by every student counts all of them" do
    lesson = create_lesson("Completa")
    links = [ create_link(lesson, "A"), create_link(lesson, "B") ]
    [ @s1, @s2, @s3 ].each { |student| links.each { |link| submit(link, student, "x") } }

    assert_equal [ 3, 3, 100.0 ], completion(lesson).values_at(:completed_count, :eligible_count, :percentage)
  end

  test "a lesson completed by some students needs every required exercise, and students without attempts do not count" do
    lesson = create_lesson("Parcial")
    first = create_link(lesson, "A")
    second = create_link(lesson, "B")
    submit(first, @s1, "x")
    submit(second, @s1, "wrong")
    submit(first, @s2, "x")

    result = completion(lesson)

    assert_equal [ 1, 3 ], result.values_at(:completed_count, :eligible_count)
    assert_in_delta 100.0 / 3, result[:percentage]
  end

  test "an invalid earlier attempt does not complete the lesson, while a later valid one is the official attempt" do
    lesson = create_lesson("Inválida")
    link = create_link(lesson, "A")
    invalid_attempt(link, @s1, 2.days.ago)
    invalid_attempt(link, @s2, 2.days.ago)
    submit(link, @s2, "wrong")

    assert_equal 1, completion(lesson)[:completed_count]
  end

  test "a deactivated official attempt still completes the lesson and later attempts change nothing" do
    lesson = create_lesson("Desativada")
    link = create_link(lesson, "A")
    submit(link, @s1, "wrong").update!(active: false)
    submit(link, @s1, "x")
    submit(link, @s2, "x")

    assert_equal 2, completion(lesson)[:completed_count]
  end

  test "a reused exercise is tracked per lesson link" do
    first_lesson = create_lesson("Primeira aula")
    second_lesson = create_lesson("Segunda aula")
    link = create_link(first_lesson, "Reusado")
    reused = second_lesson.activity_exercises.create!(exercise: link.exercise, position: 1, points: 10)
    submit(link, @s1, "x")
    submit(reused, @s2, "x")
    submit(reused, @s3, "x")

    assert_equal 1, completion(first_lesson)[:completed_count]
    assert_equal 2, completion(second_lesson)[:completed_count]
  end

  test "drafts report no completion, and inactive links, exercises and enrollments follow the existing rules" do
    draft = create_lesson("Rascunho", published: false)
    submit(create_link(draft, "D"), @s1, "x")
    lesson = create_lesson("Com inativos")
    required = create_link(lesson, "Obrigatório")
    inactive_link = create_link(lesson, "Link inativo")
    hidden = create_link(lesson, "Exercício inativo")
    inactive_link.update!(active: false)
    hidden.exercise.update!(active: false)
    submit(required, @s1, "x")
    off = create_student("lcoff")
    @school_class.class_students.create!(student: off, active: false)
    submit(required, off, "x")

    draft_result = completion(draft)
    result = completion(lesson)

    assert_nil draft_result[:completed_count]
    assert_nil draft_result[:percentage]
    assert_equal 3, draft_result[:eligible_count]
    assert_equal [ 1, 3 ], result.values_at(:completed_count, :eligible_count)
  end

  test "a lesson without exercises keeps the current behavior of zero completions" do
    lesson = create_lesson("Vazia")
    only_inactive = create_lesson("Só inativos")
    create_link(only_inactive, "Inativo").update!(active: false)

    assert_equal [ 0, 3, 0.0 ], completion(lesson).values_at(:completed_count, :eligible_count, :percentage)
    assert_equal 0, completion(only_inactive)[:completed_count]

    empty_class = @teacher.school_classes.create!(name: "Sem alunos", active: true)
    empty_class.activities.create!(title: "Sem alunos", published: true)
    result = TeacherDashboard.call(teacher: @teacher, school_class: empty_class).lesson_completions.first
    assert_equal [ 0, 0 ], [ result.completed_count, result.eligible_count ]
    assert_nil result.percentage
  end

  test "an inactive class completes nothing, as in lesson_completed?" do
    lesson = create_lesson("Turma inativa")
    submit(create_link(lesson, "A"), @s1, "x")
    @school_class.update!(active: false)

    assert_equal 0, completion(lesson)[:completed_count]
    assert_not ActivityResults.lesson_completed?(activity: lesson.reload, student: @s1)
  end

  test "completions match ActivityResults.lesson_completed? for every filter combination" do
    full = create_lesson("Referência completa")
    partial = create_lesson("Referência parcial")
    create_lesson("Referência vazia")
    draft = create_lesson("Referência rascunho", published: false)
    full_links = [ create_link(full, "A"), create_link(full, "B") ]
    partial_links = [ create_link(partial, "C"), create_link(partial, "D") ]
    draft_link = create_link(draft, "E")
    reused = partial.activity_exercises.create!(exercise: full_links.first.exercise, position: 3, points: 10)
    [ @s1, @s2 ].each { |student| full_links.each { |link| submit(link, student, "x") } }
    submit(partial_links.first, @s1, "x")
    submit(partial_links.last, @s1, "wrong").update!(active: false)
    submit(partial_links.first, @s2, "x")
    submit(reused, @s1, "x")
    invalid_attempt(partial_links.last, @s2, 3.days.ago)
    submit(draft_link, @s3, "x")

    [
      {}, { student: @s1 }, { student: @s3 }, { activity: partial }, { activity: draft }, { activity: partial, student: @s1 },
      { activity: partial, activity_exercise: partial_links.first }, { activity: full, activity_exercise: full_links.last, student: @s2 }
    ].each do |filters|
      result = TeacherDashboard.call(teacher: @teacher, school_class: SchoolClass.find(@school_class.id), **filters)
      students = filters[:student] ? [ filters[:student] ] : [ @s1, @s2, @s3 ]
      expected = result.lesson_completions.map do |entry|
        activity = Activity.find(entry.activity.id)
        activity.published? ? students.count { |student| ActivityResults.lesson_completed?(activity:, student:) } : nil
      end

      assert_equal expected, result.lesson_completions.map(&:completed_count), "filters: #{filters.keys.inspect}"
    end
  end

  test "an exercise filter does not change which exercises a lesson requires" do
    lesson = create_lesson("Filtro")
    first = create_link(lesson, "A")
    create_link(lesson, "B")
    submit(first, @s1, "x")

    filtered = TeacherDashboard.call(teacher: @teacher, school_class: @school_class, activity_exercise: first).lesson_completions

    assert_equal [ 0, 3 ], filtered.first.then { |entry| [ entry.completed_count, entry.eligible_count ] }
  end

  test "indicators other than the completions are unchanged by the lesson rule" do
    lesson = create_lesson("Indicadores")
    link = create_link(lesson, "A")
    submit(link, @s1, "x")
    submit(link, @s2, "wrong")

    result = TeacherDashboard.call(teacher: @teacher, school_class: @school_class)

    assert_equal [ 3, 1, 1 ], [ result.students_count, result.activities_count, result.exercise_links_count ]
    assert_in_delta 50.0, result.class_average
    assert_equal [ 2, 3 ], [ result.completed_exercises, result.possible_exercises ]
  end

  test "completion queries do not grow with more students or lessons" do
    lesson = create_lesson("Base")
    links = [ create_link(lesson, "A"), create_link(lesson, "B") ]
    [ @s1, @s2, @s3 ].each { |student| links.each { |link| submit(link, student, "x") } }
    baseline = dashboard_queries

    5.times do |index|
      student = create_student("lcextra#{index}")
      @school_class.class_students.create!(student:, active: true)
      links.each { |link| submit(link, student, "x") }
    end
    with_more_students = dashboard_queries
    extra_lessons = 4.times.map { |index| create_lesson("Extra #{index}") }
    extra_lessons.each_with_index { |extra, index| submit(create_link(extra, "X#{index}"), @s1, "x") }
    with_more_lessons = dashboard_queries

    assert_equal baseline[:total], with_more_students[:total]
    assert_equal 0, with_more_students[:completion_checks] + with_more_lessons[:completion_checks]
    assert_operator with_more_lessons[:total] - with_more_students[:total], :<=, extra_lessons.length * 3
  end

  private

  def dashboard_queries
    total = 0
    completion_checks = 0
    callback = lambda do |*, payload|
      next if payload[:cached] || payload[:name] == "SCHEMA"

      total += 1
      completion_checks += 1 if payload[:sql].match?(/FROM "classes_students".*LIMIT/m)
    end
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        TeacherDashboard.call(teacher: Teacher.find(@teacher.id), school_class: SchoolClass.find(@school_class.id))
      end
    end
    { total:, completion_checks: }
  end

  def completion(activity, **filters)
    result = TeacherDashboard.call(teacher: @teacher, school_class: @school_class, **filters)
    entry = result.lesson_completions.find { |item| item.activity.id == activity.id }
    { completed_count: entry.completed_count, eligible_count: entry.eligible_count, percentage: entry.percentage }
  end

  def create_lesson(title, published: true)
    @school_class.activities.create!(title:, published:)
  end

  def create_link(activity, title)
    exercise = @teacher.exercises.create!(
      title:, exercise_type: :quiz,
      object: { "questions" => [ { "question_type" => "short_answer", "statement" => "Responda x.", "correct_answer" => "x" } ] }
    )
    activity.activity_exercises.create!(exercise:, position: activity.activity_exercises.active.maximum(:position).to_i + 1, points: 10)
  end

  def submit(link, student, answer)
    Exercises::QuizSubmission.call(activity_exercise: link, student:, answers: { "0" => answer }).attempt
  end

  def invalid_attempt(link, student, created_at)
    ExerciseAttempt.create!(
      student:, activity_exercise: link,
      answer: { "answers" => { "0" => "" } }, correct: { "questions" => [ { "correct" => false } ] }, score: 0
    ).tap { |attempt| attempt.update_columns(created_at:) }
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
