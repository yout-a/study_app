# db/migrate/20xxxxxxxxxx_create_tags.rb
class CreateTags < ActiveRecord::Migration[7.1]
  def change
    create_table :tags do |t|
      t.references :user, null: false, foreign_key: true, type: :bigint
      t.string :name, null: false
      t.timestamps
    end
    add_index :tags, [:user_id, :name], unique: true, name: "index_tags_on_user_id_and_name"
  end
end
