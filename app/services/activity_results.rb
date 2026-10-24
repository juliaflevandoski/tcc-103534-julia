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
    return if activity_exercise.points.to_i <= 0

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

  def self.points_possible(attempt:)
    snapshot = attempt.correct.to_h
    snapshot["points_possible"] || snapshot["points"]
  end

  def self.attempt_percentage(attempt:)
    possible_points = points_possible(attempt:)
    return if possible_points.nil? || possible_points.to_i <= 0

    attempt.score.to_f / possible_points * 100
  end

  def self.activity_average_percentage(activity_exercise:)
    school_class = activity_exercise.activity.school_class
    enrolled_student_ids = ClassStudent.active.joins(:student)
      .where(class_id: school_class.id, students: { active: true })
      .pluck(:student_id)
    percentages = official_attempts(activity_exercise:).filter_map do |student_id, attempt|
      attempt_percentage(attempt:) if enrolled_student_ids.include?(student_id)
    end
    return if percentages.empty?

    percentages.sum / percentages.length
  end

  def self.student_average_percentage(student:, activity_exercises:)
    percentages = activity_exercises.filter_map do |activity_exercise|
      attempt = official_attempt(activity_exercise:, student:)
      attempt_percentage(attempt:) if attempt
    end
    mean_percentage(percentages)
  end

  def self.class_average_percentage(students:, activity_exercises:)
    student_averages = students.uniq(&:id).filter_map do |student|
      student_average_percentage(student:, activity_exercises:)
    end
    mean_percentage(student_averages)
  end

  def self.mean_percentage(percentages)
    eligible_percentages = percentages.compact
    return if eligible_percentages.empty?

    eligible_percentages.sum / eligible_percentages.length
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
