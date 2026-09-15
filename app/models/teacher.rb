class Teacher < ApplicationRecord
  include ActiveRecordScope
  has_secure_password

  has_many :school_classes, dependent: :restrict_with_exception
  has_many :activities, dependent: :restrict_with_exception
  has_many :exercises, dependent: :restrict_with_exception

  validates :username, :email, :name, presence: true
  validates :username, :email, uniqueness: true
end
