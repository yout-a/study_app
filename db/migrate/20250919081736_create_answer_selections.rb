class CreateAnswerSelections < ActiveRecord::Migration[7.1]
  def change
    create_table :answer_selections do |t|
      t.references :answer, null: false, foreign_key: true
      t.references :question_choice, null: false, foreign_key: true

      t.timestamps
    end
  end
end
