class CreateTestTaggings < ActiveRecord::Migration[7.1]
  def change
    create_table :test_taggings do |t|
      t.references :test, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.index [:test_id, :tag_id], unique: true
      t.timestamps
    end
  end
end
