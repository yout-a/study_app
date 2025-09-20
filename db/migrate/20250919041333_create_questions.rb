class CreateQuestions < ActiveRecord::Migration[7.1]
  def change
    create_table :questions do |t|
      t.references :word, null: false, foreign_key: true
      t.text :body

      t.timestamps
    end
  end
end
