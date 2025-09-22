# frozen_string_literal: true
class SmartTagger
  # 検索に弱い一般語・ノイズを除外
  STOPWORDS = %w[
    意味 とは こと ため よう 等 など これ それ あれ です ます
    年 月 日 時 現在 以降 以前 日本 国内 海外 一般 概要 公式
    the and of for to in on by with from as is are was were be been being
  ].freeze

  KATAKANA = /\p{Katakana}{2,}/
  KANJI    = /\p{Han}{2,}/
  LATIN    = /\p{Latin}{2,}/

  def self.call(text:, word:, memo_keywords:, limit: 5)
    text = text.to_s

    # 候補の収集：本文＋メモ
    candidates = []
    # 1) メモのキーワードは重み高
    memo_keywords.each { |k| candidates << [normalize(k), 3.0] }

    # 2) 本文から固有名詞っぽい表現（カタカナ/漢字/ラテン語）
    top = text[0, 600] # 冒頭に寄るほど強い
    tokens = tokenize(top)
    freq   = tokens.tally

    freq.each do |tok, c|
      next if STOPWORDS.include?(tok) || tok.size <= 1
      w = 1.0
      w += 0.6 if tok.match?(KATAKANA)
      w += 0.4 if tok.match?(LATIN)
      candidates << [tok, w + c * 0.8]
    end

    # 3) メインワードも候補に
    candidates << [normalize(word), 2.0]

    # スコア集約
    scored = {}
    candidates.each do |name, score|
      next if name.blank? || STOPWORDS.include?(name)
      scored[name] = (scored[name] || 0) + score
    end

    # 並べ替え→上位を返す（重複・空・ノイズ除去）
    scored.sort_by { |(_, s)| -s }
          .map(&:first)
          .reject { |t| t.blank? || t.size < 2 }
          .uniq
          .first(limit)
  end

  def self.normalize(s)
    s.to_s.downcase.strip
  end

  # 日本語の簡易トークナイズ（実務ではMeCab推奨）
  def self.tokenize(str)
    # 記号・数字単独は除去
    raw = str.gsub(/[^\p{Han}\p{Hiragana}\p{Katakana}\p{Latin}\d]+/, " ")
             .split(/\s+/)
             .map { |w| normalize(w) }
             .reject { |w| w.empty? || w =~ /^\d+$/ }
    # 連続する漢字やカタカナ、ラテン語だけを優先
    raw.select { |w| w.match?(KATAKANA) || w.match?(KANJI) || w.match?(LATIN) }
  end
end
