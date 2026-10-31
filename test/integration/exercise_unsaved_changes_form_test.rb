require "test_helper"

class ExerciseUnsavedChangesFormTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    id = SecureRandom.hex(6)
    @teacher = Teacher.create!(name: "uc-#{id}", username: "uc-#{id}", email: "uc-#{id}@example.com", password: "secret123")
    @exercise = @teacher.exercises.create!(title: "Quiz", exercise_type: :quiz, object: {
      "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ]
    })
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
  end

  test "new form wires the unsaved changes controller without starting dirty" do
    get new_exercise_url

    assert_response :success
    assert_wired(false)
  end

  test "edit form wires the unsaved changes controller without starting dirty" do
    get edit_exercise_url(@exercise)

    assert_response :success
    assert_wired(false)
  end

  test "form rendered after a validation error starts dirty" do
    post exercises_url, params: { exercise: { title: "", exercise_type: "quiz", object: "{}" } }

    assert_response :unprocessable_entity
    assert_wired(true)
  end

  test "form rendered with a source activity keeps the controller" do
    school_class = @teacher.school_classes.create!(name: "Turma", active: true)
    activity = school_class.activities.create!(title: "Aula")
    get new_exercise_url(activity_id: activity.id)

    assert_response :success
    assert_wired(false)
  end

  test "ai modals stay inside the form, where the controller ignores them" do
    get new_exercise_url

    assert_select "form[data-controller~='unsaved-changes'] dialog", minimum: 5
  end

  test "unsaved changes controller is only used by the exercise form" do
    get new_activity_url(school_class_id: @teacher.school_classes.create!(name: "T", active: true).id)

    assert_select "[data-controller~='unsaved-changes']", count: 0
  end

  private

  def assert_wired(dirty)
    assert_select "form[data-controller='exercise-form unsaved-changes']" \
                  "[data-unsaved-changes-start-dirty-value='#{dirty}']" \
                  "[data-action~='turbo:submit-start->unsaved-changes#submitStart']" \
                  "[data-action~='turbo:submit-end->unsaved-changes#submitEnd']", count: 1
  end
end
