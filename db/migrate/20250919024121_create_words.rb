# db/migrate/20xxxxxxxxxx_create_words.rb
class CreateWords < ActiveRecord::Migration[7.1]
  def change
    create_table :words do |t|
      t.references :user, null: false, foreign_key: true, type: :bigint
      t.string :term, null: false
      t.text :meaning
      t.text :memo
      t.timestamps
    end
    add_index :words, [:user_id, :term], unique: true
  end
end
