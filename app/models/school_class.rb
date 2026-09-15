class SchoolClass < ApplicationRecord
  self.table_name = "classes"

  include ActiveRecordScope

  belongs_to :teacher
  has_many :class_students, dependent: :restrict_with_exception
  has_many :students, through: :class_students
  has_many :activities, dependent: :restrict_with_exception

  before_validation :assign_access_code, on: :create

  validates :name, :access_code, presence: true
  validates :access_code, uniqueness: true

  private

  def assign_access_code
    self.access_code ||= loop do
      code = SecureRandom.alphanumeric(8).upcase
      break code unless self.class.exists?(access_code: code)
    end
  end
end
