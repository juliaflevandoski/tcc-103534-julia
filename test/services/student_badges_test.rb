require "test_helper"

class StudentBadgesTest < ActiveSupport::TestCase
  setup do
    @teacher = Teacher.create!(name: "Professor", username: "badgeprof", email: "badgeprof@example.com", password: "secret123")
    @school_class = @teacher.school_classes.create!(name: "Medalhas", active: true)
    @activity = @school_class.activities.create!(title: "Aula", published: true)
    @student = Student.create!(name: "Aluno", username: "badgestudent", email: "badgestudent@example.com", password: "secret123")
    @school_class.class_students.create!(student: @student, active: true)
  end

  test "new student has four locked badges" do
    badges = StudentBadges.call(@student)

    assert_equal %i[first_steps perfect_score mission_accomplished explorer], badges.map(&:id)
    assert_equal [ "Primeiros Passos", "Nota Máxima", "Missão Cumprida", "Explorador" ], badges.map(&:name)
    assert badges.all? { |badge| badge.description.present? }
    assert_equal [ false ] * 4, badges.map(&:earned)
  end

  test "first valid official attempt unlocks first steps" do
    link = create_quiz_link
    submit_quiz(link, "wrong")

    assert earned[:first_steps]
    assert_not earned[:perfect_score]
    assert_not earned[:explorer]
  end

  test "incomplete or invalid attempt unlocks nothing" do
    link = create_quiz_link
    ExerciseAttempt.create!(
      student: @student,
      activity_exercise: link,
      answer: { "answers" => { "0" => "a" } },
      correct: { "questions" => [ { "correct" => true } ] },
      score: 10
    )

    assert_equal [ false ] * 4, StudentBadges.call(@student).map(&:earned)
  end

  test "full score unlocks perfect score" do
    submit_quiz(create_quiz_link, "42")

    assert earned[:first_steps]
    assert earned[:perfect_score]
  end

  test "partial score does not unlock perfect score" do
    submit_quiz(create_quiz_link, "wrong")

    assert_not earned[:perfect_score]
  end

  test "later perfect repetition does not replace a partial official attempt" do
    link = create_quiz_link
    submit_quiz(link, "wrong")
    submit_quiz(link, "42")

    assert_not earned[:perfect_score]
  end

  test "completed lesson unlocks mission accomplished" do
    first = create_quiz_link
    second = create_quiz_link
    submit_quiz(first, "wrong")
    assert_not earned[:mission_accomplished]

    submit_quiz(second, "wrong")
    assert earned[:mission_accomplished]
  end

  test "partially answered lesson does not unlock mission accomplished" do
    create_quiz_link
    second = create_quiz_link
    submit_quiz(second, "42")

    assert earned[:first_steps]
    assert_not earned[:mission_accomplished]
  end

  test "lesson without active exercises does not unlock mission accomplished" do
    link = create_quiz_link
    submit_quiz(link, "42")
    link.update!(active: false)

    assert earned[:first_steps]
    assert_not earned[:mission_accomplished]
  end

  test "unpublished lesson does not unlock mission accomplished" do
    submit_quiz(create_quiz_link, "42")
    @activity.update!(published: false)

    assert_not earned[:mission_accomplished]
  end

  test "explorer requires level three" do
    stat = StudentStat.create!(student: @student, xp: 199)
    assert_not earned[:explorer]

    stat.update!(xp: 200)
    assert earned[:explorer]
  end

  test "student without stat is handled and level column is ignored" do
    assert_not earned[:explorer]

    StudentStat.create!(student: @student, xp: 0, level: 9)
    assert_not earned[:explorer]
  end

  test "repetitions do not add badges" do
    link = create_quiz_link
    submit_quiz(link, "42")
    before = StudentBadges.call(@student)
    3.times { submit_quiz(link, "42") }
    after = StudentBadges.call(@student)

    assert_equal 4, after.length
    assert_equal before.map(&:to_h), after.map(&:to_h)
  end

  test "service does not modify records" do
    link = create_quiz_link
    submit_quiz(link, "42")
    tables = [ ExerciseAttempt, StudentStat, ActivityExercise, Activity ]
    snapshot = -> { tables.map { |model| [ model.count, model.maximum(:updated_at) ] } }
    stat = @student.student_stat
    before = snapshot.call
    xp = stat.xp

    StudentBadges.call(@student)

    assert_equal before, snapshot.call
    assert_equal xp, stat.reload.xp
    assert_equal 1, stat.level
  end

  private

  def earned
    StudentBadges.call(@student).to_h { |badge| [ badge.id, badge.earned ] }
  end

  def submit_quiz(link, short_answer)
    Exercises::QuizSubmission.call(
      activity_exercise: link,
      student: @student,
      answers: { "0" => "a", "1" => short_answer }
    ).attempt
  end

  def create_quiz_link
    exercise = @teacher.exercises.create!(title: "Quiz", exercise_type: :quiz, object: {
      "questions" => [
        {
          "question_type" => "multiple_choice",
          "statement" => "Escolha a resposta correta.",
          "options" => [ { "id" => "a", "text" => "A" }, { "id" => "b", "text" => "B" } ],
          "correct_option_ids" => [ "a" ]
        },
        { "question_type" => "short_answer", "statement" => "Responda 42.", "correct_answer" => "42" }
      ]
    })
    @activity.activity_exercises.create!(exercise:, position: @activity.activity_exercises.active.maximum(:position).to_i + 1, points: 10)
  end
end
