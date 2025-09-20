class CreateQuestionChoices < ActiveRecord::Migration[7.1]
  def change
    create_table :question_choices do |t|
      t.references :question, null: false, foreign_key: true
      t.text :body
      t.boolean :correct

      t.timestamps
    end
  end
end
