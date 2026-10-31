require "test_helper"

class ActivityExercises::NextExerciseTest < ActiveSupport::TestCase
  setup do
    id = SecureRandom.hex(6)
    @teacher = Teacher.create!(name: "Professor", username: "next-#{id}", email: "next-#{id}@example.com", password: "secret123")
    @school_class = @teacher.school_classes.create!(name: "Turma", active: true)
    @activity = @school_class.activities.create!(title: "Aula", published: true)
  end

  test "returns the next link in position order, skipping gaps, and nil for the last" do
    first = link(position: 1)
    second = link(position: 5)
    third = link(position: 12)

    assert_equal second, ActivityExercises::NextExercise.call(activity_exercise: first)
    assert_equal third, ActivityExercises::NextExercise.call(activity_exercise: second)
    assert_nil ActivityExercises::NextExercise.call(activity_exercise: third)
  end

  test "orders by position and never returns the current link" do
    first = link(position: 3)
    second = link(position: 1)
    third = link(position: 2)

    assert_equal third, ActivityExercises::NextExercise.call(activity_exercise: second)
    assert_equal first, ActivityExercises::NextExercise.call(activity_exercise: third)
    assert_nil ActivityExercises::NextExercise.call(activity_exercise: first)
  end

  test "ignores inactive links and inactive exercises" do
    first = link(position: 1)
    inactive_link = link(position: 2)
    inactive_link.update!(active: false)
    inactive_exercise_link = link(position: 3)
    inactive_exercise_link.exercise.update!(active: false)
    valid = link(position: 4)

    assert_equal valid, ActivityExercises::NextExercise.call(activity_exercise: first)
  end

  test "only considers links from the same activity" do
    first = link(position: 1)
    other_activity = @school_class.activities.create!(title: "Outra aula", published: true)
    other_activity.activity_exercises.create!(exercise: create_exercise, position: 2, points: 1)

    assert_nil ActivityExercises::NextExercise.call(activity_exercise: first)
  end

  test "does not create attempts or links" do
    first = link(position: 1)
    second = link(position: 2)

    assert_no_difference([ "ExerciseAttempt.count", "ActivityExercise.count" ]) do
      assert_equal second, ActivityExercises::NextExercise.call(activity_exercise: first)
    end
  end

  test "returns nil for a missing or unsaved link" do
    assert_nil ActivityExercises::NextExercise.call(activity_exercise: nil)
    assert_nil ActivityExercises::NextExercise.call(activity_exercise: ActivityExercise.new(activity: @activity, position: 1))
  end

  private

  def link(position:)
    @activity.activity_exercises.create!(exercise: create_exercise, position:, points: 1)
  end

  def create_exercise
    @teacher.exercises.create!(title: "Exercício #{SecureRandom.hex(3)}", exercise_type: :quiz, object: {
      "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ]
    })
  end
end
