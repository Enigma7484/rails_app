class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      t.references :upload, null: false, foreign_key: true
      t.string :merchant
      t.string :merchant_normalized
      t.string :category
      t.text :description
      t.string :frequency
      t.decimal :avg_amount
      t.date :last_paid
      t.date :next_expected
      t.decimal :confidence
      t.text :evidence

      t.timestamps
    end
  end
end
