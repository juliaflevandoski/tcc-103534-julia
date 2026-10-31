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
      active_links = @activity.activity_exercises.active.to_a
      records = active_links.index_by(&:id).slice(*@ordered_ids)
      return false unless records.keys.sort == @ordered_ids.sort && @ordered_ids.uniq.size == @ordered_ids.size

      # Vínculos fora da lista (ex.: de exercícios inativos) vão para o fim, preservando a ordem relativa.
      remaining = active_links.reject { |link| records.key?(link.id) }.sort_by { |link| [ link.position, link.id ] }
      final_order = @ordered_ids.map { |id| records[id] } + remaining

      ActivityExercise.transaction do
        final_order.each { |link| link.update_columns(position: -link.id) }
        final_order.each_with_index { |link, index| link.update!(position: index + 1) }
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end
  end
end
