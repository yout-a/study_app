# app/helpers/tags_helper.rb
module TagsHelper
  # 先頭文字の種別で大まかに整列（日本語 → 英数字 → その他）
  def bucket_for(str)
    c = str.to_s.strip[0]
    return 2 unless c
    return 1 if c.match?(/[A-Za-z0-9]/)
    return 0 if c.match?(/[一-龯ぁ-んァ-ン]/)
    2
  end

  def sort_tags_gojuon(tags)
    tags.sort_by do |t|
      yomi = TagReader.yomi(t.name)  # ここで読みを取得
      [bucket_for(t.name), yomi, t.id]
    end
  end
end
