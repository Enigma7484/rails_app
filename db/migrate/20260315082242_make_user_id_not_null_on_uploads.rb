class MakeUserIdNotNullOnUploads < ActiveRecord::Migration[8.0]
  def change
    change_column_null :uploads, :user_id, false
  end
end