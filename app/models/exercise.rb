class Exercise < ApplicationRecord
  include ActiveRecordScope

  belongs_to :teacher
  has_many :activity_exercises, dependent: :restrict_with_exception
  has_many :activities, through: :activity_exercises
  has_many_attached :memory_images

  enum :exercise_type, {
    quiz: "quiz",
    fill_blanks: "fill_blanks",
    ordering: "ordering",
    crossword: "crossword",
    memory_game: "memory_game"
  }

  validates :exercise_type, :object, presence: true
end
