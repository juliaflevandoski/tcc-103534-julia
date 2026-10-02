require "test_helper"

class AuthorizationSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = Teacher.create!(name: "Teacher", username: "securityteacher", email: "securityteacher@example.com", password: "secret123")
    @other_teacher = Teacher.create!(name: "Other teacher", username: "othersecurityteacher", email: "othersecurityteacher@example.com", password: "secret123")
    @school_class = @teacher.school_classes.create!(name: "Owned class", active: true)
    @other_class = @other_teacher.school_classes.create!(name: "Other class", active: true)
    @student = Student.create!(name: "Student", username: "securitystudent", email: "securitystudent@example.com", password: "secret123")
    @other_student = Student.create!(name: "Other student", username: "othersecuritystudent", email: "othersecuritystudent@example.com", password: "secret123")
    @membership = @school_class.class_students.create!(student: @student, active: true)
    @other_membership = @other_class.class_students.create!(student: @other_student, active: true)
    @activity = @school_class.activities.create!(title: "Owned activity", published: true)
    @other_activity = @other_class.activities.create!(title: "Other activity", published: true)
    @activity_exercise = create_memory_link(@teacher, @activity, "Owned memory")
    @other_activity_exercise = create_memory_link(@other_teacher, @other_activity, "Other memory")
    @own_attempt = create_memory_attempt(@student, @activity_exercise)
    @other_attempt = create_memory_attempt(@other_student, @other_activity_exercise)
    @own_stat = StudentStat.create!(student: @student, xp: 12, level: 2)
    @other_stat = StudentStat.create!(student: @other_student, xp: 30, level: 4)
  end

  test "profile policies allow only the matching user's own record" do
    assert TeacherPolicy.new(@teacher, @teacher).show?
    assert TeacherPolicy.new(@teacher, @teacher).update?
    assert_not TeacherPolicy.new(@teacher, @teacher).create?
    assert_not TeacherPolicy.new(@teacher, @other_teacher).show?
    assert_not TeacherPolicy.new(@student, @teacher).show?
    assert_not StudentPolicy.new(@teacher, @student).show?
    assert StudentPolicy.new(@student, @student).show?
    assert_not StudentPolicy.new(@student, @other_student).update?
    assert_not StudentPolicy.new(@student, @student).create?
  end

  test "student stats are scoped to the student or the teacher's own roster and are read-only" do
    sign_in(@student, role: "student")

    get student_stat_url(@own_stat)
    assert_response :success
    get student_stat_url(@other_stat)
    assert_redirected_to root_url
    assert_no_difference("StudentStat.count") do
      post student_stats_url, params: { student_stat: { student_id: @student.id, xp: 999, level: 99 } }
    end
    assert_redirected_to root_url
    patch student_stat_url(@own_stat), params: { student_stat: { xp: 999, level: 99 } }
    assert_redirected_to root_url
    assert_equal [ 12, 2 ], [ @own_stat.reload.xp, @own_stat.level ]

    sign_in(@teacher, role: "teacher")
    get student_stats_url
    assert_response :success
    assert_includes response.body, @student.name
    assert_not_includes response.body, @other_student.name
    assert_select "a[href='#{edit_student_stat_path(@own_stat)}']", count: 0
    assert_select "a", text: "Novo registro", count: 0
    assert_select "button", text: "Remover", count: 0
    get student_stat_url(@other_stat)
    assert_redirected_to root_url
    patch student_stat_url(@own_stat), params: { student_stat: { xp: 500, level: 50 } }
    assert_redirected_to root_url
    assert_equal [ 12, 2 ], [ @own_stat.reload.xp, @own_stat.level ]
  end

  test "teacher membership queries and mutations stay within owned classes" do
    sign_in(@teacher, role: "teacher")

    get class_students_url
    assert_response :success
    assert_select "tbody tr", count: 1
    assert_includes response.body, @student.name
    assert_not_includes response.body, @other_student.name
    get class_student_url(@other_membership)
    assert_redirected_to root_url

    assert_no_difference("ClassStudent.count") do
      post class_students_url, params: { class_student: { student_id: @other_student.id, class_id: @other_class.id } }
    end
    assert_redirected_to root_url

    patch class_student_url(@membership), params: { class_student: { student_id: @other_student.id, class_id: @other_class.id } }
    assert_redirected_to root_url
    assert_equal [ @student.id, @school_class.id ], @membership.reload.values_at(:student_id, :class_id)
  end

  test "students use the class code flow and cannot manage memberships through CRUD" do
    sign_in(@other_student, role: "student")

    assert_no_difference("ClassStudent.count") do
      post class_students_url, params: { class_student: { student_id: @other_student.id, class_id: @school_class.id } }
    end
    assert_redirected_to root_url

    post join_school_classes_url, params: { access_code: @school_class.access_code }
    assert @school_class.class_students.active.exists?(student_id: @other_student.id)
    delete leave_school_class_url(@school_class)
    assert_not @school_class.class_students.active.exists?(student_id: @other_student.id)
  end

  test "students cannot edit attempts or result fields and cannot access another student's attempt" do
    sign_in(@student, role: "student")

    get exercise_attempts_url
    assert_response :success
    assert_includes response.body, @own_attempt.student.name
    assert_not_includes response.body, @other_attempt.student.name
    get exercise_attempt_url(@other_attempt)
    assert_redirected_to root_url
    get edit_exercise_attempt_url(@own_attempt)
    assert_redirected_to root_url
    get new_exercise_attempt_url
    assert_redirected_to root_url
    patch exercise_attempt_url(@own_attempt), params: {
      exercise_attempt: {
        student_id: @other_student.id,
        activity_exercise_id: @other_activity_exercise.id,
        answer: { forged: true },
        correct: { forged: true },
        score: 999
      }
    }
    assert_redirected_to root_url
    assert_equal @student.id, @own_attempt.reload.student_id
    assert_equal @activity_exercise.id, @own_attempt.activity_exercise_id
    assert_equal 0, @own_attempt.score
    assert_not_equal({ "forged" => true }, @own_attempt.correct)
  end

  test "memory attempt start ignores client-supplied identity and result fields" do
    sign_in(@student, role: "student")

    assert_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: {
        exercise_attempt: {
          activity_exercise_id: @activity_exercise.id,
          student_id: @other_student.id,
          answer: { forged: true },
          correct: { forged: true },
          score: 999
        }
      }
    end

    attempt = ExerciseAttempt.order(:id).last
    assert_equal @student.id, attempt.student_id
    assert_equal @activity_exercise.id, attempt.activity_exercise_id
    assert_equal 0, attempt.score
    assert attempt.correct.key?("deck")
    assert_not attempt.correct.key?("forged")
    assert_redirected_to exercise_url(
      @activity_exercise.exercise,
      activity_exercise_id: @activity_exercise.id,
      memory_game_attempt_id: attempt.id
    )
  end

  test "memory attempt submission is scoped to the student's enrolled activity" do
    sign_in(@student, role: "student")

    assert_no_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: {
        exercise_attempt: { activity_exercise_id: @other_activity_exercise.id }
      }
    end
    assert_redirected_to root_url
  end

  test "invalid generic attempt submission cannot create a client-scored result" do
    sign_in(@student, role: "student")

    assert_no_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: {
        exercise_attempt: {
          student_id: @other_student.id,
          activity_exercise_id: 999_999,
          answer: { forged: true },
          correct: { forged: true },
          score: 999
        }
      }
    end
    assert_redirected_to root_url
  end

  private

  def sign_in(user, role:)
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end

  def create_memory_link(teacher, activity, title)
    result = Exercises::MemoryGameBuilder.call(object: {
      instructions: "Combine os pares.",
      pair_type: "word_word",
      pairs: [
        { left: { type: "word", content: "DOG" }, right: { type: "word", content: "CÃO" } },
        { left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } }
      ]
    })
    exercise = teacher.exercises.create!(title:, exercise_type: :memory_game, object: result.object)
    activity.activity_exercises.create!(exercise:, position: 1, points: 10)
  end

  def create_memory_attempt(student, activity_exercise)
    game = Exercises::MemoryGamePlay.start(object: activity_exercise.exercise.object, points: activity_exercise.points)
    ExerciseAttempt.create!(
      student:,
      activity_exercise:,
      answer: game.fetch("answer"),
      correct: game.fetch("correct"),
      score: 0
    )
  end
end
