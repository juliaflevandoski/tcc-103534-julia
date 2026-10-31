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
        "questions" => [
          { "question_type" => "short_answer", "statement" => "Responda.", "correct_answer" => "Sim" },
          { "question_type" => "true_false", "statement" => "Confirme.", "correct_option_ids" => [ "true" ] }
        ]
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

  test "blank or incomplete Quiz, Fill Blanks, Ordering, and Crossword submissions are rejected without persistence" do
    submissions = {
      quiz: [ { answers: { "0" => "   " } }, { answers: { "0" => "wrong answer" } } ],
      fill_blanks: [ { answers: { "1" => "", "2" => " " } }, { answers: { "1" => "wrong answer", "2" => " " } } ],
      ordering: [ { ordered_ids: [] }, { ordered_ids: [ "a" ] }, { ordered_ids: %w[a a] }, { ordered_ids: %w[a unknown] } ],
      crossword: [ { answer: { cells: {} }.to_json }, { answer: partial_crossword_answer.to_json } ]
    }

    submissions.each do |exercise_type, payloads|
      activity_exercise = @links.fetch(exercise_type)
      payloads.each do |payload|
        assert_no_difference("ExerciseAttempt.count") do
          post exercise_attempts_url, params: {
            exercise_attempt: { activity_exercise_id: activity_exercise.id }.merge(payload)
          }
        end
        assert_response :unprocessable_entity
        assert_includes response.body, "Preencha todas as respostas obrigatórias antes de enviar a atividade."
      end
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

  def partial_crossword_answer
    grid = @links.fetch(:crossword).exercise.object.fetch("grid").fetch("cells")
    cell_id, cell_value = grid.each_with_index.flat_map do |row, row_index|
      row.each_with_index.filter_map do |value, column_index|
        [ [ "#{row_index}-#{column_index}", value ] ] if value.present?
      end
    end.first
    { "cells" => { cell_id => cell_value } }
  end
end
