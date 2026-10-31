require "test_helper"

class ActivityResultsTest < ActiveSupport::TestCase
  setup do
    @teacher = Teacher.create!(name: "Professor", username: "resultsprof", email: "resultsprof@example.com", password: "secret123")
    @school_class = @teacher.school_classes.create!(name: "Resultados", active: true)
    @activity = @school_class.activities.create!(title: "Resultados", published: true)
    @student = create_student("resultstudent")
    @other_student = create_student("otherresultstudent")
    @unattempted_student = create_student("unattemptedstudent")
    [ @student, @other_student, @unattempted_student ].each do |student|
      @school_class.class_students.create!(student:, active: true)
    end
  end

  test "first valid attempt is official through later attempts and soft-delete" do
    activity_exercise = create_quiz_link
    first = Exercises::QuizSubmission.call(
      activity_exercise:,
      student: @student,
      answers: { "0" => "a", "1" => "wrong" }
    ).attempt
    second = Exercises::QuizSubmission.call(
      activity_exercise:,
      student: @student,
      answers: { "0" => "a", "1" => "42" }
    ).attempt
    third = Exercises::QuizSubmission.call(
      activity_exercise:,
      student: @student,
      answers: { "0" => "b", "1" => "wrong" }
    ).attempt

    assert_equal 5, first.score
    assert_equal 10, ActivityResults.points_possible(attempt: first)
    assert_equal 10, second.score
    assert_equal 0, third.score
    assert_equal first, ActivityResults.official_attempt(activity_exercise:, student: @student)
    xp_before_incomplete_submission = @student.reload.student_stat.xp

    assert ActivityResults.lesson_completed?(activity: @activity, student: @student)
    assert_no_difference("ExerciseAttempt.count") do
      assert_raises(Exercises::AttemptValidity::BlankResponse) do
        Exercises::QuizSubmission.call(activity_exercise:, student: @student, answers: { "0" => "a" })
      end
    end

    assert_equal first, ActivityResults.official_attempt(activity_exercise:, student: @student)
    assert ActivityResults.lesson_completed?(activity: @activity, student: @student)
    assert_equal xp_before_incomplete_submission, @student.reload.student_stat.xp

    first.update!(active: false)
    assert_equal first, ActivityResults.official_attempt(activity_exercise:, student: @student)
  end

  test "official attempt ordering uses created_at then ID, not a client-selected marker" do
    activity_exercise = create_quiz_link
    first_created = Exercises::QuizSubmission.call(
      activity_exercise:,
      student: @student,
      answers: { "0" => "a", "1" => "wrong" }
    ).attempt
    second_created = Exercises::QuizSubmission.call(
      activity_exercise:,
      student: @student,
      answers: { "0" => "b", "1" => "42" }
    ).attempt
    same_timestamp = Time.current.change(usec: 0)
    first_created.update_columns(created_at: same_timestamp + 1.second)
    second_created.update_columns(created_at: same_timestamp)

    assert_equal second_created, ActivityResults.official_attempt(activity_exercise:, student: @student)

    second_created.update_columns(created_at: same_timestamp)
    first_created.update_columns(created_at: same_timestamp)
    assert_equal first_created, ActivityResults.official_attempt(activity_exercise:, student: @student)
  end

  test "blank submissions raise before creating attempts or student stats" do
    quiz = create_quiz_link
    fill_blanks = create_fill_blanks_link
    ordering = create_ordering_link
    crossword = create_crossword_link

    [
      [ quiz, -> { Exercises::QuizSubmission.call(activity_exercise: quiz, student: @student, answers: {}) } ],
      [ fill_blanks, -> { Exercises::FillBlanksSubmission.call(activity_exercise: fill_blanks, student: @student, answers: {}) } ],
      [ ordering, -> { Exercises::OrderingSubmission.call(activity_exercise: ordering, student: @student, ordered_ids: []) } ],
      [ crossword, -> { Exercises::CrosswordSubmission.call(activity_exercise: crossword, student: @student, answer: { "cells" => {} }) } ]
    ].each do |_link, submit|
      assert_no_difference("ExerciseAttempt.count") do
        assert_raises(Exercises::AttemptValidity::BlankResponse, &submit)
      end
    end
    assert_not StudentStat.exists?(student_id: @student.id)
  end

  test "partial responses are rejected and complete incorrect responses remain official" do
    activity_exercise = create_fill_blanks_link
    assert_no_difference("ExerciseAttempt.count") do
      assert_raises(Exercises::AttemptValidity::BlankResponse) do
        Exercises::FillBlanksSubmission.call(
          activity_exercise:,
          student: @student,
          answers: { "1" => "not the expected answer", "2" => "" }
        )
      end
    end
    assert_not StudentStat.exists?(student_id: @student.id)
    assert_nil ActivityResults.official_attempt(activity_exercise:, student: @student)

    submission = Exercises::FillBlanksSubmission.call(
      activity_exercise:,
      student: @student,
      answers: { "1" => "not the expected answer", "2" => "also incorrect" }
    )
    assert_equal 0, submission.attempt.score
    assert_equal submission.attempt, ActivityResults.official_attempt(activity_exercise:, student: @student)
  end

  test "legacy partial attempts remain in history but do not become official" do
    activity_exercise = create_fill_blanks_link
    partial_attempt = ExerciseAttempt.create!(
      student: @student,
      activity_exercise:,
      answer: { "answers" => { "1" => "resposta parcial" } },
      correct: { "blanks" => [ { "id" => "1", "correct" => false }, { "id" => "2", "correct" => false } ] },
      score: 0
    )

    assert_nil ActivityResults.official_attempt(activity_exercise:, student: @student)

    complete_attempt = Exercises::FillBlanksSubmission.call(
      activity_exercise:,
      student: @student,
      answers: { "1" => "incorreta", "2" => "também incorreta" }
    ).attempt

    assert_equal complete_attempt, ActivityResults.official_attempt(activity_exercise:, student: @student)
    assert_equal 2, ExerciseAttempt.where(student: @student, activity_exercise:).count
    assert_equal({ "answers" => { "1" => "resposta parcial" } }, partial_attempt.reload.answer)
  end

  test "ordering rejects missing duplicate and unknown item IDs before persistence" do
    activity_exercise = create_ordering_link

    [ %w[item-1], %w[item-1 item-1], %w[item-1 unknown] ].each do |ordered_ids|
      assert_no_difference("ExerciseAttempt.count") do
        assert_raises(Exercises::AttemptValidity::BlankResponse) do
          Exercises::OrderingSubmission.call(activity_exercise:, student: @student, ordered_ids:)
        end
      end
    end

    assert_not StudentStat.exists?(student_id: @student.id)
  end

  test "average uses only enrolled students' official attempts and excludes later higher scores" do
    activity_exercise = create_quiz_link
    first = Exercises::QuizSubmission.call(activity_exercise:, student: @student, answers: { "0" => "a", "1" => "wrong" }).attempt
    Exercises::QuizSubmission.call(activity_exercise:, student: @student, answers: { "0" => "a", "1" => "42" })
    Exercises::QuizSubmission.call(activity_exercise:, student: @other_student, answers: { "0" => "a", "1" => "42" })

    assert_equal 5, first.score
    assert_in_delta 7.5, ActivityResults.activity_average(activity_exercise:), 0.001
    assert_nil ActivityResults.official_attempt(activity_exercise:, student: @unattempted_student)
  end

  test "normalized averages exclude zero-point exercises and weight eligible students equally" do
    ten_point_link = create_quiz_link
    twenty_point_link = create_ordering_link(points: 20)
    zero_point_link = create_exercise_link(
      :quiz,
      {
        "questions" => [
          { "question_type" => "short_answer", "statement" => "Responda.", "correct_answer" => "42" }
        ]
      },
      title: "Sem pontos",
      points: 0
    )

    first_student_attempt = Exercises::QuizSubmission.call(
      activity_exercise: ten_point_link,
      student: @student,
      answers: { "0" => "a", "1" => "wrong" }
    ).attempt
    Exercises::QuizSubmission.call(
      activity_exercise: ten_point_link,
      student: @other_student,
      answers: { "0" => "a", "1" => "42" }
    )
    Exercises::OrderingSubmission.call(
      activity_exercise: twenty_point_link,
      student: @other_student,
      ordered_ids: %w[item-1 item-2]
    )
    twenty_point_link.update!(points: 0)
    Exercises::QuizSubmission.call(
      activity_exercise: zero_point_link,
      student: @student,
      answers: { "0" => "wrong" }
    )

    assert_in_delta 50, ActivityResults.attempt_percentage(attempt: first_student_attempt), 0.001
    assert_in_delta 75, ActivityResults.activity_average_percentage(activity_exercise: ten_point_link), 0.001
    assert_in_delta 100, ActivityResults.activity_average_percentage(activity_exercise: twenty_point_link), 0.001
    assert_nil ActivityResults.activity_average(activity_exercise: zero_point_link)
    assert_nil ActivityResults.activity_average_percentage(activity_exercise: zero_point_link)
    assert_in_delta 50, ActivityResults.student_average_percentage(student: @student, activity_exercises: [ ten_point_link, zero_point_link ]), 0.001
    assert_in_delta 100, ActivityResults.student_average_percentage(student: @other_student, activity_exercises: [ ten_point_link, twenty_point_link ]), 0.001
    assert_in_delta 75, ActivityResults.class_average_percentage(
      students: [ @student, @other_student, @unattempted_student ],
      activity_exercises: [ ten_point_link, twenty_point_link, zero_point_link ]
    ), 0.001
    assert_nil ActivityResults.student_average_percentage(student: @unattempted_student, activity_exercises: [ ten_point_link ])
  end

  test "lesson completion requires every active exercise's official attempt" do
    quiz = create_quiz_link
    ordering = create_ordering_link

    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)
    Exercises::QuizSubmission.call(activity_exercise: quiz, student: @student, answers: { "0" => "a", "1" => "wrong" })
    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)
    Exercises::OrderingSubmission.call(activity_exercise: ordering, student: @student, ordered_ids: [ "item-1", "item-2" ])
    assert ActivityResults.lesson_completed?(activity: @activity, student: @student)

    quiz.activity.update!(published: false)
    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)
  end

  test "an empty lesson is not complete" do
    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)
  end

  test "an incomplete memory game is not official, and the first completed game is" do
    activity_exercise = create_memory_link
    first_game = Exercises::MemoryGamePlay.start(object: activity_exercise.exercise.object, points: activity_exercise.points)
    incomplete_attempt = ExerciseAttempt.create!(
      student: @student,
      activity_exercise:,
      answer: first_game.fetch("answer"),
      correct: first_game.fetch("correct"),
      score: 0
    )
    assert_nil ActivityResults.official_attempt(activity_exercise:, student: @student)
    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)

    second_game = Exercises::MemoryGamePlay.start(object: activity_exercise.exercise.object, points: activity_exercise.points)
    completed_answer, score = complete_memory_game(second_game)
    completed_attempt = ExerciseAttempt.create!(
      student: @student,
      activity_exercise:,
      answer: completed_answer,
      correct: second_game.fetch("correct"),
      score:
    )

    assert_equal false, incomplete_attempt.answer.fetch("completed")
    assert_equal completed_attempt, ActivityResults.official_attempt(activity_exercise:, student: @student)
    assert_equal 10, completed_attempt.score
    assert ActivityResults.lesson_completed?(activity: @activity, student: @student)
  end

  test "lesson completion ignores deactivated exercises and inactive links" do
    active_link = create_quiz_link
    unanswered_hidden = create_ordering_link
    inactive_link = create_fill_blanks_link
    unanswered_hidden.exercise.update!(active: false)
    inactive_link.update!(active: false)

    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)
    submit_quiz(active_link)
    assert ActivityResults.lesson_completed?(activity: @activity, student: @student)
  end

  test "attempt on a deactivated exercise is not required and does not replace a pending active exercise" do
    pending_link = create_quiz_link
    hidden_link = create_ordering_link
    Exercises::OrderingSubmission.call(activity_exercise: hidden_link, student: @student, ordered_ids: [ "item-1", "item-2" ])
    hidden_link.exercise.update!(active: false)

    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)
    submit_quiz(pending_link)
    assert ActivityResults.lesson_completed?(activity: @activity, student: @student)
  end

  test "lesson without active exercises is not complete" do
    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)

    hidden_link = create_quiz_link
    submit_quiz(hidden_link)
    assert ActivityResults.lesson_completed?(activity: @activity, student: @student)
    hidden_link.exercise.update!(active: false)
    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)

    inactive_only = create_ordering_link
    inactive_only.update!(active: false)
    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)
  end

  test "deactivating and reactivating an exercise changes completion without touching attempts" do
    answered = create_quiz_link
    pending = create_ordering_link
    attempt = submit_quiz(answered)

    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)
    pending.exercise.update!(active: false)
    assert ActivityResults.lesson_completed?(activity: @activity, student: @student)
    pending.exercise.update!(active: true)
    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)

    assert_equal 1, ExerciseAttempt.count
    assert_equal attempt, ActivityResults.official_attempt(activity_exercise: answered, student: @student)
    assert_equal 5, attempt.reload.score
  end

  test "completion keeps using the first official attempt" do
    link = create_quiz_link
    first = submit_quiz(link)
    Exercises::QuizSubmission.call(activity_exercise: link, student: @student, answers: { "0" => "a", "1" => "42" })

    assert_equal first, ActivityResults.official_attempt(activity_exercise: link, student: @student)
    assert ActivityResults.lesson_completed?(activity: @activity, student: @student)
  end

  test "completion still requires active published lesson, class, student and enrollment" do
    link = create_quiz_link
    submit_quiz(link)
    assert ActivityResults.lesson_completed?(activity: @activity, student: @student)

    @activity.update!(published: false)
    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)
    @activity.update!(published: true, active: false)
    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)
    @activity.update!(active: true)
    @school_class.update!(active: false)
    assert_not ActivityResults.lesson_completed?(activity: @activity.reload, student: @student)
    @school_class.update!(active: true)
    @student.update!(active: false)
    assert_not ActivityResults.lesson_completed?(activity: @activity.reload, student: @student.reload)
    @student.update!(active: true)
    @school_class.class_students.find_by!(student: @student).update!(active: false)
    assert_not ActivityResults.lesson_completed?(activity: @activity.reload, student: @student.reload)
  end

  private

  def submit_quiz(link)
    Exercises::QuizSubmission.call(activity_exercise: link, student: @student, answers: { "0" => "a", "1" => "wrong" }).attempt
  end

  def create_student(username)
    Student.create!(name: username, username:, email: "#{username}@example.com", password: "secret123")
  end

  def create_exercise_link(type, object, title:, points: 10)
    exercise = @teacher.exercises.create!(title:, exercise_type: type, object:)
    @activity.activity_exercises.create!(exercise:, position: @activity.activity_exercises.active.maximum(:position).to_i + 1, points:)
  end

  def create_quiz_link
    create_exercise_link(:quiz, {
      "questions" => [
        {
          "question_type" => "multiple_choice",
          "statement" => "Escolha a resposta correta.",
          "options" => [ { "id" => "a", "text" => "A" }, { "id" => "b", "text" => "B" } ],
          "correct_option_ids" => [ "a" ]
        },
        { "question_type" => "short_answer", "statement" => "Responda 42.", "correct_answer" => "42" }
      ]
    }, title: "Quiz")
  end

  def create_fill_blanks_link
    create_exercise_link(:fill_blanks, {
      "text_template" => "{{1}} e {{2}}",
      "blanks" => { "1" => "um", "2" => "dois" }
    }, title: "Lacunas")
  end

  def create_ordering_link(points: 10)
    create_exercise_link(:ordering, {
      "instructions" => "Ordene os itens.",
      "item_type" => "words",
      "items" => [ { "id" => "item-1", "label" => "Um" }, { "id" => "item-2", "label" => "Dois" } ],
      "correct_order" => %w[item-1 item-2]
    }, title: "Ordenação", points:)
  end

  def create_crossword_link
    result = Exercises::CrosswordBuilder.call(
      instructions: "Complete a cruzadinha.",
      seed: 17,
      words: [ { word: "APPLE", clue: "Fruta" }, { word: "PEAR", clue: "Outra fruta" } ]
    )
    create_exercise_link(:crossword, result.object, title: "Cruzadinha")
  end

  def create_memory_link
    result = Exercises::MemoryGameBuilder.call(object: {
      instructions: "Combine os pares.",
      pair_type: "word_word",
      pairs: [
        { left: { type: "word", content: "DOG" }, right: { type: "word", content: "CÃO" } },
        { left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } }
      ]
    })
    create_exercise_link(:memory_game, result.object, title: "Memória")
  end

  def complete_memory_game(game)
    answer = game.fetch("answer")
    score = 0
    pairs = game.fetch("correct").fetch("deck").group_by { |card| card.fetch("pair_id") }
    pairs.each_value do |cards|
      first = Exercises::MemoryGamePlay.reveal(
        answer:, correct: game.fetch("correct"), card_id: cards[0].fetch("id"), points: 10
      )
      second = Exercises::MemoryGamePlay.reveal(
        answer: first.answer, correct: game.fetch("correct"), card_id: cards[1].fetch("id"), points: 10
      )
      answer = second.answer
      score = second.score
    end
    [ answer, score ]
  end
end
