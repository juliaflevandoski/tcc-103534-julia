module Exercises
  class MemoryGamePlay
    COMPARISON_DELAY = 0.9.seconds

    Result = Struct.new(
      :answer, :correct, :card, :matched, :comparison, :completed, :score, :errors,
      keyword_init: true
    ) do
      def success?
        errors.empty?
      end
    end

    def self.start(object:, seed: Random.new_seed, points: 0)
      new(object:).start(seed:, points:)
    end

    def self.reveal(answer:, correct:, card_id:, points:)
      new(answer:, correct:).reveal(card_id:, points:)
    end

    def self.reset(answer:, correct:, at: Time.current)
      new(answer:, correct:).reset(at:)
    end

    def initialize(object: nil, answer: {}, correct: {})
      @object = object&.deep_stringify_keys
      @answer = answer.to_h.deep_stringify_keys
      @correct = correct.to_h.deep_stringify_keys
    end

    def start(seed: Random.new_seed, points: 0)
      deck = @object.fetch("pairs").flat_map do |pair|
        %w[left right].map do |side|
          {
            "id" => SecureRandom.uuid,
            "pair_id" => pair.fetch("id"),
            "element" => pair.fetch(side)
          }
        end
      end.shuffle(random: Random.new(seed))

      {
        "answer" => {
          "started_at" => Time.current.iso8601(6),
          "selected_card_id" => nil,
          "pending_reset_ids" => [],
          "pending_reset_until" => nil,
          "matched_card_ids" => [],
          "attempts" => 0,
          "matches" => 0,
          "errors" => 0,
          "completed" => false
        },
        "correct" => { "deck" => deck, "points" => points.to_i, "xp_award_claimed" => false },
        "card_ids" => deck.pluck("id")
      }
    end

    def reveal(card_id:, points:)
      return failure("Partida encerrada.") if @answer["completed"]
      return failure("Aguarde a comparação atual.") if @answer["pending_reset_ids"].present?

      deck = Array(@correct["deck"])
      card = deck.find { |entry| entry["id"] == card_id.to_s }
      return failure("Carta inválida.") unless card

      matched_ids = Array(@answer["matched_card_ids"])
      return failure("Esta carta já foi encontrada.") if matched_ids.include?(card_id.to_s)

      selected_id = @answer["selected_card_id"]
      if selected_id.nil?
        return result(answer: @answer.merge("selected_card_id" => card_id.to_s), card: public_card(card))
      end
      return failure("Selecione uma carta diferente.") if selected_id == card_id.to_s

      first_card = deck.find { |entry| entry["id"] == selected_id }
      return failure("Partida inválida.") unless first_card

      matched = first_card["pair_id"] == card["pair_id"]
      attempts = @answer.fetch("attempts", 0) + 1
      matches = @answer.fetch("matches", 0) + (matched ? 1 : 0)
      errors = @answer.fetch("errors", 0) + (matched ? 0 : 1)
      matched_ids = matched ? matched_ids + [ selected_id, card_id.to_s ] : matched_ids
      total_pairs = deck.map { |entry| entry["pair_id"] }.uniq.length
      completed = matches == total_pairs
      answer = @answer.merge(
        "selected_card_id" => nil,
        "pending_reset_ids" => matched ? [] : [ selected_id, card_id.to_s ],
        "pending_reset_until" => matched ? nil : (Time.current + COMPARISON_DELAY).iso8601(6),
        "matched_card_ids" => matched_ids,
        "attempts" => attempts,
        "matches" => matches,
        "errors" => errors,
        "completed" => completed
      )
      score = completed ? points.to_i : 0

      result(
        answer:, card: public_card(card), matched:, comparison: true, completed:, score:
      )
    end

    def reset(at: Time.current)
      return failure("Não há comparação para encerrar.") if @answer["pending_reset_ids"].blank?
      return failure("Aguarde a comparação atual.") if Time.iso8601(@answer.fetch("pending_reset_until")) > at

      result(answer: @answer.merge("pending_reset_ids" => [], "pending_reset_until" => nil))
    end

    private

    def public_card(card)
      { "id" => card.fetch("id") }.merge(card.fetch("element"))
    end

    def result(answer:, correct: @correct, card: nil, matched: nil, comparison: false, completed: false, score: 0)
      Result.new(answer:, correct:, card:, matched:, comparison:, completed:, score:, errors: [])
    end

    def failure(message)
      Result.new(answer: @answer, correct: @correct, errors: [ message ])
    end
  end
end
