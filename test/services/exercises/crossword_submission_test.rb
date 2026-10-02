require "test_helper"

class Exercises::CrosswordSubmissionTest < ActiveSupport::TestCase
  test "awards XP only for the first crossword attempt, including after soft delete" do
    teacher = Teacher.create!(name: "Professora", username: "crosswordservice", email: "crosswordservice@example.com", password: "secret123")
    school_class = teacher.school_classes.create!(name: "Frutas", active: true)
    activity = school_class.activities.create!(title: "Cruzadinha", published: true)
    student = Student.create!(name: "Aluno", username: "crosswordstudent", email: "crosswordstudent@example.com", password: "secret123")
    school_class.class_students.create!(student:, active: true)
    generated = Exercises::CrosswordBuilder.call(
      instructions: "Complete a cruzadinha",
      seed: 17,
      words: [ { word: "APPLE", clue: "A red fruit" }, { word: "PEAR", clue: "Another fruit" } ]
    )
    exercise = teacher.exercises.create!(title: "Frutas", exercise_type: :crossword, object: generated.object)
    activity_exercise = activity.activity_exercises.create!(exercise:, position: 1, points: 11)
    cells = generated.object.fetch("grid").fetch("cells").each_with_index.flat_map do |row, row_index|
      row.each_with_index.filter_map do |letter, column_index|
        [ "#{row_index}-#{column_index}", letter ] if letter.present?
      end
    end.to_h
    answer = { "cells" => cells }

    first = Exercises::CrosswordSubmission.call(activity_exercise:, student:, answer:)
    assert_equal 11, first.attempt.score
    assert first.xp_awarded
    assert_equal 11, student.reload.student_stat.xp

    first.attempt.update!(active: false)
    second = Exercises::CrosswordSubmission.call(activity_exercise:, student:, answer:)

    assert_equal 11, second.attempt.score
    assert_not second.xp_awarded
    assert_equal false, second.attempt.correct.fetch("xp_award_claimed")
    assert_equal 11, student.reload.student_stat.xp
  end
end
