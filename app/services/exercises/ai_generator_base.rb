module Exercises
  class AiGeneratorBase
    include RefinementSupport

    DIFFICULTIES = QuizGenerator::DIFFICULTIES
    MAX_GENERATED_ITEMS = 20

    Result = Struct.new(:draft, :error_code, :message, keyword_init: true) do
      def success?
        error_code.nil?
      end

      def failure?
        !success?
      end
    end

    def self.call(client: OpenaiResponsesClient, **arguments)
      new(client:).call(**arguments)
    end

    def initialize(client: OpenaiResponsesClient)
      @client = client
    end

    private

    def parse_count(value, minimum:, maximum: MAX_GENERATED_ITEMS)
      count = if value.is_a?(Integer)
        value
      elsif value.is_a?(String) && value.match?(/\A\d+\z/)
        Integer(value, 10)
      end
      count if count&.between?(minimum, maximum)
    end

    def valid_topic_and_difficulty?(topic, difficulty)
      topic.is_a?(String) && topic.present? && DIFFICULTIES.include?(difficulty)
    end



    def request_json(instructions:, input:, schema_name:, schema:, refinement: nil, previous_reference: nil)
      instructions, input = apply_refinement(instructions:, input:, refinement:, previous_reference:)
      response = begin
        @client.call(instructions:, input:, schema_name:, schema:)
      rescue StandardError => error
        Rails.logger.error("AI exercise generation failed: #{error.class}")
        return failure(:communication_error, "Não foi possível gerar o exercício agora. Tente novamente.")
      end

      unless response.respond_to?(:success?) && response.success? && response.respond_to?(:data) && response.data.is_a?(Hash)
        error_code = response.error_code if response.respond_to?(:error_code)
        message = response.message if response.respond_to?(:message)
        return failure(error_code || :invalid_response, message.presence || "A resposta da IA não é válida.")
      end

      response.data
    end

    def validated_draft(exercise_type, draft)
      validation = ExerciseContentValidator.call(exercise_type:, object: draft)
      return failure(:invalid_response, "A resposta da IA não corresponde ao formato aceito pelo Ludus.") unless validation.success?

      Result.new(draft:, message: nil)
    end

    def failure(error_code, message)
      Result.new(draft: nil, error_code:, message:)
    end

    def difficulty_instructions(difficulty, descriptions:)
      <<~TEXT
        Critérios de dificuldade para este tipo de exercício:
        #{descriptions.map { |level, description| "#{level}: #{description}" }.join("\n")}
        Aplique o nível selecionado: #{difficulty}. A dificuldade é uma orientação pedagógica; preserve clareza, validade e resposta correta inequívoca.
      TEXT
    end
  end
end
