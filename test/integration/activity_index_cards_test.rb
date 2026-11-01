require "test_helper"

class ActivityIndexCardsTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = create_teacher("activity-index")
    @school_class = @teacher.school_classes.create!(name: "Turma da listagem")
    @published_activity = @school_class.activities.create!(title: "Aula publicada", published: true)
    @draft_activity = @school_class.activities.create!(title: "Aula em rascunho", published: false)
  end

  test "teacher sees their active lessons as cards with existing actions and publication states" do
    other_teacher = create_teacher("activity-index-other")
    other_class = other_teacher.school_classes.create!(name: "Turma de outro professor")
    other_activity = other_class.activities.create!(title: "Aula de outro professor", published: true)
    inactive_activity = @school_class.activities.create!(title: "Aula desativada", active: false)
    sign_in(@teacher)

    get activities_url

    assert_response :success
    assert_select ".activities-index-header a[href='#{new_activity_path}']", text: "Nova aula"
    assert_select ".activities-index-card", 2
    assert_select ".activities-index-card h2", text: @published_activity.title
    assert_select ".activities-index-card h2", text: @draft_activity.title
    assert_select ".activities-index-status.is-published", text: "Publicada"
    assert_select ".activities-index-status.is-draft", text: "Rascunho"
    assert_select ".activities-index-card", text: /Turma: #{@school_class.name}/
    assert_select ".activities-index-card a[href='#{activity_path(@published_activity)}']", text: "Ver"
    assert_select ".activities-index-card a[href='#{edit_activity_path(@published_activity)}']", text: "Editar"
    assert_select ".activities-index-card form[action='#{activity_path(@published_activity)}'][data-turbo-confirm^='Desativar esta aula'] input[name='_method'][value='delete']"
    assert_no_match(other_activity.title, response.body)
    assert_no_match(inactive_activity.title, response.body)
  end

  test "student remains redirected away from the teacher activity listing" do
    student = Student.create!(
      name: "Aluno da listagem",
      username: "activity-index-student-#{SecureRandom.hex(6)}",
      email: "activity-index-student-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    sign_in(student, "student")

    get activities_url

    assert_redirected_to school_classes_url
  end

  private

  def create_teacher(prefix)
    identifier = "#{prefix}-#{SecureRandom.hex(6)}"
    Teacher.create!(name: "Professora #{identifier}", username: identifier, email: "#{identifier}@example.com", password: "secret123")
  end

  def sign_in(user, role = "teacher")
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end
end
