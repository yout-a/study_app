class CreateTestQuestions < ActiveRecord::Migration[7.1]
  def change
    create_table :test_questions do |t|
      t.bigint  :test_id,     null: false
      t.bigint  :question_id, null: false
      t.integer :position,    null: false
      t.timestamps
    end
    add_index :test_questions, [:test_id, :position], unique: true
    add_foreign_key :test_questions, :tests,     column: :test_id
    add_foreign_key :test_questions, :questions, column: :question_id
  end
end
