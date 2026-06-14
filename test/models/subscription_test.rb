require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  test "monthly amount normalizes recurring frequencies" do
    subscription = subscriptions(:one)

    subscription.avg_amount = 120

    subscription.frequency = "yearly"
    assert_equal 10, subscription.monthly_amount

    subscription.frequency = "quarterly"
    assert_equal 40, subscription.monthly_amount

    subscription.frequency = "weekly"
    assert_in_delta 520, subscription.monthly_amount, 0.01
  end

  test "cancel candidates and watchlist items count as savings candidates" do
    subscription = subscriptions(:one)

    subscription.status = "cancel_candidate"
    assert subscription.savings_candidate?

    subscription.status = "watchlist"
    assert subscription.savings_candidate?

    subscription.status = "keep"
    assert_not subscription.savings_candidate?
  end
end
