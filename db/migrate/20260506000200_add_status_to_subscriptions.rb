class AddStatusToSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :subscriptions, :status, :string, null: false, default: "detected"
    add_column :subscriptions, :user_note, :text
  end
end
