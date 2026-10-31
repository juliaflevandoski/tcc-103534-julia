require "test_helper"

class EmptyLessonNoticeTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  STUDENT_MESSAGE = "Esta aula ainda não possui exercícios disponíveis.".freeze
  TEACHER_MESSAGE = "Esta aula não possui exercícios ativos. Adicione ou ative exercícios para que os alunos possam concluí-la.".freeze

  setup do
    suffix = SecureRandom.hex(6)
    @teacher = Teacher.create!(name: "Professor", username: "vazia-t-#{suffix}", email: "vazia-t-#{suffix}@example.com", password: "secret123")
    @student = Student.create!(name: "Aluno", username: "vazia-s-#{suffix}", email: "vazia-s-#{suffix}@example.com", password: "secret123")
    @school_class = @teacher.school_classes.create!(name: "Turma vazia", active: true)
    @school_class.class_students.create!(student: @student, active: true)
    @activity = @school_class.activities.create!(title: "Aula vazia", published: true)
  end

  test "teacher sees the teacher message on an empty lesson and student message is absent" do
    login_as(@teacher, "teacher")
    get activity_url(@activity)

    assert_response :success
    assert_select ".empty-lesson-notice", text: TEACHER_MESSAGE, count: 1
    assert_select "p", text: STUDENT_MESSAGE, count: 0
  end

  test "enrolled student sees the student message on an empty lesson" do
    login_as(@student, "student")
    get activity_url(@activity)

    assert_response :success
    assert_select ".empty-lesson-notice", text: STUDENT_MESSAGE, count: 1
    assert_select "p", text: TEACHER_MESSAGE, count: 0
  end

  test "lesson with only inactive exercises or inactive links shows the notices" do
    inactive_exercise = create_exercise(active: false)
    inactive_link_exercise = create_exercise
    @activity.activity_exercises.create!(exercise: inactive_exercise, position: 1, points: 1)
    @activity.activity_exercises.create!(exercise: inactive_link_exercise, position: 2, points: 1, active: false)

    login_as(@teacher, "teacher")
    get activity_url(@activity)
    assert_select ".empty-lesson-notice", text: TEACHER_MESSAGE, count: 1
    assert_select "table.exercise-table tbody tr", count: 0

    delete logout_url
    login_as(@student, "student")
    get activity_url(@activity)
    assert_select ".empty-lesson-notice", text: STUDENT_MESSAGE, count: 1
    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)
  end

  test "no notice appears when the lesson has an active exercise" do
    @activity.activity_exercises.create!(exercise: create_exercise, position: 1, points: 1)

    login_as(@teacher, "teacher")
    get activity_url(@activity)
    assert_select ".empty-lesson-notice", count: 0

    delete logout_url
    login_as(@student, "student")
    get activity_url(@activity)
    assert_select ".empty-lesson-notice", count: 0
  end

  test "notice disappears when an inactive exercise is replaced by an active one" do
    @activity.activity_exercises.create!(exercise: create_exercise(active: false), position: 1, points: 1)
    @activity.activity_exercises.create!(exercise: create_exercise, position: 2, points: 1)

    login_as(@teacher, "teacher")
    get activity_url(@activity)
    assert_select ".empty-lesson-notice", count: 0
  end

  test "empty lessons can still be published" do
    draft = @school_class.activities.create!(title: "Rascunho vazio", published: false)
    login_as(@teacher, "teacher")

    patch activity_url(draft), params: { activity: { class_id: @school_class.id, title: draft.title, published: "1" } }

    assert_redirected_to activity_url(draft)
    assert draft.reload.published?
  end

  test "student cannot see the notice for an unpublished or foreign lesson" do
    draft = @school_class.activities.create!(title: "Rascunho", published: false)
    outsider_class = @teacher.school_classes.create!(name: "Outra turma", active: true)
    foreign = outsider_class.activities.create!(title: "Aula alheia", published: true)
    login_as(@student, "student")

    [ draft, foreign ].each do |activity|
      get activity_url(activity)
      assert_redirected_to root_url
      assert_no_match STUDENT_MESSAGE, response.body
    end
  end

  private

  def login_as(user, role)
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end

  def create_exercise(active: true)
    @teacher.exercises.create!(
      title: "Exercício #{SecureRandom.hex(3)}", exercise_type: :quiz, active:,
      object: { "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ] }
    )
  end
end
