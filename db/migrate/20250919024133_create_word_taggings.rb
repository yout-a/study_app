class CreateWordTaggings < ActiveRecord::Migration[7.1]
  def change
    create_table :word_taggings do |t|
      t.references :word, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true

      t.timestamps
    end
  end
end
