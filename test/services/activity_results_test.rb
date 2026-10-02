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
      answers: { "0" => "a" }
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
    assert_equal 10, second.score
    assert_equal 0, third.score
    assert_equal first, ActivityResults.official_attempt(activity_exercise:, student: @student)

    first.update!(active: false)
    assert_equal first, ActivityResults.official_attempt(activity_exercise:, student: @student)
  end

  test "official attempt ordering uses created_at then ID, not a client-selected marker" do
    activity_exercise = create_quiz_link
    first_created = Exercises::QuizSubmission.call(
      activity_exercise:,
      student: @student,
      answers: { "0" => "a" }
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

  test "partial responses are valid official attempts even when their score is zero" do
    activity_exercise = create_fill_blanks_link
    submission = Exercises::FillBlanksSubmission.call(
      activity_exercise:,
      student: @student,
      answers: { "1" => "not the expected answer", "2" => "" }
    )

    assert_equal 0, submission.attempt.score
    assert_equal submission.attempt, ActivityResults.official_attempt(activity_exercise:, student: @student)
  end

  test "average uses only enrolled students' official attempts and excludes later higher scores" do
    activity_exercise = create_quiz_link
    first = Exercises::QuizSubmission.call(activity_exercise:, student: @student, answers: { "0" => "a" }).attempt
    Exercises::QuizSubmission.call(activity_exercise:, student: @student, answers: { "0" => "a", "1" => "42" })
    Exercises::QuizSubmission.call(activity_exercise:, student: @other_student, answers: { "0" => "a", "1" => "42" })

    assert_equal 5, first.score
    assert_in_delta 7.5, ActivityResults.activity_average(activity_exercise:), 0.001
    assert_nil ActivityResults.official_attempt(activity_exercise:, student: @unattempted_student)
  end

  test "lesson completion requires every active exercise's official attempt" do
    quiz = create_quiz_link
    ordering = create_ordering_link

    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)
    Exercises::QuizSubmission.call(activity_exercise: quiz, student: @student, answers: { "0" => "a" })
    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)
    Exercises::OrderingSubmission.call(activity_exercise: ordering, student: @student, ordered_ids: [ "item-1" ])
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

  private

  def create_student(username)
    Student.create!(name: username, username:, email: "#{username}@example.com", password: "secret123")
  end

  def create_exercise_link(type, object, title:)
    exercise = @teacher.exercises.create!(title:, exercise_type: type, object:)
    @activity.activity_exercises.create!(exercise:, position: @activity.activity_exercises.active.maximum(:position).to_i + 1, points: 10)
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

  def create_ordering_link
    create_exercise_link(:ordering, {
      "instructions" => "Ordene os itens.",
      "item_type" => "words",
      "items" => [ { "id" => "item-1", "label" => "Um" }, { "id" => "item-2", "label" => "Dois" } ],
      "correct_order" => %w[item-1 item-2]
    }, title: "Ordenação")
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
