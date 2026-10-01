module Exercises
  class CrosswordBuilder
    MAX_GRID_SIZE = 60

    Result = Struct.new(:success?, :object, :errors, :unplaced_words, keyword_init: true)
    Placement = Struct.new(:entry, :row, :column, :direction, keyword_init: true)

    def self.call(words:, instructions: "", seed: 0)
      new(words:, instructions:, seed:).call
    end

    def initialize(words:, instructions:, seed:)
      @valid_word_list = words.nil? || words.is_a?(Array)
      @words = words.is_a?(Array) ? words : []
      @instructions = instructions.to_s.strip
      @seed = seed.to_i % (2**32)
      @random = Random.new(@seed)
    end

    def call
      entries, errors, invalid_words = normalize_entries
      errors << "Informe as instruções da cruzadinha." if @instructions.empty?
      return failure(errors, unplaced_words: invalid_words) if errors.any?

      ordered_entries = entries.sort_by { |entry| [ -entry[:normalized].length, entry[:index] ] }
      @placements = [ Placement.new(entry: ordered_entries.shift, row: 0, column: 0, direction: "across") ]
      unplaced = ordered_entries.dup

      until unplaced.empty?
        candidates = unplaced.flat_map do |entry|
          candidate_placements(entry).map { |placement| score_placement(placement) }
        end
        crossing_candidates = candidates.select { |candidate| candidate[:intersections].positive? }

        if crossing_candidates.any?
          selected = crossing_candidates.max_by { |candidate| candidate[:score] }
          @placements << selected[:placement]
          unplaced.delete(selected[:placement].entry)
          next
        end

        entry = unplaced.first
        fallback = fallback_placement(entry)
        unless fallback
          return failure([ "A grade excede o limite de #{MAX_GRID_SIZE} células em uma dimensão." ], unplaced_words: unplaced.map { |entry| entry[:word] })
        end

        @placements << fallback
        unplaced.delete(entry)
      end

      Result.new(success?: true, object: build_object, errors: [], unplaced_words: [])
    end

    private

    def normalize_entries
      errors = []
      entries = []
      seen = {}
      invalid_words = []
      errors << "A lista de palavras está inválida." unless @valid_word_list

      @words.each_with_index do |item, index|
        unless item.respond_to?(:[])
          errors << "A palavra #{index + 1} está inválida."
          invalid_words << "#{index + 1}"
          next
        end

        word = value_for(item, "word").to_s.strip
        clue = value_for(item, "clue").to_s.strip
        normalized = normalize_word(word)
        if !word.match?(/\A[\p{L}\p{M}]+\z/u)
          errors << "A palavra #{index + 1} deve conter somente letras, sem espaços ou pontuação."
          invalid_words << word
        elsif !normalized.match?(/\A[A-Z]+\z/)
          errors << "A palavra #{index + 1} contém letras que não podem ser representadas na grade."
          invalid_words << word
        elsif normalized.length < 2
          errors << "A palavra #{index + 1} deve conter pelo menos duas letras."
          invalid_words << word
        elsif normalized.length > MAX_GRID_SIZE
          errors << "A palavra #{index + 1} excede o limite de #{MAX_GRID_SIZE} letras."
          invalid_words << word
        elsif clue.empty?
          errors << "Informe uma pista para a palavra #{index + 1}."
          invalid_words << word
        elsif seen.key?(normalized)
          errors << "A palavra #{word} está repetida após normalização."
          invalid_words << word
        else
          entry = { id: "word-#{index + 1}", index:, word:, normalized:, clue: }
          entries << entry
          seen[normalized] = true
        end
      end

      errors << "Adicione pelo menos duas palavras à cruzadinha." if entries.length < 2 && errors.empty?
      [ entries, errors, invalid_words ]
    end

    def value_for(item, key)
      item[key] || item[key.to_sym]
    end

    def normalize_word(word)
      word.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").upcase
    end

    def candidate_placements(entry)
      candidates = []
      @placements.each do |placed|
        next_direction = placed.direction == "across" ? "down" : "across"
        placed.entry[:normalized].chars.each_with_index do |letter, placed_index|
          entry[:normalized].chars.each_with_index do |candidate_letter, candidate_index|
            next unless letter == candidate_letter

            row, column = position_at(placed, placed_index)
            start_row = next_direction == "across" ? row : row - candidate_index
            start_column = next_direction == "across" ? column - candidate_index : column
            placement = Placement.new(entry:, row: start_row, column: start_column, direction: next_direction)
            candidates << placement if valid_placement?(placement)
          end
        end
      end
      candidates.uniq { |placement| [ placement.row, placement.column, placement.direction ] }
    end

    def position_at(placement, index)
      if placement.direction == "across"
        [ placement.row, placement.column + index ]
      else
        [ placement.row + index, placement.column ]
      end
    end

    def valid_placement?(placement)
      length = placement.entry[:normalized].length
      before = placement.direction == "across" ? [ placement.row, placement.column - 1 ] : [ placement.row - 1, placement.column ]
      after = placement.direction == "across" ? [ placement.row, placement.column + length ] : [ placement.row + length, placement.column ]
      return false if occupied?(before) || occupied?(after)

      intersects = false
      length.times do |index|
        row, column = position_at(placement, index)
        letter = placement.entry[:normalized][index]
        existing = cell_at(row, column)
        if existing
          return false unless existing[:letter] == letter
          return false if existing[:directions].include?(placement.direction)

          intersects = true
        elsif perpendicular_neighbors(placement.direction, row, column).any? { |neighbor| occupied?(neighbor) }
          return false
        end
        return false unless within_grid_bounds?(row, column)
      end
      intersects
    end

    def score_placement(placement)
      intersections = placement.entry[:normalized].length.times.count do |index|
        row, column = position_at(placement, index)
        occupied?([ row, column ])
      end
      rows, columns = bounding_size(placement)
      { placement:, intersections:, score: intersections * 10_000 - rows * columns + @random.rand(100) }
    end

    def perpendicular_neighbors(direction, row, column)
      direction == "across" ? [ [ row - 1, column ], [ row + 1, column ] ] : [ [ row, column - 1 ], [ row, column + 1 ] ]
    end

    def occupied?(position)
      !cell_at(*position).nil?
    end

    def cell_at(row, column)
      @placements.each do |placement|
        placement.entry[:normalized].chars.each_with_index do |letter, index|
          return { letter:, directions: directions_at(row, column) } if position_at(placement, index) == [ row, column ]
        end
      end
      nil
    end

    def directions_at(row, column)
      @placements.filter_map do |placement|
        placement.direction if placement.entry[:normalized].length.times.any? { |index| position_at(placement, index) == [ row, column ] }
      end.uniq
    end

    def within_grid_bounds?(row, column)
      coordinates = @placements.flat_map do |placement|
        placement.entry[:normalized].length.times.map { |index| position_at(placement, index) }
      end + [ [ row, column ] ]
      rows = coordinates.map(&:first)
      columns = coordinates.map(&:last)
      rows.max - rows.min < MAX_GRID_SIZE && columns.max - columns.min < MAX_GRID_SIZE
    end

    def bounding_size(additional = nil)
      placements = @placements + (additional ? [ additional ] : [])
      coordinates = placements.flat_map do |placement|
        placement.entry[:normalized].length.times.map { |index| position_at(placement, index) }
      end
      rows = coordinates.map(&:first)
      columns = coordinates.map(&:last)
      [ rows.max - rows.min + 1, columns.max - columns.min + 1 ]
    end

    def fallback_placement(entry)
      coordinates = @placements.flat_map do |placement|
        placement.entry[:normalized].length.times.map { |index| position_at(placement, index) }
      end
      max_row = coordinates.map(&:first).max
      min_row = coordinates.map(&:first).min

      (max_row + 2..min_row + MAX_GRID_SIZE - 1).each do |row|
        placement = Placement.new(entry:, row:, column: 0, direction: "across")
        return placement if valid_disconnected_placement?(placement)
      end
      nil
    end

    def valid_disconnected_placement?(placement)
      length = placement.entry[:normalized].length
      return false if placement.column + length > MAX_GRID_SIZE
      return false if occupied?([ placement.row, placement.column - 1 ]) || occupied?([ placement.row, placement.column + length ])

      length.times.all? do |index|
        row, column = position_at(placement, index)
        cell_at(row, column).nil? && perpendicular_neighbors(placement.direction, row, column).none? { |neighbor| occupied?(neighbor) }
      end
    end

    def build_object
      coordinates = @placements.flat_map do |placement|
        placement.entry[:normalized].length.times.map { |index| position_at(placement, index) }
      end
      min_row = coordinates.map(&:first).min
      min_column = coordinates.map(&:last).min
      placements = @placements.map do |placement|
        Placement.new(entry: placement.entry, row: placement.row - min_row, column: placement.column - min_column, direction: placement.direction)
      end
      height = coordinates.map(&:first).max - min_row + 1
      width = coordinates.map(&:last).max - min_column + 1
      grid = Array.new(height) { Array.new(width) }

      placements.each do |placement|
        placement.entry[:normalized].chars.each_with_index do |letter, index|
          row, column = position_at(placement, index)
          grid[row][column] = letter
        end
      end

      numbering = {}
      next_number = 1
      placements.sort_by { |placement| [ placement.row, placement.column, placement.direction ] }.each do |placement|
        key = [ placement.row, placement.column ]
        numbering[key] ||= next_number.tap { next_number += 1 }
      end

      entries = placements.map do |placement|
        placement.entry.slice(:id, :word, :normalized, :clue).merge(
          row: placement.row,
          column: placement.column,
          direction: placement.direction,
          number: numbering.fetch([ placement.row, placement.column ])
        ).transform_keys(&:to_s)
      end

      {
        "instructions" => @instructions,
        "words" => entries.sort_by { |entry| entry[:id] },
        "grid" => { "rows" => height, "columns" => width, "cells" => grid },
        "layout_seed" => @seed
      }
    end

    def failure(errors, unplaced_words: [])
      Result.new(success?: false, object: nil, errors:, unplaced_words:)
    end
  end
end
