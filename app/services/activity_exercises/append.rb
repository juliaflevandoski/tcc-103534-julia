module ActivityExercises
  # Salva um novo vínculo ao final dos exercícios visíveis da aula; vínculos ativos
  # ocultos (exercício desativado) são reposicionados depois dele pelo Reorder.
  class Append
    def self.call(activity_exercise)
      new(activity_exercise).call
    end

    def initialize(activity_exercise)
      @link = activity_exercise
      @activity = activity_exercise.activity
    end

    def call
      saved = false
      ActivityExercise.transaction do
        compact_positions if highest_position >= ActivityExercise::MAX_POSITION
        @link.position = highest_position + 1
        saved = @link.save && normalize_positions
        raise ActiveRecord::Rollback unless saved
      end
      saved
    rescue ActiveRecord::RecordNotUnique
      @link.errors.add(:base, "Não foi possível posicionar o exercício. Tente novamente.")
      false
    end

    private

    def highest_position
      @activity.activity_exercises.active.maximum(:position).to_i
    end

    # Evita que o novo vínculo ultrapasse o limite quando já existe uma posição extrema.
    def compact_positions
      Reorder.call(activity: @activity, ordered_ids: visible_ids)
    end

    def visible_ids
      @activity.activity_exercises.active.joins(:exercise).merge(Exercise.active)
               .where.not(id: @link.id).order(:position, :id).pluck(:id)
    end

    def normalize_positions
      Reorder.call(activity: @activity, ordered_ids: visible_ids + [ @link.id ])
    end
  end
end
