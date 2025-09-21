class AddUniqueIndexToWordsOnUserIdAndTerm < ActiveRecord::Migration[7.1]
  def change
    # 念のため null 禁止（既に null が無い前提）
    change_column_null :words, :term, false

    # MariaDB で utf8mb4 の場合は長さ指定推奨
    add_index :words, [:user_id, :term],
              unique: true,
              length: { term: 191 }, # <= 重要（MySQL でも互換）
              name: "index_words_on_user_id_and_term_unique"
  end
end
