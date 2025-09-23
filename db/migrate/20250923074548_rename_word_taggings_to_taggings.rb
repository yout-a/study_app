# db/migrate/XXXXXXXXXXXX_rename_word_taggings_to_taggings.rb
class RenameWordTaggingsToTaggings < ActiveRecord::Migration[7.1]
  def change
    # テーブル名を統一
    rename_table :word_taggings, :taggings

    # 念のためユニークインデックスを保証（既存なら何もしない）
    add_index :taggings, [:word_id, :tag_id], unique: true unless index_exists?(:taggings, [:word_id, :tag_id])
  end
end
