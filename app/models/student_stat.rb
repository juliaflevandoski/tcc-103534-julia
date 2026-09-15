class StudentStat < ApplicationRecord
  belongs_to :student

  validates :student_id, uniqueness: true
  validates :xp, :level, numericality: { greater_than_or_equal_to: 0 }
  validates :level, numericality: { greater_than_or_equal_to: 1 }
end
