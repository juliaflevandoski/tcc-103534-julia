class Exercise < ApplicationRecord
  include ActiveRecordScope

  belongs_to :teacher
  has_many :activity_exercises, dependent: :restrict_with_exception
  has_many :activities, through: :activity_exercises
  has_many_attached :memory_images
  attr_accessor :memory_upload_keys

  enum :exercise_type, {
    quiz: "quiz",
    fill_blanks: "fill_blanks",
    ordering: "ordering",
    crossword: "crossword",
    memory_game: "memory_game"
  }

  normalizes :title, with: ->(title) { title.strip }

  validates :exercise_type, :object, presence: true
  validates :title, length: { maximum: 150 }
  validates :description, length: { maximum: 255 }
  validate :title_must_be_present
  validate :content_matches_exercise_type

  TITLE_BLANK_MESSAGE = "Informe o título do exercício.".freeze

  def multiple_sentences_ordering?
    ordering? && object.is_a?(Hash) &&
      object.deep_stringify_keys["format"] == Exercises::ExerciseContentValidator::MULTIPLE_SENTENCES_FORMAT
  end

  private

  def title_must_be_present
    errors.add(:base, TITLE_BLANK_MESSAGE) if title.blank?
  end

  def content_matches_exercise_type
    return if exercise_type.blank?

    result = Exercises::ExerciseContentValidator.call(
      exercise_type:,
      object:,
      attached_image_blob_ids: memory_images_attachments.map(&:blob_id),
      allowed_upload_keys: memory_upload_keys || []
    )
    return if result.errors.empty?

    # A mensagem específica do tipo já explica a ausência de conteúdo.
    errors.delete(:object, :blank)
    result.errors.each { |message| errors.add(:object, message) }
  end
end
