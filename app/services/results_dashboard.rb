class ResultsDashboard
  def self.call(user:, school_class:)
    new(user:, school_class:).call
  end

  def initialize(user:, school_class:)
    @user = user
    @school_class = school_class
  end

  def call
    students = eligible_students
    student_ids = students.map(&:id)
    activities = visible_activities
    activity_exercises = activities.flat_map do |activity|
      activity.activity_exercises.select { |link| link.active? && link.exercise.active? }
    end

    activity_results = activities.map do |activity|
      exercise_results = activity_exercises.select { |link| link.activity_id == activity.id }.map do |link|
        build_exercise_result(link, student_ids)
      end
      { activity:, exercises: exercise_results }
    end

    student_averages = students.to_h do |student|
      percentages = activity_results.flat_map do |activity_result|
        activity_result.fetch(:exercises).filter_map do |exercise_result|
          exercise_result.fetch(:percentage_by_student)[student.id]
        end
      end
      [ student.id, ActivityResults.mean_percentage(percentages) ]
    end

    {
      school_class: @school_class,
      students:,
      student_averages:,
      class_average: ActivityResults.mean_percentage(student_averages.values),
      completed_exercises: activity_results.sum { |activity| activity.fetch(:exercises).sum { |exercise| exercise.fetch(:official_by_student).length } },
      possible_exercises: activity_exercises.length * students.length,
      activities: activity_results
    }
  end

  private

  def teacher?
    @user.is_a?(Teacher)
  end

  def eligible_students
    return [ @user ] unless teacher?

    ClassStudent.active.joins(:student)
      .where(class_id: @school_class.id, students: { active: true })
      .includes(:student)
      .map(&:student)
  end

  def visible_activities
    activities = @school_class.activities.active.includes(activity_exercises: :exercise)
    activities = activities.published unless teacher?
    activities.order(:created_at, :id).to_a
  end

  def build_exercise_result(activity_exercise, student_ids)
    official_by_student = ActivityResults.official_attempts(activity_exercise:).select do |student_id, _attempt|
      student_ids.include?(student_id)
    end
    attempts_by_student = ExerciseAttempt.where(
      activity_exercise_id: activity_exercise.id,
      student_id: student_ids
    ).includes(:student).order(:created_at, :id).to_a.group_by(&:student_id)
    percentage_by_student = official_by_student.transform_values do |attempt|
      ActivityResults.attempt_percentage(attempt:)
    end

    {
      activity_exercise:,
      official_by_student:,
      attempts_by_student:,
      percentage_by_student:,
      average_percentage: ActivityResults.mean_percentage(percentage_by_student.values),
      performance_by_item: performance_by_item(activity_exercise.exercise, official_by_student.values)
    }
  end

  def performance_by_item(exercise, official_attempts)
    return if exercise.memory_game?

    totals = {}
    official_attempts.each do |attempt|
      statuses = item_statuses(exercise, attempt)
      statuses.each do |key, label, correct|
        totals[key] ||= { label:, correct: 0, total: 0 }
        totals[key][:correct] += 1 if correct
        totals[key][:total] += 1
      end
    end
    totals.values
  end

  def item_statuses(exercise, attempt)
    snapshot = attempt.correct.to_h
    case exercise.exercise_type
    when "quiz"
      Array(snapshot["questions"]).each_with_index.map do |item, index|
        [ index, item.fetch("statement", "Questão #{index + 1}"), item["correct"] == true ]
      end
    when "fill_blanks"
      Array(snapshot["blanks"]).map do |item|
        id = item.fetch("id").to_s
        [ id, "Lacuna #{id}", item["correct"] == true ]
      end
    when "ordering"
      Array(snapshot["positions"]).each_with_index.map do |item, index|
        [ item.fetch("expected_item_id", index).to_s, item.fetch("expected_label", "Item #{index + 1}"), item["correct"] == true ]
      end
    when "crossword"
      snapshot.fetch("statuses", {}).map do |id, correct|
        [ id, "Palavra #{id}", correct == true ]
      end
    else
      []
    end
  end
end
