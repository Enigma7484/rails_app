class CreateMerchantAliases < ActiveRecord::Migration[8.1]
  def change
    create_table :merchant_aliases do |t|
      t.references :user, null: false, foreign_key: true
      t.string :raw_name, null: false
      t.string :canonical_name, null: false

      t.timestamps
    end

    add_index :merchant_aliases, [:user_id, :raw_name], unique: true
  end
end
