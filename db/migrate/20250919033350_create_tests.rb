class CreateTests < ActiveRecord::Migration[7.1]
  def change
    create_table :tests do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :scope
      t.integer :item_count
      t.integer :mode
      t.integer :grading
      t.integer :status
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end
  end
end
