module ActivityExercises
  class Reorder
    def self.call(activity:, ordered_ids:)
      new(activity:, ordered_ids:).call
    end

    def initialize(activity:, ordered_ids:)
      @activity = activity
      @ordered_ids = Array(ordered_ids).map(&:to_i)
    end

    def call
      records = @activity.activity_exercises.active.where(id: @ordered_ids).index_by(&:id)
      return false unless records.keys.sort == @ordered_ids.sort

      ActivityExercise.transaction do
        records.each_key { |id| records[id].update_columns(position: -id) }
        @ordered_ids.each_with_index { |id, index| records[id].update!(position: index + 1) }
      end
      true
    end
  end
end
