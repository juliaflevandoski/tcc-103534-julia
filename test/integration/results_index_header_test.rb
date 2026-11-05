require "test_helper"

class ResultsIndexHeaderTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = Teacher.create!(name: "Professor", username: "reshdrprof", email: "reshdrprof@example.com", password: "secret123")
    @school_class = @teacher.school_classes.create!(name: "Turma Cabecalho", active: true)
    @student = Student.create!(name: "Aluno", username: "reshdrstudent", email: "reshdrstudent@example.com", password: "secret123")
    @school_class.class_students.create!(student: @student, active: true)
  end

  test "teacher sees header, filter and keeps the filter contract" do
    sign_in(@teacher, "teacher")

    get exercise_attempts_url

    assert_response :success
    assert_select "main.results-index-page header.results-index-header .results-index-badge", text: "Resultados"
    assert_select "main.results-index-page h1", text: "Resultados"
    assert_select ".results-index-subtitle", text: /desempenho dos alunos/
    assert_select "form.results-filter[method='get'][action='#{exercise_attempts_path}']" do
      assert_select "label[for='school_class_id']", text: "Turma"
      assert_select "select#school_class_id[name='school_class_id'] option", count: 2
      assert_select "input[type='submit'][value='Filtrar'].results-index-submit"
    end
    assert_select ".gamification-panel", count: 0
  end

  test "student sees the student subtitle, selected class and gamification panel" do
    sign_in(@student, "student")

    get exercise_attempts_url(school_class_id: @school_class.id)

    assert_response :success
    assert_select ".results-index-subtitle", text: /suas notas/
    assert_select "select#school_class_id option[selected][value='#{@school_class.id}']", count: 1
    assert_select ".gamification-panel", count: 1
  end

  test "empty states keep their text and status role" do
    teacher_without_classes = Teacher.create!(name: "Sem turmas", username: "reshdrempty", email: "reshdrempty@example.com", password: "secret123")
    sign_in(teacher_without_classes, "teacher")

    get exercise_attempts_url

    assert_select "p.results-empty[role='status']", text: "Não há turmas ativas para consultar."
  end

  test "teacher class card is scoped and the completed indicator has its own note" do
    sign_in(@teacher, "teacher")

    get exercise_attempts_url

    assert_select "section.results-class.results-class--teacher", count: 1
    assert_select ".results-metric .results-metric-note", text: "resultados aluno-exercício"
  end

  test "student class card gets the student modifier and the shared card styles" do
    sign_in(@student, "student")

    get exercise_attempts_url

    assert_select "section.results-class", count: 1
    assert_select "section.results-class--student.results-class--teacher", count: 1
    assert_select "section.results-class--student .results-metric-label", text: "Sua média de notas oficiais"
  end

  test "invalid class filter still redirects" do
    sign_in(@teacher, "teacher")

    get exercise_attempts_url(school_class_id: 0)

    assert_redirected_to root_url
  end

  private

  def sign_in(user, role)
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end
end
