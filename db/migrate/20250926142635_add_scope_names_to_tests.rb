class AddScopeNamesToTests < ActiveRecord::Migration[7.1]
  def change
    add_column :tests, :scope_names, :text, comment: "選択時のタグ名を履歴として固定保存。カンマ区切り"
  end
end
