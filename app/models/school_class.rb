class SchoolClass < ApplicationRecord
  self.table_name = "classes"

  include ActiveRecordScope

  belongs_to :teacher
  has_many :class_students, foreign_key: :class_id, dependent: :restrict_with_exception
  has_many :students, through: :class_students
  has_many :activities, foreign_key: :class_id, dependent: :restrict_with_exception
  has_many :class_posts, foreign_key: :class_id, dependent: :restrict_with_exception

  before_validation :assign_access_code, on: :create

  # Maior inteiro que a coluna INTEGER do SQLite (8 bytes) consegue armazenar.
  MAX_XP_POINTS = 2**63 - 1

  normalizes :name, with: ->(name) { name.strip }

  validates :name, :access_code, presence: true
  validates :name, length: { maximum: 50 }
  validates :description, length: { maximum: 255 }
  validates :access_code, uniqueness: true
  validates :xp_points, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_XP_POINTS }, allow_nil: true

  private

  def assign_access_code
    self.access_code ||= loop do
      code = SecureRandom.alphanumeric(8).upcase
      break code unless self.class.exists?(access_code: code)
    end
  end
end
