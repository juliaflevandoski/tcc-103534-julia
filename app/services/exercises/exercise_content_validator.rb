module Exercises
  class ExerciseContentValidator
    Result = Struct.new(:errors, keyword_init: true) do
      def success?
        errors.empty?
      end
    end

    QUESTION_TYPES = %w[multiple_choice true_false short_answer].freeze
    PAIR_TYPES = MemoryGameBuilder::PAIR_TYPES
    MARKER_PATTERN = /\{\{(\d+)\}\}/

    def self.call(exercise_type:, object:, attached_image_blob_ids: [], allowed_upload_keys: [])
      new(exercise_type:, object:, attached_image_blob_ids:, allowed_upload_keys:).call
    end

    def initialize(exercise_type:, object:, attached_image_blob_ids:, allowed_upload_keys:)
      @exercise_type = exercise_type.to_s
      @object = stringify(object)
      @attached_image_blob_ids = Array(attached_image_blob_ids)
      @allowed_upload_keys = Array(allowed_upload_keys).map(&:to_s)
      @errors = []
    end

    def call
      unless @object.is_a?(Hash)
        return Result.new(errors: [ "O conteúdo deve ser um objeto JSON." ])
      end

      case @exercise_type
      when "quiz"
        validate_quiz
      when "fill_blanks"
        validate_fill_blanks
      when "ordering"
        validate_ordering
      when "crossword"
        validate_crossword
      when "memory_game"
        validate_memory_game
      end

      Result.new(errors: @errors.uniq)
    end

    private

    def stringify(value)
      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
      case value
      when Hash
        value.each_with_object({}) { |(key, nested), result| result[key.to_s] = stringify(nested) }
      when Array
        value.map { |nested| stringify(nested) }
      else
        value
      end
    end

    def validate_quiz
      questions = @object["questions"]
      unless questions.is_a?(Array) && questions.any?
        @errors << "Adicione pelo menos uma pergunta ao Quiz."
        return
      end

      questions.each_with_index do |question, index|
        unless question.is_a?(Hash)
          @errors << "Pergunta #{index + 1}: informe um objeto de pergunta válido."
          next
        end

        prefix = "Pergunta #{index + 1}: "
        question_type = question["question_type"]
        statement = question["statement"]
        unless QUESTION_TYPES.include?(question_type)
          @errors << "#{prefix}selecione um tipo de pergunta válido."
          next
        end
        @errors << "#{prefix}informe o enunciado." unless nonblank_string?(statement)

        case question_type
        when "multiple_choice"
          validate_multiple_choice(question, prefix)
        when "true_false"
          correct_ids = question["correct_option_ids"]
          unless correct_ids.is_a?(Array) && correct_ids.one? && %w[true false].include?(correct_ids.first)
            @errors << "#{prefix}selecione uma resposta correta de verdadeiro ou falso."
          end
        when "short_answer"
          unless nonblank_string?(question["correct_answer"])
            @errors << "#{prefix}informe a resposta esperada."
          end
        end
      end
    end

    def validate_multiple_choice(question, prefix)
      options = question["options"]
      unless options.is_a?(Array) && options.length >= 2
        @errors << "#{prefix}adicione pelo menos duas alternativas."
        return
      end

      option_ids = []
      options.each do |option|
        unless option.is_a?(Hash) && nonblank_string?(option["id"]) && nonblank_string?(option["text"])
          @errors << "#{prefix}cada alternativa precisa de identificador e texto."
          next
        end
        option_ids << option["id"]
      end
      @errors << "#{prefix}os identificadores das alternativas devem ser únicos." unless option_ids.uniq.length == options.length

      correct_ids = question["correct_option_ids"]
      unless correct_ids.is_a?(Array) && correct_ids.one? && option_ids.include?(correct_ids.first)
        @errors << "#{prefix}a alternativa correta deve corresponder a uma única opção existente."
      end
    end

    def validate_fill_blanks
      template = @object["text_template"]
      unless nonblank_string?(template)
        @errors << "Informe o texto do exercício de completar lacunas."
        return
      end

      marker_ids = template.scan(MARKER_PATTERN).flatten.uniq
      malformed_markers = template.gsub(MARKER_PATTERN, "")
      if marker_ids.empty? || malformed_markers.include?("{{") || malformed_markers.include?("}}")
        @errors << "O texto deve conter ao menos uma lacuna válida."
        return
      end

      blanks = @object["blanks"]
      unless blanks.is_a?(Hash)
        @errors << "Informe uma resposta para cada lacuna."
        return
      end

      unless blanks.keys.sort == marker_ids.sort
        @errors << "As respostas devem corresponder exatamente às lacunas do texto."
      end
      marker_ids.each do |marker_id|
        @errors << "A lacuna #{marker_id} precisa de uma resposta esperada." unless nonblank_string?(blanks[marker_id])
      end
    end

    def validate_ordering
      @errors << "Informe a pergunta ou instrução da ordenação." unless nonblank_string?(@object["instructions"])
      item_type = @object["item_type"]
      @errors << "Selecione um tipo de item válido." unless %w[words numbers].include?(item_type)

      items = @object["items"]
      unless items.is_a?(Array) && items.length >= 2
        @errors << "Adicione pelo menos dois itens para ordenar."
        return
      end

      item_ids = []
      normalized_labels = []
      items.each_with_index do |item, index|
        unless item.is_a?(Hash) && nonblank_string?(item["id"]) && nonblank_string?(item["label"])
          @errors << "Item #{index + 1}: informe identificador e conteúdo válidos."
          next
        end
        item_ids << item["id"]
        if item_type == "numbers" && !item["label"].match?(/\A-?\d+\z/)
          @errors << "Item #{index + 1}: use um número inteiro válido."
        end
        normalized_label = item["label"].strip.gsub(/\s+/, " ").downcase
        normalized_label = Integer(item["label"], 10).to_s if item_type == "numbers" && item["label"].match?(/\A-?\d+\z/)
        normalized_labels << normalized_label
      end
      @errors << "Os identificadores dos itens devem ser únicos." unless item_ids.uniq.length == items.length
      @errors << "Os itens da ordenação não podem estar duplicados." unless normalized_labels.uniq.length == normalized_labels.length

      correct_order = @object["correct_order"]
      unless correct_order.is_a?(Array) && correct_order.length == items.length && correct_order.all? { |id| id.is_a?(String) } && correct_order.uniq.length == correct_order.length && correct_order.sort == item_ids.sort
        @errors << "A ordem correta deve conter uma vez cada identificador de item existente."
      end
    end

    def validate_crossword
      unless nonblank_string?(@object["instructions"])
        @errors << "Informe as instruções da cruzadinha."
        return
      end
      unless @object["layout_seed"].is_a?(Integer)
        @errors << "A semente do layout da cruzadinha deve ser um número inteiro."
        return
      end

      result = CrosswordBuilder.call(
        words: @object["words"],
        instructions: @object["instructions"],
        seed: @object["layout_seed"]
      )
      unless result.success?
        @errors.concat(result.errors)
        return
      end

      validate_crossword_layout
    end

    def validate_crossword_layout
      grid = @object["grid"]
      words = @object["words"]
      unless grid.is_a?(Hash) && words.is_a?(Array)
        @errors << "Informe a grade e as palavras posicionadas da cruzadinha."
        return
      end

      rows = grid["rows"]
      columns = grid["columns"]
      cells = grid["cells"]
      unless rows.is_a?(Integer) && columns.is_a?(Integer) && rows.positive? && columns.positive? &&
          rows <= CrosswordBuilder::MAX_GRID_SIZE && columns <= CrosswordBuilder::MAX_GRID_SIZE &&
          cells.is_a?(Array) && cells.length == rows && cells.all? { |row| row.is_a?(Array) && row.length == columns }
        @errors << "As dimensões e as células da grade são inválidas."
        return
      end

      unless cells.flatten.all? { |cell| cell.nil? || (cell.is_a?(String) && cell.match?(/\A[A-Z]\z/)) }
        @errors << "As células da grade devem conter letras normalizadas ou espaços vazios."
      end

      ids = words.filter_map do |entry|
        unless entry.is_a?(Hash) && nonblank_string?(entry["id"])
          @errors << "Cada palavra posicionada precisa de um identificador."
          next
        end
        entry["id"]
      end
      @errors << "Os identificadores das palavras devem ser únicos." unless ids.uniq.length == ids.length

      covered_cells = {}
      start_cells = []
      words.each_with_index do |entry, index|
        next unless entry.is_a?(Hash)

        word = entry["word"]
        normalized = normalize_crossword_word(word)
        row = entry["row"]
        column = entry["column"]
        direction = entry["direction"]
        number = entry["number"]
        unless nonblank_string?(word) && entry["normalized"] == normalized &&
            row.is_a?(Integer) && column.is_a?(Integer) && row >= 0 && column >= 0 &&
            %w[across down].include?(direction) && number.is_a?(Integer) && number.positive?
          @errors << "Palavra #{index + 1}: dados de posicionamento inválidos."
          next
        end

        start_cells << [ row, column ]
        normalized.each_char.with_index do |letter, letter_index|
          cell_row = row + (direction == "down" ? letter_index : 0)
          cell_column = column + (direction == "across" ? letter_index : 0)
          if cell_row >= rows || cell_column >= columns || cells[cell_row][cell_column] != letter
            @errors << "Palavra #{index + 1}: a posição não corresponde às letras da grade."
            next
          end
          covered_cells[[ cell_row, cell_column ]] = true
        end
      end

      expected_numbers = start_cells.uniq.sort.each_with_index.to_h { |coordinate, index| [ coordinate, index + 1 ] }
      words.each_with_index do |entry, index|
        next unless entry.is_a?(Hash) && entry["row"].is_a?(Integer) && entry["column"].is_a?(Integer)

        unless entry["number"] == expected_numbers[[ entry["row"], entry["column"] ]]
          @errors << "Palavra #{index + 1}: numeração inconsistente com a grade."
        end
      end

      cells.each_with_index do |row, row_index|
        row.each_with_index do |cell, column_index|
          if cell.present? && !covered_cells[[ row_index, column_index ]]
            @errors << "A grade contém letras que não pertencem a nenhuma palavra."
            return
          end
        end
      end
    end

    def normalize_crossword_word(word)
      return "" unless word.is_a?(String)

      word.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").upcase
    end

    def validate_memory_game
      unless nonblank_string?(@object["instructions"])
        @errors << "Informe as instruções do jogo da memória."
      end

      result = MemoryGameBuilder.call(object: @object)
      @errors.concat(result.errors)
      validate_memory_pair_ids
      validate_memory_images if @object["pair_type"].is_a?(String)
    end

    def validate_memory_pair_ids
      pairs = @object["pairs"]
      return unless pairs.is_a?(Array)

      pair_ids = pairs.filter_map do |pair|
        unless pair.is_a?(Hash) && pair.keys.sort == %w[id left right] && nonblank_string?(pair["id"])
          @errors << "Cada par precisa conter somente um identificador e dois elementos."
          next
        end
        pair["id"]
      end
      @errors << "Os identificadores dos pares devem ser únicos." unless pair_ids.uniq.length == pair_ids.length
    end

    def validate_memory_images
      pairs = @object["pairs"]
      return unless pairs.is_a?(Array)

      pairs.each_with_index do |pair, pair_index|
        next unless pair.is_a?(Hash)

        expected_types = PAIR_TYPES[@object["pair_type"]]
        next unless expected_types

        %w[left right].each_with_index do |side, side_index|
          element = pair[side]
          next unless element.is_a?(Hash) && element["type"] == "image" && expected_types[side_index] == "image"

          if element.keys.sort == %w[type upload_key]
            unless nonblank_string?(element["upload_key"]) && @allowed_upload_keys.include?(element["upload_key"])
              @errors << "Par #{pair_index + 1}: a imagem enviada não está associada ao upload recebido."
            end
          elsif element.keys.sort == %w[blob_id type]
            blob_id = element["blob_id"]
            unless blob_id.is_a?(Integer) && blob_id.positive? && @attached_image_blob_ids.include?(blob_id)
              @errors << "Par #{pair_index + 1}: a imagem não pertence aos anexos deste exercício."
            end
          else
            @errors << "Par #{pair_index + 1}: a referência da imagem é inválida."
          end
        end
      end
    end

    def nonblank_string?(value)
      value.is_a?(String) && value.present?
    end
  end
end
