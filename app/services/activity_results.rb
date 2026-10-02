class ActivityResults
  def self.official_attempts(activity_exercise:)
    return {} unless activity_exercise&.persisted?

    exercise = activity_exercise.exercise
    return {} unless Exercises::ExerciseContentValidator.call(
      exercise_type: exercise.exercise_type,
      object: exercise.object,
      attached_image_blob_ids: exercise.memory_images_attachments.map(&:blob_id)
    ).success?

    ExerciseAttempt.where(activity_exercise_id: activity_exercise.id)
      .includes(activity_exercise: :exercise)
      .order(:created_at, :id)
      .each_with_object({}) do |attempt, official_by_student|
        next if official_by_student.key?(attempt.student_id)
        next unless Exercises::AttemptValidity.valid_attempt?(attempt)

        official_by_student[attempt.student_id] = attempt
      end
  end

  def self.official_attempt(activity_exercise:, student:)
    official_attempts(activity_exercise:)[student.id]
  end

  def self.activity_average(activity_exercise:)
    school_class = activity_exercise.activity.school_class
    enrolled_student_ids = ClassStudent.active.joins(:student)
      .where(class_id: school_class.id, students: { active: true })
      .pluck(:student_id)
    scores = official_attempts(activity_exercise:).filter_map do |student_id, attempt|
      attempt.score if enrolled_student_ids.include?(student_id)
    end
    return if scores.empty?

    scores.sum.to_f / scores.length
  end

  def self.lesson_completed?(activity:, student:)
    school_class = activity.school_class
    return false unless activity.active? && activity.published? && school_class.active? && student.active?
    return false unless school_class.class_students.active.exists?(student_id: student.id)

    required_exercises = activity.activity_exercises.active.includes(:exercise).to_a
    return false if required_exercises.empty?

    required_exercises.all? do |activity_exercise|
      official_attempt(activity_exercise:, student:).present?
    end
  end
end
