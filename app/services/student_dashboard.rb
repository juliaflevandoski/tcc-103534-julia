class StudentDashboard
  Result = Struct.new(
    :classes_count, :lessons_available, :lessons_completed, :exercises_available, :exercises_completed,
    :average, :exercise_completion_percentage, :classes,
    keyword_init: true
  )
  ClassProgress = Struct.new(
    :school_class, :lessons_available, :lessons_completed, :exercises_available, :exercises_completed,
    :average, :exercise_completion_percentage, :lessons,
    keyword_init: true
  )
  LessonProgress = Struct.new(
    :activity, :completed, :exercises_available, :exercises_completed, :completion_percentage,
    keyword_init: true
  )

  def self.call(student:, school_classes:)
    new(student:, school_classes:).call
  end

  def initialize(student:, school_classes:)
    @student = student
    @school_classes = school_classes.to_a
    enrolled_ids = ClassStudent.active.where(student_id: student.id, class_id: @school_classes.map(&:id)).pluck(:class_id)
    unless @school_classes.all? { |school_class| school_class.active? && enrolled_ids.include?(school_class.id) }
      raise ArgumentError, "Turma sem matrícula ativa do aluno"
    end
  end

  def call
    sections = @school_classes.map { |school_class| ResultsDashboard.call(user: @student, school_class:) }
    classes = sections.map { |section| class_progress(section) }
    activity_results = sections.flat_map { |section| section.fetch(:activities) }
    exercise_results = activity_results.flat_map { |activity_result| activity_result.fetch(:exercises) }
    available = sections.sum { |section| section.fetch(:possible_exercises) }
    completed = sections.sum { |section| section.fetch(:completed_exercises) }

    Result.new(
      classes_count: @school_classes.length,
      lessons_available: classes.sum(&:lessons_available),
      lessons_completed: classes.sum(&:lessons_completed),
      exercises_available: available,
      exercises_completed: completed,
      average: ActivityResults.mean_percentage(exercise_results.filter_map { |result| result.fetch(:percentage_by_student)[@student.id] }),
      exercise_completion_percentage: percentage(completed, available),
      classes:
    )
  end

  private

  def percentage(done, total)
    total.positive? ? done.to_f / total * 100 : nil
  end

  def class_progress(section)
    lessons = section.fetch(:activities).map do |activity_result|
      exercises = activity_result.fetch(:exercises)
      done = exercises.count { |result| result.fetch(:official_by_student).key?(@student.id) }
      LessonProgress.new(
        activity: activity_result.fetch(:activity),
        completed: ActivityResults.lesson_completed?(activity: activity_result.fetch(:activity), student: @student),
        exercises_available: exercises.length,
        exercises_completed: done,
        completion_percentage: percentage(done, exercises.length)
      )
    end
    available = section.fetch(:possible_exercises)
    completed = section.fetch(:completed_exercises)

    ClassProgress.new(
      school_class: section.fetch(:school_class),
      lessons_available: lessons.length,
      lessons_completed: lessons.count(&:completed),
      exercises_available: available,
      exercises_completed: completed,
      average: section.fetch(:student_averages)[@student.id],
      exercise_completion_percentage: percentage(completed, available),
      lessons:
    )
  end
end
