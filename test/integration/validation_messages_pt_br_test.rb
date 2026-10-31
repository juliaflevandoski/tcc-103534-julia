require "test_helper"

class ValidationMessagesPtBrTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  ENGLISH_FRAGMENTS = [ "can't be blank", "has already been taken", "must exist", "doesn't match", "is invalid" ].freeze

  def valid_attrs(suffix = SecureRandom.hex(4))
    { name: "Nome #{suffix}", username: "user_#{suffix}", email: "#{suffix}@example.com",
      password: "secret123", password_confirmation: "secret123" }
  end

  def create_teacher(suffix = SecureRandom.hex(4))
    Teacher.create!(valid_attrs(suffix))
  end

  def login(user)
    post login_url, params: { role: user.is_a?(Teacher) ? "teacher" : "student", username: user.username, password: "secret123" }
  end

  def assert_portuguese_only
    ENGLISH_FRAGMENTS.each { |fragment| assert_not_includes response.body, fragment }
    css_select(".errors li").each { |item| assert_no_match(/\A(Password|Username|Title|Name|Email|Object|Teacher|Class)\b/, item.text) }
  end

  test "default locale is pt-BR" do
    assert_equal :"pt-BR", I18n.default_locale
    assert_equal :"pt-BR", I18n.locale
  end

  test "automatic model messages are translated with translated attribute names" do
    teacher = Teacher.new(name: "", username: "", email: "", password: "secret123", password_confirmation: "outra")
    teacher.valid?

    assert_includes teacher.errors.full_messages, "Nome não pode ficar em branco"
    assert_includes teacher.errors.full_messages, "Usuário não pode ficar em branco"
    assert_includes teacher.errors.full_messages, "E-mail não pode ficar em branco"
    assert_includes teacher.errors.full_messages, "Confirmação da senha não é igual a Senha"
  end

  test "uniqueness, required association and numericality messages are translated" do
    existing = create_teacher
    duplicate = Teacher.new(valid_attrs.merge(username: existing.username, email: existing.email))
    duplicate.valid?
    assert_includes duplicate.errors.full_messages, "Usuário já está em uso"
    assert_includes duplicate.errors.full_messages, "E-mail já está em uso"

    activity = Activity.new(title: "A")
    activity.valid?
    assert_includes activity.errors.full_messages, "Selecione a turma da aula."

    link = ActivityExercise.new(position: -1, points: "x")
    link.valid?
    assert_includes link.errors.full_messages, "Posição deve ser maior ou igual a 0"
    assert_includes link.errors.full_messages, "Pontos não é um número"
  end

  test "custom Portuguese messages are preserved" do
    exercise = Exercise.new(title: " ", exercise_type: :quiz, object: { "questions" => [] })
    exercise.valid?
    assert_includes exercise.errors.full_messages, "Informe o título do exercício."
    assert_includes exercise.errors.full_messages, "Adicione pelo menos uma pergunta ao Quiz."

    activity = Activity.new(title: "A")
    activity.errors.add(:class_id, "inválida")
    assert_equal [ "Turma inválida" ], activity.errors.full_messages
  end

  test "support connectors join messages in Portuguese" do
    assert_equal "a, b e c", %w[a b c].to_sentence
    assert_equal "a e b", %w[a b].to_sentence
  end

  test "plural helper still works for Portuguese words" do
    assert_equal "2 exercícios", ApplicationController.helpers.pluralize(2, "exercício")
    assert_equal "1 exercício", ApplicationController.helpers.pluralize(1, "exercício")
  end

  %w[teacher student].each do |role|
    test "#{role} registration with several errors shows Portuguese messages and keeps status" do
      post register_url(role), params: { registration: { name: "", username: "", email: "", password: "secret123", password_confirmation: "outra" } }

      assert_response :unprocessable_entity
      assert_includes response.body, "Nome não pode ficar em branco"
      assert_includes response.body, "Confirmação da senha não é igual a Senha"
      assert_portuguese_only
    end

    test "#{role} registration with duplicate data shows Portuguese uniqueness messages" do
      existing = role == "teacher" ? create_teacher : Student.create!(valid_attrs)
      post register_url(role), params: { registration: valid_attrs.merge(username: existing.username, email: existing.email) }

      assert_response :unprocessable_entity
      assert_includes response.body, "Usuário já está em uso"
      assert_includes response.body, "E-mail já está em uso"
      assert_portuguese_only
    end
  end

  test "school class with invalid data shows a single Portuguese error" do
    login(create_teacher)

    assert_no_difference -> { SchoolClass.count } do
      post school_classes_url, params: { school_class: { name: "", description: "x" } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "1 erro impediu o salvamento:"
    assert_includes response.body, "Nome não pode ficar em branco"
    assert_portuguese_only
  end

  test "activity with invalid data shows several Portuguese errors" do
    login(create_teacher)

    assert_no_difference -> { Activity.count } do
      post activities_url, params: { activity: { title: "", class_id: 0 } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "2 erros impediram o salvamento:"
    assert_includes response.body, "Título não pode ficar em branco"
    assert_includes response.body, "Selecione a turma da aula."
    assert_portuguese_only
  end

  test "exercise without title shows the Portuguese message and keeps status" do
    login(create_teacher)
    object = { questions: [ { question_type: "short_answer", statement: "P?", correct_answer: "R" } ] }

    assert_no_difference -> { Exercise.count } do
      post exercises_url, params: { exercise: { title: "", exercise_type: "quiz", object: object.to_json } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "1 erro impediu o salvamento:"
    assert_includes response.body, "Informe o título do exercício."
    assert_portuguese_only
  end

  test "exercise content errors are not prefixed with an attribute name" do
    login(create_teacher)

    post exercises_url, params: { exercise: { title: "Quiz", exercise_type: "quiz", object: { questions: [] }.to_json } }

    assert_response :unprocessable_entity
    assert_includes response.body, "<li>Adicione pelo menos uma pergunta ao Quiz.</li>"
    assert_equal [ "Adicione pelo menos uma pergunta ao Quiz." ], css_select(".errors li").map(&:text)
  end

  test "empty content shows only specific messages, never a bare blank message" do
    login(create_teacher)

    %w[quiz fill_blanks ordering].each do |type|
      [ { object: "{}" }, {}, { object: { text: "" }.to_json } ].each do |extra|
        post exercises_url, params: { exercise: { title: "Meu #{type}", description: "Desc", exercise_type: type }.merge(extra) }

        assert_response :unprocessable_entity, type
        items = css_select(".errors li").map(&:text)
        assert_not_empty items, type
        items.each { |item| assert_no_match(/\Anão pode ficar em branco\z/, item.strip) }
        assert_equal items.uniq, items, type
        assert_includes response.body, "Meu #{type}"
      end
    end
  end

  test "fill blanks without text shows a single clear message" do
    login(create_teacher)

    post exercises_url, params: { exercise: { title: "Lacunas", exercise_type: "fill_blanks", object: "{}" } }

    assert_response :unprocessable_entity
    assert_equal [ "Informe o texto do exercício de completar lacunas." ], css_select(".errors li").map(&:text)
    assert_includes response.body, "Lacunas"
  end

  test "password reset with wrong confirmation keeps its Portuguese message and status" do
    token = SecureRandom.urlsafe_base64(24)
    Teacher.create!(valid_attrs.merge(password_reset_token: token, password_reset_sent_at: Time.current))

    patch edit_password_reset_url("teacher", token), params: { user: { password: "novasenha1", password_confirmation: "diferente" } }

    assert_response :unprocessable_entity
    assert_includes response.body, "A confirmação da senha deve ser igual à nova senha."
    assert_includes response.body, "1 erro impediu o salvamento:"
    assert_portuguese_only
  end
end
