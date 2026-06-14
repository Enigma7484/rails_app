class AddCancellationWorkflowToSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :subscriptions, :cancellation_url, :string
    add_column :subscriptions, :cancellation_notes, :text
    add_column :subscriptions, :cancelled_on, :date
    add_column :subscriptions, :next_check_date, :date
  end
end
