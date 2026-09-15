require "test_helper"

class ExerciseAttemptTest < ActiveSupport::TestCase
  test "allows multiple attempts for the same exercise" do
    teacher = Teacher.create!(name: "Ana", username: "ana", email: "ana@example.com", password: "secret123")
    student = Student.create!(name: "Bia", username: "bia", email: "bia@example.com", password: "secret123")
    school_class = SchoolClass.create!(teacher:, name: "História")
    activity = Activity.create!(school_class:, title: "Aula 1")
    exercise = Exercise.create!(teacher:, exercise_type: :quiz, object: { "question" => "2+2" })
    link = ActivityExercise.create!(activity:, exercise:, position: 1, points: 10)

    first = ExerciseAttempt.create!(student:, activity_exercise: link, answer: { "value" => 4 }, correct: { "value" => 4 })
    second = ExerciseAttempt.create!(student:, activity_exercise: link, answer: { "value" => 3 }, correct: { "value" => 4 })

    assert first.persisted?
    assert second.persisted?
  end
end
