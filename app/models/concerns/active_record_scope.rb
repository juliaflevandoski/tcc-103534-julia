module ActiveRecordScope
  extend ActiveSupport::Concern

  included do
    scope :active, -> { where(active: true) }
  end
end
