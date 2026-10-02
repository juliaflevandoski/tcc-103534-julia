require "test_helper"

class BlankExerciseSubmissionsTest < ActionDispatch::IntegrationTest
  setup do
    teacher = Teacher.create!(name: "Professora", username: "blankteacher", email: "blankteacher@example.com", password: "secret123")
    school_class = teacher.school_classes.create!(name: "Conteúdos", active: true)
    activity = school_class.activities.create!(title: "Aula", published: true)
    @student = Student.create!(name: "Aluno", username: "blankstudent", email: "blankstudent@example.com", password: "secret123")
    school_class.class_students.create!(student: @student, active: true)
    @links = {
      quiz: create_link(teacher, activity, :quiz, {
        "questions" => [ { "question_type" => "short_answer", "statement" => "Responda.", "correct_answer" => "Sim" } ]
      }),
      fill_blanks: create_link(teacher, activity, :fill_blanks, {
        "text_template" => "{{1}} e {{2}}", "blanks" => { "1" => "um", "2" => "dois" }
      }),
      ordering: create_link(teacher, activity, :ordering, {
        "instructions" => "Ordene.",
        "item_type" => "words",
        "items" => [ { "id" => "a", "label" => "Um" }, { "id" => "b", "label" => "Dois" } ],
        "correct_order" => %w[a b]
      }),
      crossword: create_crossword_link(teacher, activity)
    }
    post login_url, params: { role: "student", username: @student.username, password: "secret123" }
  end

  test "blank Quiz, Fill Blanks, Ordering, and Crossword submissions are rejected without persistence" do
    submissions = {
      quiz: { answers: { "0" => "   " } },
      fill_blanks: { answers: { "1" => "", "2" => " " } },
      ordering: { ordered_ids: [] },
      crossword: { answer: { cells: {} }.to_json }
    }

    submissions.each do |exercise_type, payload|
      activity_exercise = @links.fetch(exercise_type)
      assert_no_difference("ExerciseAttempt.count") do
        post exercise_attempts_url, params: {
          exercise_attempt: { activity_exercise_id: activity_exercise.id }.merge(payload)
        }
      end
      assert_redirected_to exercise_url(activity_exercise.exercise, activity_exercise_id: activity_exercise.id)
      assert_equal "Responda à atividade antes de enviá-la.", flash[:alert]
    end

    assert_not StudentStat.exists?(student_id: @student.id)
  end

  private

  def create_link(teacher, activity, exercise_type, object)
    exercise = teacher.exercises.create!(title: exercise_type.to_s, exercise_type:, object:)
    activity.activity_exercises.create!(exercise:, position: activity.activity_exercises.active.maximum(:position).to_i + 1, points: 10)
  end

  def create_crossword_link(teacher, activity)
    result = Exercises::CrosswordBuilder.call(
      instructions: "Complete a cruzadinha.",
      seed: 17,
      words: [ { word: "APPLE", clue: "Fruta" }, { word: "PEAR", clue: "Outra fruta" } ]
    )
    exercise = teacher.exercises.create!(title: "crossword", exercise_type: :crossword, object: result.object)
    activity.activity_exercises.create!(exercise:, position: activity.activity_exercises.active.maximum(:position).to_i + 1, points: 10)
  end
end
