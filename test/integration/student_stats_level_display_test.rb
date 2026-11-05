require "test_helper"

class StudentStatsLevelDisplayTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = Teacher.create!(name: "Professor", username: "levelprof", email: "levelprof@example.com", password: "secret123")
    @school_class = @teacher.school_classes.create!(name: "Turma Níveis", active: true)
    @student = Student.create!(name: "Aluno Veterano", username: "levelvet", email: "levelvet@example.com", password: "secret123")
    @novice = Student.create!(name: "Aluno Novato", username: "levelnovice", email: "levelnovice@example.com", password: "secret123")
    [ @student, @novice ].each { |student| @school_class.class_students.create!(student:, active: true) }
    @stat = StudentStat.create!(student: @student, xp: 250, level: 1)
    @novice_stat = StudentStat.create!(student: @novice, xp: 99, level: 1)
  end

  test "teacher index shows the calculated level instead of the stored level" do
    sign_in(@teacher, "teacher")

    get student_stats_url

    assert_response :success
    assert_select "tr", text: /Aluno Veterano\s*250\s*3/
    assert_select "tr", text: /Aluno Novato\s*99\s*1/
  end

  test "teacher show displays the calculated level" do
    sign_in(@teacher, "teacher")

    get student_stat_url(@stat)

    assert_response :success
    assert_select "p", text: "XP: 250"
    assert_select "p", text: "Nível: 3"
  end

  test "student sees the same calculated level and nothing is modified" do
    sign_in(@student, "student")

    assert_no_changes -> { [ @stat.reload.xp, @stat.level, @stat.updated_at ] } do
      get student_stat_url(@stat)
    end

    assert_select "p", text: "Nível: 3"
  end

  test "authorization is preserved" do
    sign_in(@teacher, "teacher")
    outsider = Student.create!(name: "Fora", username: "leveloutsider", email: "leveloutsider@example.com", password: "secret123")
    outsider_stat = StudentStat.create!(student: outsider, xp: 500)

    get student_stat_url(outsider_stat)

    assert_redirected_to root_url
  end

  private

  def sign_in(user, role)
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end
end
