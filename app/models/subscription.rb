class Subscription < ApplicationRecord
  belongs_to :upload

  STATUSES = %w[detected confirmed active keep cancel_candidate cancelled ignored watchlist].freeze

  validates :status, inclusion: { in: STATUSES }

  before_validation :set_default_status

  def monthly_amount
    amount = avg_amount.to_f

    case frequency.to_s.downcase
    when "weekly"
      amount * 52 / 12
    when "biweekly"
      amount * 26 / 12
    when "quarterly"
      amount / 3
    when "yearly"
      amount / 12
    else
      amount
    end
  end

  def annual_amount
    monthly_amount * 12
  end

  def savings_candidate?
    status.in?(%w[cancel_candidate watchlist])
  end

  def cancelled?
    status == "cancelled"
  end

  private

  def set_default_status
    self.status ||= "detected"
  end
end
