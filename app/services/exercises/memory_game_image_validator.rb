module Exercises
  class MemoryGameImageValidator
    MAX_FILE_SIZE = 5.megabytes
    ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze

    Result = Struct.new(:content_type, :errors, keyword_init: true) do
      def success?
        errors.empty?
      end
    end

    def self.call(upload)
      errors = []
      unless upload.respond_to?(:size) && upload.respond_to?(:tempfile)
        return Result.new(errors: [ "Selecione uma imagem válida." ])
      end

      errors << "Cada imagem deve ter no máximo 5 MB." if upload.size > MAX_FILE_SIZE
      content_type = Marcel::MimeType.for(upload.tempfile)
      upload.tempfile.rewind
      errors << "Use uma imagem PNG, JPEG ou WebP." unless ALLOWED_CONTENT_TYPES.include?(content_type)
      Result.new(content_type:, errors:)
    end
  end
end
