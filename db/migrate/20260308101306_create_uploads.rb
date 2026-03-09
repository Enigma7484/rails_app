class CreateUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :uploads do |t|
      t.jsonb :analysis_result

      t.timestamps
    end
  end
end
