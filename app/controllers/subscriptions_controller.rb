class SubscriptionsController < ApplicationController
  before_action :authenticate_user!

  def update
    subscription = Subscription.joins(:upload).find_by!(
      id: params[:id],
      uploads: { user_id: current_user.id }
    )

    subscription.update!(subscription_params)
    redirect_back fallback_location: uploads_path, notice: "Subscription updated."
  end

  private

  def subscription_params
    params.require(:subscription).permit(:status, :user_note)
  end
end
