require "net/http"
require "uri"
require "json"
require "erb"

class MeaningFinder
  class << self
    def call(word:, memo: "")
      kw    = build_keywords(word, memo)
      query = kw.join(" ")

      text, src = fetch_best_summary(query: query, prefer_title: word)

      if text.present?
        # ★ ChatGPT で 500字・自然文に整形＋タグ提案（まずAIに任せる）
        ai = GptWriter.rewrite(plain_text: text, word: word, memo: memo, max_chars: 500)

        meaning = ai[:meaning].presence || summarize_ja(word: word, base: text, memo: memo, target_chars: 500)
        tags    = ai[:tags].presence    || SmartTagger.call(text: "#{text} #{memo}", word: word, memo_keywords: kw, limit: 5)

        return { meaning: meaning, tags: tags, sources: src, fallback: false }
      end

      # 取得失敗のときはオフライン整形
      summary = offline_fallback(word: word, memo: memo, target_chars: 500)
      tags    = SmartTagger.call(text: "#{word} #{memo}", word: word, memo_keywords: kw, limit: 5)
      { meaning: summary, tags: tags, sources: [], fallback: true }
    rescue => e
      Rails.logger.warn("[MeaningFinder] #{e.class}: #{e.message}")
      kw ||= build_keywords(word, memo)
      summary = offline_fallback(word: word, memo: memo, target_chars: 500)
      tags    = SmartTagger.call(text: "#{word} #{memo}", word: word, memo_keywords: kw, limit: 5)
      { meaning: summary, tags: tags, sources: [], fallback: true }
    end


    # === フォールバック：メモを取り入れて約300字で整形 ===
    def offline_fallback(word:, memo:, target_chars: 500)
      body = memo.present? ?
        "（オンライン取得に失敗。メモを基に暫定の説明を生成）\n#{memo.to_s.strip}" :
        "（オンライン取得に失敗。必要に応じて追記してください）"
      ("【#{word}】の意味\n" + body)[0, target_chars]
    end


    private

    # メモの語を検索クエリに統合
    def build_keywords(word, memo)
      memo_keys = memo.to_s.gsub(/[、，;]/, ",").split(/[,\s]+/).map(&:strip).reject(&:blank?)
      ([word.to_s.strip] + memo_keys).uniq.first(8)
    end

       # 上位: Wikipedia → Wikidata → Wiktionary → DuckDuckGo → DBpedia
    def fetch_best_summary(query:, prefer_title:)
      cache_key = "meaning_finder:v3:#{query}"
      cached = Rails.cache.read(cache_key)
      return cached if cached


      wiki = wikipedia_search_then_summary(query: query, prefer_title: prefer_title)
      if wiki[:text].present?
        Rails.cache.write(cache_key, [wiki[:text], wiki[:sources]], expires_in: 18.hours)
        return [wiki[:text], wiki[:sources]]
      end

      wd = wikidata_description(query)
      return [wd[:text], wd[:sources]] if wd[:text].present?

      wt = wiktionary_definition(prefer_title)
      return [wt[:text], wt[:sources]] if wt[:text].present?

      ddg = duckduckgo_ia(query)
      return [ddg[:text], ddg[:sources]] if ddg[:text].present?

      dbp = dbpedia_abstract_ja(prefer_title)
      [dbp[:text], dbp[:sources]]
    rescue => e
      Rails.logger.warn("[MeaningFinder.fetch] #{e.class}: #{e.message}")
      ["", []]
    end

    # --- Wikidata: 検索→エンティティ説明(ja) ---
    def wikipedia_search_then_summary(query:, prefer_title:)
      q = ERB::Util.url_encode(query)
      s_url = "https://ja.wikipedia.org/w/api.php?action=query&list=search&format=json&srprop=&srlimit=1&srsearch=#{q}"
      search = http_get_json(s_url)
      title  = search.dig("query", "search", 0, "title") || prefer_title
      return { text: "", sources: [] } if title.blank?
      summary(title.to_s)
    rescue
      { text: "", sources: [] }
    end

    def summary(title)
      t   = ERB::Util.url_encode(title)
      url = "https://ja.wikipedia.org/api/rest_v1/page/summary/#{t}"
      json = http_get_json(url)
      return { text: "", sources: [] } if json.blank? || json["extract"].blank?

      text = json["extract"].to_s.strip
      src  = [{
        title: json.dig("titles", "normalized") || title,
        url:   json.dig("content_urls", "desktop", "page") || "https://ja.wikipedia.org"
      }]
      { text: text, sources: src }
    end

    # --- DuckDuckGo IA: 要約テキスト ---
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
    def http_get_json(url_or_uri)
      uri = url_or_uri.is_a?(URI) ? url_or_uri : URI.parse(url_or_uri)
      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: uri.scheme == "https",
                      read_timeout: 6, open_timeout: 3) do |http|
        res = http.get(uri.request_uri, { "User-Agent" => "StudyApp/1.0 (+rails)" })
        return JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
      end
      {}
    rescue
      {}
    end

    # --- 約300字サマリ（※凍結文字列対策済み） ---
    def summarize_ja(word:, base:, memo:, target_chars: 500)
      base = base.to_s.gsub(/\[[^\]]+\]/, "").gsub(/\s+/, " ").strip
      return offline_fallback(word: word, memo: memo, target_chars: target_chars) if base.blank?

      sentences = base.split(/(?<=。)/)
      picked = String.new
      sentences.each do |s|
        break if picked.size >= target_chars
        picked << s
      end

      if memo.present?
        note = "（メモ: #{memo.to_s.strip}）"
        rest = target_chars - picked.size
        picked << note[0, rest] if rest > 0
      end

      picked = picked[0, target_chars]
      picked << "…" if picked.size == target_chars && picked[-1] != "。"
      "【#{word}】の意味\n" + picked
    end
  end
end
