class Activity < ApplicationRecord
  include ActiveRecordScope

  belongs_to :school_class, foreign_key: :class_id
  belongs_to :teacher
  has_many :activity_exercises, dependent: :restrict_with_exception
  has_many :exercises, through: :activity_exercises

  before_validation :copy_teacher_from_class

  validates :title, presence: true
  validates :teacher, presence: true

  scope :published, -> { where(published: true) }

  private

  def copy_teacher_from_class
    self.teacher ||= school_class&.teacher
  end
end
