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

  validates :exercise_type, :object, presence: true
  validate :content_matches_exercise_type

  private

  def content_matches_exercise_type
    return if exercise_type.blank?

    result = Exercises::ExerciseContentValidator.call(
      exercise_type:,
      object:,
      attached_image_blob_ids: memory_images_attachments.map(&:blob_id),
      allowed_upload_keys: memory_upload_keys || []
    )
    result.errors.each { |message| errors.add(:object, message) }
  end
end
