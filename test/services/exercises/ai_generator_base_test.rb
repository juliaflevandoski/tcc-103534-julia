require "test_helper"

class Exercises::AiGeneratorBaseTest < ActiveSupport::TestCase
  class UnexpectedClient
    def call(**)
      raise "Client must not be called for invalid parameters"
    end
  end

  test "each concrete generator exposes the class call contract and validates before networking" do
    generators = [
      Exercises::FillBlanksGenerator,
      Exercises::OrderingGenerator,
      Exercises::CrosswordGenerator,
      Exercises::MemoryGameGenerator
    ]

    generators.each do |generator|
      result = generator.call(client: UnexpectedClient.new)

      assert result.failure?, "#{generator} should reject missing parameters"
      assert_equal :invalid_input, result.error_code
      assert_nil result.draft
    end
  end
end
