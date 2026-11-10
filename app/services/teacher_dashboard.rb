class TeacherDashboard
  RANKING_SIZE = 3

  Result = Struct.new(
    :school_class, :students_count, :activities_count, :exercise_links_count,
    :distinct_exercises_count, :class_average, :completed_exercises, :possible_exercises,
    :exercise_completion_percentage, :lesson_completions, :best_exercises, :worst_exercises,
    keyword_init: true
  )

  LessonCompletion = Struct.new(:activity, :completed_count, :eligible_count, :percentage, keyword_init: true)
  ExerciseRanking = Struct.new(:activity_exercise, :activity, :title, :average, :students_count, keyword_init: true)

  def self.call(teacher:, school_class:, activity: nil, activity_exercise: nil, student: nil)
    new(teacher:, school_class:, activity:, activity_exercise:, student:).call
  end

  def initialize(teacher:, school_class:, activity: nil, activity_exercise: nil, student: nil)
    @student = student
    raise ArgumentError, "Turma não pertence ao professor" unless school_class.teacher_id == teacher.id
    raise ArgumentError, "Aula não pertence à turma" if activity && activity.class_id != school_class.id

    @teacher = teacher
    @school_class = school_class
    @activity_exercise = activity_exercise
    @activity = activity || activity_exercise&.activity
    if activity_exercise && (activity_exercise.activity.class_id != school_class.id || activity_exercise.activity_id != @activity.id)
      raise ArgumentError, "Vinculo nao pertence a aula da turma"
    end
  end

  def call
    full_data = ResultsDashboard.call(user: @teacher, school_class: @school_class)
    data = scoped(full_data)
    exercise_links = data.fetch(:activities).flat_map { |activity| activity.fetch(:exercises) }
    possible = data.fetch(:possible_exercises)
    completed = data.fetch(:completed_exercises)

    Result.new(
      school_class: @school_class,
      students_count: data.fetch(:students).length,
      activities_count: data.fetch(:activities).length,
      exercise_links_count: exercise_links.length,
      distinct_exercises_count: exercise_links.map { |result| result.fetch(:activity_exercise).exercise_id }.uniq.length,
      class_average: data.fetch(:class_average),
      completed_exercises: completed,
      possible_exercises: possible,
      exercise_completion_percentage: possible.positive? ? completed.to_f / possible * 100 : nil,
      lesson_completions: lesson_completions(data, full_data),
      best_exercises: ranked_exercises(data).sort_by { |ranking| [ -ranking.average, ranking.activity_exercise.id ] }.first(RANKING_SIZE),
      worst_exercises: ranked_exercises(data).sort_by { |ranking| [ ranking.average, ranking.activity_exercise.id ] }.first(RANKING_SIZE)
    )
  end

  private

  # Restringe os dados já agregados à aula escolhida, com as mesmas fórmulas do ResultsDashboard.
  def scoped(data)
    return data unless @activity || @student

    students = data.fetch(:students)
    if @student
      students = students.select { |student| student.id == @student.id }
      raise ArgumentError, "Aluno sem matrícula ativa na turma" if students.empty?
    end

    activities = data.fetch(:activities)
    activities = activities.select { |activity_result| activity_result.fetch(:activity).id == @activity.id } if @activity
    activities = activities.map do |activity_result|
      exercises = activity_result.fetch(:exercises)
      exercises = exercises.select { |result| result.fetch(:activity_exercise).id == @activity_exercise.id } if @activity_exercise
      exercises = exercises.map { |result| for_student(result) } if @student
      activity_result.merge(exercises:)
    end
    exercise_results = activities.flat_map { |activity_result| activity_result.fetch(:exercises) }
    student_averages = students.to_h do |student|
      percentages = exercise_results.filter_map { |result| result.fetch(:percentage_by_student)[student.id] }
      [ student.id, ActivityResults.mean_percentage(percentages) ]
    end

    data.merge(
      students:,
      activities:,
      student_averages:,
      class_average: ActivityResults.mean_percentage(student_averages.values),
      completed_exercises: exercise_results.sum { |result| result.fetch(:official_by_student).length },
      possible_exercises: exercise_results.length * students.length
    )
  end

  def for_student(result)
    official = result.fetch(:official_by_student).slice(@student.id)
    percentages = result.fetch(:percentage_by_student).slice(@student.id)
    result.merge(official_by_student: official, percentage_by_student: percentages, average_percentage: ActivityResults.mean_percentage(percentages.values))
  end

  # Mesma regra de ActivityResults.lesson_completed?, lida dos resultados em lote; usa full_data porque o filtro de exercício não muda os exercícios obrigatórios da aula.
  def lesson_completions(data, full_data)
    students = data.fetch(:students)
    required_by_activity = full_data.fetch(:activities).to_h { |activity_result| [ activity_result.fetch(:activity).id, activity_result.fetch(:exercises) ] }
    data.fetch(:activities).map do |activity_result|
      activity = activity_result.fetch(:activity)
      next LessonCompletion.new(activity:, completed_count: nil, eligible_count: students.length, percentage: nil) unless activity.published?

      required = required_by_activity.fetch(activity.id)
      completed = if @school_class.active? && required.any?
        students.count { |student| required.all? { |result| result.fetch(:official_by_student).key?(student.id) } }
      else
        0
      end
      LessonCompletion.new(
        activity:,
        completed_count: completed,
        eligible_count: students.length,
        percentage: students.empty? ? nil : completed.to_f / students.length * 100
      )
    end
  end

  def ranked_exercises(data)
    @ranked_exercises ||= data.fetch(:activities).flat_map do |activity_result|
      activity_result.fetch(:exercises).filter_map do |exercise_result|
        average = exercise_result.fetch(:average_percentage)
        next if average.nil?

        link = exercise_result.fetch(:activity_exercise)
        ExerciseRanking.new(
          activity_exercise: link,
          activity: activity_result.fetch(:activity),
          title: link.exercise.title,
          average:,
          students_count: exercise_result.fetch(:percentage_by_student).length
        )
      end
    end
  end
end
