module Exercises
  # Valida o rascunho anterior enviado pelo navegador para refinamento e extrai dele
  # apenas uma referência compacta para o prompt. O rascunho nunca é confiável: a
  # estrutura é revalidada no servidor e nada é persistido.
  class PreviousDraftReference
    # Teto de 20 KB para o JSON do rascunho: o maior rascunho legítimo (20 itens) fica bem abaixo disso.
    MAX_BYTES = 20_000
    INVALID_MESSAGE = "A sugestão anterior enviada para refinamento é inválida.".freeze
    TOO_LARGE_MESSAGE = "A sugestão anterior é grande demais para ser refinada.".freeze
    FORMAT_MESSAGE = "A sugestão anterior não corresponde ao formato selecionado.".freeze
    MIN_ITEMS = 2
    MAX_ITEMS = 20
    MEMORY_SIDE_TYPES = {
      "word_word" => %w[word word],
      "word_image" => %w[word image],
      "image_image" => %w[image image]
    }.freeze

    Result = Struct.new(:reference, :message, keyword_init: true) do
      def success?
        message.nil?
      end
    end

    class Rejected < StandardError; end

    def self.call(**arguments)
      new.call(**arguments)
    end

    def call(exercise_type:, draft:, requested: {})
      raise Rejected, INVALID_MESSAGE unless draft.is_a?(Hash)
      raise Rejected, TOO_LARGE_MESSAGE if JSON.generate(draft).bytesize > MAX_BYTES

      Result.new(reference: public_send(:"#{exercise_type}_reference", draft, requested))
    rescue Rejected => error
      Result.new(message: error.message)
    rescue StandardError
      Result.new(message: INVALID_MESSAGE)
    end

    def quiz_reference(draft, requested)
      validate!("quiz", draft)
      allowed = requested[:question_types]
      types = draft.fetch("questions").map { |question| question["question_type"] }.uniq
      raise Rejected, FORMAT_MESSAGE if allowed.is_a?(Array) && (types - allowed).any?

      draft.slice("questions")
    end

    def fill_blanks_reference(draft, _requested)
      validate!("fill_blanks", draft)
      draft.slice("text_template", "blanks")
    end

    def ordering_reference(draft, requested)
      if requested[:format] == "multiple_sentences"
        raise Rejected, FORMAT_MESSAGE unless draft["format"] == ExerciseContentValidator::MULTIPLE_SENTENCES_FORMAT

        validate!("ordering", draft)
        { "instructions" => draft["instructions"], "sentences" => draft.fetch("sentences").map { |sentence| ordered_labels(sentence).join(" ") } }
      else
        raise Rejected, FORMAT_MESSAGE if draft["format"].present? || draft["item_type"] != requested[:item_type]

        validate!("ordering", draft)
        { "instructions" => draft["instructions"], "item_type" => draft["item_type"], "ordered_labels" => ordered_labels(draft) }
      end
    end

    def crossword_reference(draft, _requested)
      words = draft["words"]
      raise Rejected, INVALID_MESSAGE unless words.is_a?(Array) && words.length.between?(MIN_ITEMS, MAX_ITEMS)
      raise Rejected, INVALID_MESSAGE unless words.all? { |entry| entry.is_a?(Hash) && entry["word"].is_a?(String) && entry["clue"].is_a?(String) }

      entries = words.map { |entry| { "word" => entry["word"], "clue" => entry["clue"] } }
      raise Rejected, INVALID_MESSAGE unless CrosswordBuilder.call(words: entries, instructions: "Validação da sugestão anterior.", seed: 0).success?

      { "words" => entries }
    end

    def memory_game_reference(draft, requested)
      pair_type = draft["pair_type"]
      raise Rejected, FORMAT_MESSAGE unless pair_type == requested[:pair_type] && MEMORY_SIDE_TYPES.key?(pair_type)

      pairs = draft["pairs"]
      instructions = draft["instructions"]
      raise Rejected, INVALID_MESSAGE unless instructions.is_a?(String) && instructions.present?
      raise Rejected, INVALID_MESSAGE unless pairs.is_a?(Array) && pairs.length.between?(MIN_ITEMS, MAX_ITEMS)

      validate!("memory_game", draft) if pair_type == "word_word"
      left_type, right_type = MEMORY_SIDE_TYPES.fetch(pair_type)
      {
        "pair_type" => pair_type,
        "instructions" => instructions,
        "pairs" => pairs.map { |pair| { "left" => side_text(pair["left"], left_type), "right" => side_text(pair["right"], right_type) } }
      }
    end

    private

    def validate!(exercise_type, draft)
      raise Rejected, INVALID_MESSAGE unless ExerciseContentValidator.call(exercise_type:, object: draft).success?
    end

    def ordered_labels(container)
      labels = container.fetch("items").to_h { |item| [ item.fetch("id"), item.fetch("label") ] }
      container.fetch("correct_order").map { |id| labels.fetch(id) }
    end

    def side_text(side, type)
      raise Rejected, INVALID_MESSAGE unless side.is_a?(Hash) && side["type"] == type

      text = type == "word" ? side["content"] : side["ai_description"]
      raise Rejected, INVALID_MESSAGE unless text.is_a?(String) && text.present?

      text
    end
  end
end
