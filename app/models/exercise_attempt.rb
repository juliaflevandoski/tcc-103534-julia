class ExerciseAttempt < ApplicationRecord
  include ActiveRecordScope

  belongs_to :student
  belongs_to :activity_exercise

  validates :answer, :correct, presence: true
  validates :score, numericality: { greater_than_or_equal_to: 0 }
  validates :time_spent, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
