class AddUserToUploads < ActiveRecord::Migration[8.1]
  def change
    add_reference :uploads, :user, null: true, foreign_key: true
  end
end
