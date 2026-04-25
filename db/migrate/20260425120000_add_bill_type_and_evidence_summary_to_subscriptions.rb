class AddBillTypeAndEvidenceSummaryToSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :subscriptions, :bill_type, :string
    add_column :subscriptions, :evidence_summary, :text
  end
end
