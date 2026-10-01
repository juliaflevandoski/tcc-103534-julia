module Exercises
  class MemoryGameBuilder
    PAIR_TYPES = {
      "word_word" => %w[word word],
      "word_image" => %w[word image],
      "image_image" => %w[image image]
    }.freeze

    Result = Struct.new(:object, :errors, keyword_init: true) do
      def success?
        errors.empty?
      end
    end

    def self.call(object:)
      new(object:).call
    end

    def initialize(object:)
      @object = stringify_keys(object)
    end

    def call
      errors = []
      pair_type = @object["pair_type"].to_s
      expected_types = PAIR_TYPES[pair_type]
      errors << "Selecione um tipo de associação válido." unless expected_types

      source_pairs = @object["pairs"].is_a?(Array) ? @object["pairs"] : []
      errors << "Adicione pelo menos dois pares." if source_pairs.length < 2

      pairs = source_pairs.each_with_index.filter_map do |pair, index|
        pair = pair.to_h.deep_stringify_keys if pair.respond_to?(:to_h)
        unless pair.is_a?(Hash) && expected_types
          errors << "Par #{index + 1}: informe os dois elementos."
          next
        end

        elements = %w[left right].map do |side|
          side_index = side == "left" ? 0 : 1
          normalize_element(pair[side], expected_types[side_index], index, side, errors)
        end
        next if elements.any?(&:nil?)

        { "id" => SecureRandom.uuid, "left" => elements[0], "right" => elements[1] }
      end

      Result.new(
        object: {
          "instructions" => @object["instructions"].to_s.strip,
          "pair_type" => pair_type,
          "pairs" => pairs
        },
        errors:
      )
    end

    private

    def stringify_keys(value)
      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), result|
          result[key.to_s] = stringify_keys(nested_value)
        end
      when Array
        value.map { |nested_value| stringify_keys(nested_value) }
      else
        value
      end
    end

    def normalize_element(element, expected_type, index, side, errors)
      element = stringify_keys(element)
      unless element.is_a?(Hash) && element["type"] == expected_type
        errors << "Par #{index + 1}: elemento #{side == "left" ? "da esquerda" : "da direita"} inválido."
        return
      end

      if expected_type == "word"
        content = element["content"].to_s.strip
        if content.blank?
          errors << "Par #{index + 1}: preencha a palavra dos dois lados."
          return
        end

        { "type" => "word", "content" => content }
      else
        upload_key = element["upload_key"].to_s
        return { "type" => "image", "upload_key" => upload_key } if upload_key.present?

        blob_id = Integer(element["blob_id"], exception: false)
        if blob_id.nil? || blob_id <= 0
          errors << "Par #{index + 1}: selecione uma imagem para os dois lados."
          return
        end

        { "type" => "image", "blob_id" => blob_id }
      end
    end
  end
end
