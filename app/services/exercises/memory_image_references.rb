module Exercises
  # Identifica os blob_ids de imagens guardados nos baralhos de todas as tentativas de um exercício da Memória.
  # Qualquer dado que não possa ser interpretado com segurança torna o resultado incompleto, e quem o consome
  # deve preservar todas as imagens.
  class MemoryImageReferences
    Result = Struct.new(:blob_ids, :complete, keyword_init: true) do
      alias_method :complete?, :complete
    end

    def self.call(exercise)
      new(exercise).call
    end

    def initialize(exercise)
      @exercise = exercise
    end

    def call
      blob_ids = Set.new
      attempts.find_each do |attempt|
        ids = blob_ids_from(attempt.correct)
        return incomplete unless ids

        blob_ids.merge(ids)
      end
      Result.new(blob_ids:, complete: true)
    rescue StandardError => error
      Rails.logger.error("Memory image reference lookup failed: #{error.class}")
      incomplete
    end

    private

    # Sem filtro de active, conclusão, aula ou turma: qualquer tentativa existente pode precisar da imagem.
    def attempts
      ExerciseAttempt.where(activity_exercise_id: ActivityExercise.where(exercise_id: @exercise.id).select(:id))
    end

    def blob_ids_from(correct)
      return unless correct.is_a?(Hash) && correct["deck"].is_a?(Array)

      ids = []
      correct["deck"].each do |card|
        element = card.is_a?(Hash) ? card["element"] : nil
        return nil unless element.is_a?(Hash)
        next unless element["type"] == "image"

        blob_id = element["blob_id"]
        return nil unless blob_id.is_a?(Integer) && blob_id.positive?

        ids << blob_id
      end
      ids
    end

    def incomplete
      Result.new(blob_ids: Set.new, complete: false)
    end
  end
end
