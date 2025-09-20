class CreateWords < ActiveRecord::Migration[7.1]
  def change
    create_table :words do |t|
      t.references :user, null: false, foreign_key: true
      t.string :term
      t.text :meaning
      t.text :memo

      t.timestamps
    end
  end
end
