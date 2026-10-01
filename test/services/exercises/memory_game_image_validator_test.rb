require "test_helper"
require "stringio"

class Exercises::MemoryGameImageValidatorTest < ActiveSupport::TestCase
  test "accepts PNG, JPEG, and WebP images" do
    {
      "image/png" => "\x89PNG\r\n\x1A\n".b,
      "image/jpeg" => "\xFF\xD8\xFF".b,
      "image/webp" => "RIFF0000WEBP".b
    }.each do |content_type, signature|
      result = Exercises::MemoryGameImageValidator.call(uploaded_file(signature))

      assert result.success?, "#{content_type} should be accepted"
      assert_includes Exercises::MemoryGameImageValidator::ALLOWED_CONTENT_TYPES, result.content_type
    end
  end

  test "rejects unsupported content and images larger than five megabytes" do
    unsupported = Exercises::MemoryGameImageValidator.call(uploaded_file("plain text"))
    oversized = Exercises::MemoryGameImageValidator.call(uploaded_file("\x89PNG\r\n\x1A\n".b, size: 5.megabytes + 1))

    assert_not unsupported.success?
    assert_includes unsupported.errors, "Use uma imagem PNG, JPEG ou WebP."
    assert_not oversized.success?
    assert_includes oversized.errors, "Cada imagem deve ter no máximo 5 MB."
  end

  private

  def uploaded_file(content, size: content.bytesize)
    Struct.new(:size, :tempfile).new(size, StringIO.new(content))
  end
end
