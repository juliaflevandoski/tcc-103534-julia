module ActivityExercises
  class NextExercise
    def self.call(activity_exercise:)
      new(activity_exercise:).call
    end

    def initialize(activity_exercise:)
      @activity_exercise = activity_exercise
    end

    def call
      return unless @activity_exercise&.persisted?

      position = @activity_exercise.position
      ActivityExercise.active
        .joins(:exercise).merge(Exercise.active)
        .where(activity_id: @activity_exercise.activity_id)
        .where("activities_exercises.position > :position OR (activities_exercises.position = :position AND activities_exercises.id > :id)",
          position:, id: @activity_exercise.id)
        .includes(:exercise)
        .order(:position, :id)
        .first
    end
  end
end
