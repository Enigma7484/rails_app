class Subscription < ApplicationRecord
  belongs_to :upload

  STATUSES = %w[detected confirmed active cancelled ignored watchlist].freeze

  validates :status, inclusion: { in: STATUSES }

  before_validation :set_default_status

  private

  def set_default_status
    self.status ||= "detected"
  end
end
