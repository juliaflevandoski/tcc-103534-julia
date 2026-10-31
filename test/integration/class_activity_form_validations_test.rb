require "test_helper"

class ClassActivityFormValidationsTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  MAX_XP = 2**63 - 1

  setup do
    @teacher = Teacher.create!(name: "Prof", username: "prof_v", email: "prof_v@example.com", password: "secret123")
    @school_class = SchoolClass.create!(teacher: @teacher, name: "Turma base")
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
  end

  def new_class(**attrs)
    SchoolClass.new({ teacher: @teacher, name: "Turma" }.merge(attrs))
  end

  def new_activity(**attrs)
    Activity.new({ school_class: @school_class, title: "Aula" }.merge(attrs))
  end

  def errors_list
    css_select(".errors li").map(&:text)
  end

  # SchoolClass: nome

  test "class name is required, trimmed and limited to 50 characters" do
    assert new_class(name: "Matemática").valid?
    [ nil, "", "   " ].each { |name| assert_not new_class(name:).valid?, name.inspect }
    assert_includes new_class(name: "  ").tap(&:valid?).errors.full_messages, "Nome não pode ficar em branco"

    assert new_class(name: "a" * 50).valid?
    too_long = new_class(name: "a" * 51)
    assert_not too_long.valid?
    assert_equal [ "Nome é muito longo (máximo: 50 caracteres)" ], too_long.errors.full_messages

    padded = new_class(name: "  Turma A  ")
    assert_equal "Turma A", padded.name
    assert padded.save
    assert_equal "Turma A", padded.reload.name
    assert new_class(name: " #{'a' * 50} ").valid?
  end

  # SchoolClass: descrição

  test "class description is optional and limited to 255 characters" do
    assert new_class(description: nil).valid?
    assert new_class(description: "").valid?
    assert new_class(description: "d" * 255).valid?
    assert_equal [ "Descrição é muito longo (máximo: 255 caracteres)" ], new_class(description: "d" * 256).tap(&:valid?).errors.full_messages
    assert_equal "  x  ", new_class(description: "  x  ").description
  end

  # SchoolClass: XP

  test "class xp accepts nil, empty, zero and non-negative integers" do
    [ nil, "", "0", 0, "10", 25, MAX_XP, MAX_XP.to_s ].each do |xp|
      assert new_class(xp_points: xp).valid?, xp.inspect
    end
    assert_nil new_class(xp_points: "").xp_points
  end

  test "class xp rejects negative, decimal, non numeric and scientific values without silent conversion" do
    [ "-5", -1, "1.7", 1.5, "abc", "1e3", "12abc", "0x10" ].each do |xp|
      record = new_class(xp_points: xp)
      assert_not record.valid?, xp.inspect
      assert record.errors[:xp_points].any?, xp.inspect
    end
    assert_includes new_class(xp_points: "abc").tap(&:valid?).errors.full_messages, "XP da turma não é um número"
    assert_includes new_class(xp_points: "1.7").tap(&:valid?).errors.full_messages, "XP da turma não é um número inteiro"
    assert_includes new_class(xp_points: "-5").tap(&:valid?).errors.full_messages, "XP da turma deve ser maior ou igual a 0"
  end

  test "class xp above the technical limit is rejected and the limit is persistable" do
    over = (MAX_XP + 1).to_s
    record = new_class(xp_points: over)
    assert_not record.valid?
    assert_not record.save
    assert_includes record.errors.full_messages, "XP da turma deve ser menor ou igual a #{MAX_XP}"

    limit = new_class(xp_points: MAX_XP.to_s)
    assert limit.save
    assert_equal MAX_XP, limit.reload.xp_points
  end

  # SchoolClass: formulários

  test "creating a class with invalid data keeps typed values and returns 422" do
    assert_no_difference -> { SchoolClass.count } do
      post school_classes_url, params: { school_class: { name: "Nova", description: "Minha descrição", xp_points: "-3" } }
    end

    assert_response :unprocessable_entity
    assert_equal [ "XP da turma deve ser maior ou igual a 0" ], errors_list
    assert_select "input[name='school_class[name]'][value=?]", "Nova"
    assert_select "textarea[name='school_class[description]']", text: /Minha descrição/
    assert_select "input[name='school_class[xp_points]'][value=?]", "-3"
  end

  test "creating a class with huge xp returns 422 instead of a server error" do
    assert_no_difference -> { SchoolClass.count } do
      post school_classes_url, params: { school_class: { name: "Nova", xp_points: "9" * 25 } }
    end

    assert_response :unprocessable_entity
    assert_equal [ "XP da turma deve ser menor ou igual a #{MAX_XP}" ], errors_list
  end

  test "creating a class trims the name and keeps xp blank as nil" do
    assert_difference -> { SchoolClass.count }, 1 do
      post school_classes_url, params: { school_class: { name: "  Física  ", xp_points: "" } }
    end

    created = SchoolClass.order(:id).last
    assert_equal "Física", created.name
    assert_nil created.xp_points
    assert_redirected_to school_class_url(created)
  end

  test "editing a class applies the same rules and keeps typed values" do
    patch school_class_url(@school_class), params: { school_class: { name: "a" * 51, description: "Texto", xp_points: "1.5" } }

    assert_response :unprocessable_entity
    assert_equal [ "Nome é muito longo (máximo: 50 caracteres)", "XP da turma não é um número inteiro" ], errors_list
    assert_select "input[name='school_class[name]'][value=?]", "a" * 51
    assert_select "textarea[name='school_class[description]']", text: /Texto/
    assert_equal "Turma base", @school_class.reload.name

    patch school_class_url(@school_class), params: { school_class: { name: "  Nova edição ", xp_points: "0" } }
    assert_redirected_to school_class_url(@school_class)
    assert_equal "Nova edição", @school_class.reload.name
    assert_equal 0, @school_class.xp_points
  end

  test "class form exposes the browser attributes" do
    get new_school_class_url

    assert_select "input[name='school_class[name]'][required][maxlength='50']"
    assert_select "textarea[name='school_class[description]'][maxlength='255']"
    assert_select "input[name='school_class[xp_points]'][min='0']"
  end

  # Activity: título

  test "activity title is required, trimmed and limited to 150 characters" do
    assert new_activity.valid?
    [ nil, "", "   " ].each { |title| assert_not new_activity(title:).valid?, title.inspect }
    assert new_activity(title: "a" * 150).valid?
    too_long = new_activity(title: "a" * 151)
    assert_not too_long.valid?
    assert_equal [ "Título é muito longo (máximo: 150 caracteres)" ], too_long.errors.full_messages

    padded = new_activity(title: "  Aula 1  ")
    assert padded.save
    assert_equal "Aula 1", padded.reload.title
    assert new_activity(title: " #{'a' * 150} ").valid?
  end

  test "activity without a class shows a clear message only once" do
    activity = Activity.new(title: "Aula", teacher: @teacher)
    assert_not activity.valid?
    assert_equal [ "Selecione a turma da aula." ], activity.errors.full_messages
  end

  # Activity: formulários

  test "creating an activity with invalid data keeps typed values and returns 422" do
    assert_no_difference -> { Activity.count } do
      post activities_url, params: { activity: { class_id: @school_class.id, title: "a" * 151, published: "1" } }
    end

    assert_response :unprocessable_entity
    assert_equal [ "Título é muito longo (máximo: 150 caracteres)" ], errors_list
    assert_select "input[name='activity[title]'][value=?]", "a" * 151
    assert_select "select[name='activity[class_id]'] option[selected][value=?]", @school_class.id.to_s
    assert_select "input[type=checkbox][name='activity[published]'][checked]"
  end

  test "creating an activity without a class shows the clear message" do
    post activities_url, params: { activity: { class_id: "", title: "Aula" } }

    assert_response :unprocessable_entity
    assert_equal [ "Selecione a turma da aula." ], errors_list
  end

  test "creating an activity with a class from another teacher keeps the previous behavior" do
    other = Teacher.create!(name: "Outro", username: "outro_v", email: "outro_v@example.com", password: "secret123")
    foreign = SchoolClass.create!(teacher: other, name: "Alheia")

    assert_no_difference -> { Activity.count } do
      post activities_url, params: { activity: { class_id: foreign.id, title: "Aula" } }
    end

    assert_response :unprocessable_entity
    assert_equal [ "Selecione a turma da aula." ], errors_list
  end

  test "creating and editing activities trims the title and keeps publication behavior" do
    assert_difference -> { Activity.count }, 1 do
      post activities_url, params: { activity: { class_id: @school_class.id, title: "  Aula nova  ", published: "1" } }
    end
    activity = Activity.order(:id).last
    assert_equal "Aula nova", activity.title
    assert activity.published?

    patch activity_url(activity), params: { activity: { title: "", published: "0" } }
    assert_response :unprocessable_entity
    assert_equal [ "Título não pode ficar em branco" ], errors_list
    assert activity.reload.published?
    assert_equal "Aula nova", activity.title

    patch activity_url(activity), params: { activity: { title: "  Editada ", published: "0" } }
    assert_redirected_to activity_url(activity)
    assert_equal "Editada", activity.reload.title
    assert_not activity.published?
  end

  test "activity form exposes the browser attributes" do
    get new_activity_url

    assert_select "select[name='activity[class_id]'][required]"
    assert_select "input[name='activity[title]'][required][maxlength='150']"
  end
end
