class StudentBadges
  EXPLORER_LEVEL = 3
  PERFECT_PERCENTAGE = 100

  Badge = Struct.new(:id, :name, :description, :earned, keyword_init: true)

  CATALOG = [
    { id: :first_steps, name: "Primeiros Passos", description: "Concluiu ao menos um exercício com tentativa oficial válida." },
    { id: :perfect_score, name: "Nota Máxima", description: "Obteve 100% de aproveitamento em uma tentativa oficial." },
    { id: :mission_accomplished, name: "Missão Cumprida", description: "Concluiu todos os exercícios de uma aula." },
    { id: :explorer, name: "Explorador", description: "Alcançou o nível #{EXPLORER_LEVEL}." }
  ].freeze

  def self.call(student)
    new(student).call
  end

  def initialize(student)
    @student = student
  end

  def call
    earned = {
      first_steps: official_attempts.any?,
      perfect_score: official_attempts.any? { |attempt| perfect?(attempt) },
      mission_accomplished: mission_accomplished?,
      explorer: StudentLevel.call(@student.student_stat&.xp).level >= EXPLORER_LEVEL
    }
    CATALOG.map { |definition| Badge.new(**definition, earned: earned.fetch(definition.fetch(:id))) }
  end

  private

  def attempted_activity_exercises
    @attempted_activity_exercises ||= begin
      ids = ExerciseAttempt.where(student_id: @student.id).distinct.pluck(:activity_exercise_id)
      ActivityExercise.where(id: ids).includes(:exercise, :activity).to_a
    end
  end

  def official_attempts
    @official_attempts ||= attempted_activity_exercises.filter_map do |activity_exercise|
      ActivityResults.official_attempt(activity_exercise:, student: @student)
    end
  end

  def perfect?(attempt)
    percentage = ActivityResults.attempt_percentage(attempt:)
    !percentage.nil? && percentage >= PERFECT_PERCENTAGE
  end

  def mission_accomplished?
    attempted_activity_exercises.map(&:activity).uniq.any? do |activity|
      ActivityResults.lesson_completed?(activity:, student: @student)
    end
  end
end
