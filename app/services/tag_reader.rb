# app/services/tag_reader.rb
require "natto"

class TagReader
  # 文字列から「読み（カタカナ）」を返す
  def self.yomi(text)
    return "" if text.blank?

    nm = Natto::MeCab.new
    yomi = +""

    nm.parse(text) do |n|
      next if n.is_eos?
      feats = (n.feature || "").split(",")
      # MeCab の feature 8番目が読み。無ければ表層系を使う
      y = feats[7].presence || n.surface
      yomi << y
    end

    # ひらがな→カタカナに統一
    yomi.tr("ぁ-ん", "ァ-ン")
  end
end
