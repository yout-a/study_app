# app/services/meaning_finder.rb
require "net/http"
require "uri"
require "json"
require "erb"
require "cgi"

class MeaningFinder
  class << self
    def call(word:, memo: "", tags: [])
      kw    = build_keywords(word, memo, tags)
      query = build_query_string(word, kw)

      text, src = fetch_best_summary(query: query, prefer_title: word)

      if text.present?
        sanitized = sanitize_plain_text(text)

        # Wikipedia セクション追加
        extra = ""
        if src.present? && src.first[:url].to_s.include?("wikipedia.org")
          wiki_title = src.first[:title].to_s.presence || word
          extra = wikipedia_sections_plain(wiki_title)
        end

        combined = [sanitized, extra].reject(&:blank?).join("\n\n")

        ai = GptWriter.rewrite(
          plain_text: combined,
          word: word,
          memo: memo,
          max_chars: 650
        )

        meaning = ai[:meaning].presence || summarize_ja(word: word, base: combined, memo: memo, target_chars: 650)
        tags_ai = ai[:tags].presence    || SmartTagger.call(text: "#{combined} #{memo}", word: word, memo_keywords: kw, limit: 5)

        # ★★ ここが抜けていた ★★
        return { meaning: meaning, tags: tags_ai, sources: src, fallback: false }
      end

      # 取得失敗 → フォールバック
      summary = offline_fallback(word: word, memo: memo, target_chars: 650) # ← 650に揃える
      tags_fb = SmartTagger.call(text: "#{word} #{memo}", word: word, memo_keywords: kw, limit: 5)
      { meaning: summary, tags: tags_fb, sources: [], fallback: true }
    rescue => e
      Rails.logger.warn("[MeaningFinder] #{e.class}: #{e.message}")
      kw ||= build_keywords(word, memo, tags)
      summary = offline_fallback(word: word, memo: memo, target_chars: 650)
      tags_fb = SmartTagger.call(text: "#{word} #{memo}", word: word, memo_keywords: kw, limit: 5)
      { meaning: summary, tags: tags_fb, sources: [], fallback: true }
    end

    # === フォールバック（文頭は必ず「【word】は」） ===
    def offline_fallback(word:, memo:, target_chars: 500)
      body =
        if memo.present?
          "メモを手掛かりにした暫定の説明です。#{memo.to_s.strip}"
        else
          "オンライン情報の取得に失敗しました。必要に応じて追記してください。"
        end
      ("【#{word}】は " + body)[0, target_chars]
    end

    private

    def sanitize_plain_text(text)   # ← self. を付けてクラスメソッドとして明示
      t = text.to_s
      t = t.sub(/\A[【\[\(（"]?[^「【\(\)\]\}」]{1,50}の意味(?:とは)?[」】\)\]\}:：\-–—]*\s*/u, "")
      t.gsub(/\[[^\]]+\]/, "").gsub(/\s+/, " ").strip
    end

    # メモ・タグを検索キーワードに統合
    def build_keywords(_word, memo, tags)
      memo_keys = memo.to_s.gsub(/[、，;]/, ",").split(/[,\s]+/).map(&:strip).reject(&:blank?)
      tag_keys  = Array(tags).map(&:to_s).map(&:strip).reject(&:blank?)
      (memo_keys + tag_keys).uniq.first(10)
    end

    # クエリ文字列を構築（wordは引用符で完全一致狙い、kwは補助）
    def build_query_string(word, kw)
      w = word.to_s.strip
      pieces = []
      pieces << %Q{"#{w}"} if w.present?
      pieces.concat(kw) if kw.present?
      pieces.join(" ").strip
    end

    def normalize(s)
      s.to_s.tr("　", " ").gsub(/\s+/, " ").strip
    end

    def title_similarity(a, b)
      a = normalize(a); b = normalize(b)
      return 1.0 if a == b
      return 0.9 if a.include?(b) || b.include?(a)
      return 0.7 if a.start_with?(b) || b.start_with?(a)
      inter = (a.chars & b.chars).size.to_f
      base  = [a.size, b.size].max.to_f
      (inter / base).round(3)
    end

    # === 取得戦略 ===
    # 1) exact title → 2) Wikipedia検索 → 3) Wikidata → 4) Wiktionary → 5) DuckDuckGo → 6) DBpedia
    def fetch_best_summary(query:, prefer_title:)
      cache_key = "meaning_finder:v4:#{normalize(query)}"
      if (cached = Rails.cache.read(cache_key))
        return cached
      end

      exact = summary(prefer_title.to_s)
      if exact[:text].present?
        Rails.cache.write(cache_key, [exact[:text], exact[:sources]], expires_in: 18.hours)
        return [exact[:text], exact[:sources]]
      end

      wiki = wikipedia_search_then_summary(query: query, prefer_title: prefer_title)
      if wiki[:text].present?
        Rails.cache.write(cache_key, [wiki[:text], wiki[:sources]], expires_in: 18.hours)
        return [wiki[:text], wiki[:sources]]
      end

      wd = wikidata_description(query)                          # ← 追加実装
      return [wd[:text], wd[:sources]] if wd[:text].present?

      wt = wiktionary_definition(prefer_title)                  # ← 追加実装
      return [wt[:text], wt[:sources]] if wt[:text].present?

      ddg = duckduckgo_ia(query)
      return [ddg[:text], ddg[:sources]] if ddg[:text].present?

      dbp = dbpedia_abstract_ja(prefer_title)
      [dbp[:text], dbp[:sources]]
    rescue => e
      Rails.logger.warn("[MeaningFinder.fetch] #{e.class}: #{e.message}")
      ["", []]
    end

    # --- Wikipedia: 検索 → 最良タイトル → summary ---
    def wikipedia_search_then_summary(query:, prefer_title:)
      quoted = %Q{"#{prefer_title.to_s.strip}"}
      q = ERB::Util.url_encode("#{quoted} intitle:#{prefer_title} #{query}")
      s_url = "https://ja.wikipedia.org/w/api.php?action=query&list=search&format=json&srprop=snippet&srinfo=suggestion&srwhat=text&srenablerewrites=1&srlimit=5&srsearch=#{q}"
      search = http_get_json(s_url)
      arr    = Array(search.dig("query", "search"))

      best  = arr.max_by { |h| title_similarity(h["title"].to_s, prefer_title.to_s) }
      title = (best && best["title"]).presence || prefer_title
      return { text: "", sources: [] } if title.blank?

      res = summary(title.to_s)
      if res[:type] == :disambiguation && arr.size > 1
        second = (arr - [best]).max_by { |h| title_similarity(h["title"].to_s, prefer_title.to_s) }
        res = summary(second["title"].to_s) if second && second["title"].present?
      end
      res
    rescue
      { text: "", sources: [] }
    end

    def summary(title)
      t   = ERB::Util.url_encode(title)
      url = "https://ja.wikipedia.org/api/rest_v1/page/summary/#{t}"
      json = http_get_json(url)
      return { text: "", sources: [] } if json.blank? || json["extract"].blank?

      type_sym = (json["type"].to_s == "disambiguation") ? :disambiguation : :article
      text = json["extract"].to_s.strip
      src  = [{
        title: json.dig("titles", "normalized") || title,
        url:   json.dig("content_urls", "desktop", "page") || "https://ja.wikipedia.org"
      }]
      { text: text, sources: src, type: type_sym }
    end

    # --- Wikidata: 検索→日本語説明（追加） ---
    def wikidata_description(query)
      q = ERB::Util.url_encode(query.to_s.strip)
      url = "https://www.wikidata.org/w/api.php?action=wbsearchentities&format=json&language=ja&uselang=ja&limit=1&search=#{q}"
      json = http_get_json(url)

      hit = Array(json["search"]).first
      return { text: "", sources: [] } if hit.blank?

      desc  = hit["description"].to_s.strip
      label = hit["label"].to_s.strip
      page  = "https://www.wikidata.org/wiki/#{hit["id"]}"

      { text: desc, sources: [{ title: label.presence || query, url: page }] }
    rescue
      { text: "", sources: [] }
    end

    # --- Wiktionary: プレーンテキスト定義（追加） ---
    def wiktionary_definition(title)
      t = ERB::Util.url_encode(title.to_s.strip)
      url = "https://ja.wiktionary.org/w/api.php?action=query&prop=extracts&explaintext=1&format=json&redirects=1&titles=#{t}"
      json = http_get_json(url)

      page    = json.dig("query", "pages")&.values&.first
      extract = page.to_h["extract"].to_s.strip
      return { text: "", sources: [] } if extract.blank?

      text = extract.lines.first(5).join(" ").gsub(/\s+/, " ").strip
      src  = [{ title: page["title"] || title, url: "https://ja.wiktionary.org/wiki/#{t}" }]
      { text: text, sources: src }
    rescue
      { text: "", sources: [] }
    end

    # --- DuckDuckGo IA ---
    def duckduckgo_ia(query)
      q   = ERB::Util.url_encode(query)
      url = "https://api.duckduckgo.com/?q=#{q}&format=json&no_redirect=1&no_html=1"
      json = http_get_json(url)

      text = json["AbstractText"].to_s.strip
      if text.blank?
        rel = Array(json["RelatedTopics"]).find { |e| e.is_a?(Hash) && e["Text"].present? }
        text = rel.to_h["Text"].to_s.strip
      end

      src = [{ title: query, url: json["AbstractURL"].presence || "https://duckduckgo.com/?q=#{q}" }]
      { text: text, sources: src }
    rescue
      { text: "", sources: [] }
    end

    # --- DBpedia（日本語abstract） ---
    def dbpedia_abstract_ja(query)
      q = ERB::Util.url_encode(query)
      look = http_get_json("https://lookup.dbpedia.org/api/search?query=#{q}&maxResults=1")
      uri  = Array(look["docs"]).dig(0, "resource")[0] rescue nil
      return { text: "", sources: [] } if uri.blank?

      sparql = <<~SPARQL
        SELECT ?abs WHERE {
          <#{uri}> <http://dbpedia.org/ontology/abstract> ?abs .
          FILTER (lang(?abs) = 'ja')
        } LIMIT 1
      SPARQL
      ep = URI("https://ja.dbpedia.org/sparql")
      ep.query = URI.encode_www_form(query: sparql, format: "application/sparql-results+json")
      res = http_get_json(ep)
      text = res.dig("results","bindings",0,"abs","value").to_s
      { text: text, sources: [{ title: "DBpedia", url: uri }] }
    rescue
      { text: "", sources: [] }
    end

    # --- 共通HTTP(JSON) ---
    # 好みに応じて .env で上書きできるように
    HTTP_OPEN_TIMEOUT = ENV.fetch("HTTP_OPEN_TIMEOUT", "5").to_i   # 既定 5s
    HTTP_READ_TIMEOUT = ENV.fetch("HTTP_READ_TIMEOUT", "12").to_i  # 既定 12s
    HTTP_RETRY        = ENV.fetch("HTTP_RETRY", "2").to_i          # 既定 2回リトライ

    # --- 共通HTTP(JSON) ---
    def http_get_json(url_or_uri, tries: HTTP_RETRY)
      uri = url_or_uri.is_a?(URI) ? url_or_uri : URI.parse(url_or_uri)

      Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: HTTP_OPEN_TIMEOUT,
        read_timeout: HTTP_READ_TIMEOUT
      ) do |http|
        res = http.get(uri.request_uri, { "User-Agent" => "StudyApp/1.0 (+rails)" })
        return JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[MeaningFinder.http] HTTP #{res.code} #{uri}")
      end

      {}
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT => e
      Rails.logger.warn("[MeaningFinder.http] timeout #{e.class} #{uri}")
      if (tries -= 1) >= 0
        sleep(0.2 * (HTTP_RETRY - tries)) # ちょいバックオフ
        retry
      end
      {}
    rescue => e
      Rails.logger.warn("[MeaningFinder.http] #{e.class}: #{e.message} #{uri}")
      {}
    end

    # --- セクション構成の簡易サマリ（人物/製品にも対応） ---
    def summarize_ja(word:, base:, memo:, target_chars: 500)
      text = base.to_s.gsub(/\[[^\]]+\]/, "").gsub(/\s+/, " ").strip
      return offline_fallback(word: word, memo: memo, target_chars: target_chars) if text.blank?

      sents = text.split(/(?<=。)/)

      # 概要（先頭から情報密度の高い2文）
      overview = sents.first(2).join

      # 略歴: 年の入った文 / デビュー・発売・公開・受賞などの出来事
      bio_keys = /(19|20)\d{2}年|デビュー|活動開始|発売|公開|受賞|設立|解散|復帰|加入|卒業|結成/u
      bio = sents.select { |s| s =~ bio_keys }.uniq.first(8)
      # 年の数字を抽出しソート（年が無いものは後ろ）
      bio = bio.sort_by { |s| (s[/((?:19|20)\d{2})年/, 1] || "9999").to_i }

      # エピソード/特徴
      epi_keys = /愛称|挨拶|ファン|ASMR|配信|趣味|特徴|身長|誕生日|デザイン|衣装|キャラクター|受賞|代表作|別名|異名/u
      episodes = (sents - bio).select { |s| s =~ epi_keys }.uniq.first(6)

      # 組み立て
      out = +"【#{word}】は " + overview
      out << "\n\n— 概要\n" << (sents[0] || "")
      if bio.any?
        out << "\n\n— 略歴\n"
        bio.first(6).each { |b| out << "・" << b.sub(/。$/, "。") }
      end
      if episodes.any?
        out << "\n\n— 人物・エピソード\n"
        episodes.first(5).each { |e| out << "・" << e.sub(/。$/, "。") }
      end

      # 文字数制限
      out = out[0, target_chars]
      out << "…" if out.size == target_chars && out[-1] != "。"
      out
    end
    # === Wikipedia セクションをテキストで取得（概要/略歴/人物） ===
    def wikipedia_sections_plain(title)
      idx = wikipedia_section_indices(title)
      return "" if idx.values.all?(&:nil?)

      pieces = []

      if idx[:overview]
        html = wikipedia_section_html(title, idx[:overview])
        ov   = section_html_to_text(html)
        pieces << "概要\n" << ov if ov.present?
      end

      if idx[:bio]
        html = wikipedia_section_html(title, idx[:bio])
        bio  = section_html_to_text(html)
        # 年が入った行を優先して最大6件
        bio_lines = bio.split(/\R/).map(&:strip).reject(&:blank?)
        bio_lines = bio_lines.select { |l| l =~ /(18|19|20)\d{2}年/ }.first(6)
        pieces << "略歴\n" << bio_lines.map { |l| "・#{l}" }.join("\n") if bio_lines.any?
      end

      if idx[:episode]
        html = wikipedia_section_html(title, idx[:episode])
        ep   = section_html_to_text(html)
        ep_lines = ep.split(/\R/).map(&:strip).reject(&:blank?).first(10)
        pieces << "人物・エピソード\n" << ep_lines.map { |l| "・#{l}" }.join("\n") if ep_lines.any?
      end

      pieces.join("\n")
    rescue
      ""
    end

    # 対象セクションの index を探す（概要/来歴(経歴/略歴)/人物(エピソード/人物像/特徴)）
    def wikipedia_section_indices(title)
      t = ERB::Util.url_encode(title.to_s)
      url = "https://ja.wikipedia.org/w/api.php?action=parse&page=#{t}&prop=sections&format=json&redirects=1"
      json = http_get_json(url)
      secs = Array(json.dig("parse", "sections"))

      find_idx = ->(patterns) do
        pat = Regexp.union(patterns)
        found = secs.find { |s| s["line"].to_s.match?(pat) }
        found && found["index"]
      end

      {
        overview: find_idx.call([/概要/]),
        bio:      find_idx.call([/来歴/, /経歴/, /略歴/, /年表/, /活動/]),
        episode:  find_idx.call([/人物/, /人物像/, /エピソード/, /特徴/])
      }
    rescue
      { overview: nil, bio: nil, episode: nil }
    end

    # セクションHTMLを取得
    def wikipedia_section_html(title, index)
      return "" if index.blank?
      t = ERB::Util.url_encode(title.to_s)
      url = "https://ja.wikipedia.org/w/api.php?action=parse&page=#{t}&prop=text&section=#{index}&format=json&redirects=1"
      json = http_get_json(url)
      html = json.dig("parse", "text", "*").to_s
      html
    rescue
      ""
    end

    # HTML → プレーンテキスト（箇条書きは行に）
    def section_html_to_text(html)
      return "" if html.blank?
      txt = html.dup
      txt.gsub!(/<\/?li[^>]*>/i, "\n")
      txt.gsub!(/<br\s*\/?>/i, "\n")
      txt.gsub!(/<\/p>/i, "\n")
      txt = CGI.unescapeHTML(txt.gsub(/<[^>]+>/, ""))
      txt.lines.map(&:strip).reject(&:blank?).join("\n")
    end
  end
end

