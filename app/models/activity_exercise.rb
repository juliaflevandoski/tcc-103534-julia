class ActivityExercise < ApplicationRecord
  self.table_name = "activities_exercises"

  include ActiveRecordScope

  belongs_to :activity
  belongs_to :exercise
  has_many :exercise_attempts, dependent: :restrict_with_exception

  validates :position, :points, presence: true
  validates :position, uniqueness: { scope: :activity_id }
  validates :position, :points, numericality: { greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:position) }
end
