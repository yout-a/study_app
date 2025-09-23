# db/migrate/20xxxxxxxxxx_create_word_taggings.rb
class CreateWordTaggings < ActiveRecord::Migration[7.1]
  def change
    create_table :word_taggings do |t|
      t.references :word, null: false, foreign_key: true, type: :bigint
      t.references :tag,  null: false, foreign_key: true, type: :bigint
      t.timestamps
    end
    add_index :word_taggings, [:word_id, :tag_id], unique: true
  end
end
