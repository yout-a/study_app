# app/services/meaning_finder.rb
require "net/http"
require "uri"
require "json"
require "erb"
require "cgi"

class MeaningFinder
  # 単語だけを拾うためのパターン（漢字/カタカナ/英字/混在の固有名）
  TERM_PATTERN = /
    (?:[一-龥々]{2,8})                 | # 漢字  2-8
    (?:[ァ-ヶー]{2,15})                | # カタカナ 2-15（長め）
    (?:[A-Za-z]{3,20})                | # 英字 3-20
    (?:[一-龥々]{1,4}[ァ-ヶー]{1,10}) | # 漢＋カナ 混在
    (?:[ァ-ヶー]{1,4}[一-龥々]{1,10})
  /x.freeze


  class << self
    # -------------------------------
    # メイン入口
    # -------------------------------
    def call(word:, memo: "", tags: [])
      word = word.to_s.strip
      memo = memo.to_s.strip

      kw    = build_keywords(word, memo, tags)
      query = build_query_string(word, kw)
      text, src = fetch_best_summary(query: query, prefer_title: word)

      if text.present?
        sanitized = sanitize_plain_text(text)

        # Wikipedia セクション（概要/略歴/人物・エピソード）を追記
        extra = ""
        if src.present? && src.first[:url].to_s.include?("wikipedia.org")
          wiki_title = src.first[:title].to_s.presence || word
          extra = wikipedia_sections_plain(wiki_title)
        end

        combined = [sanitized, extra].reject(&:blank?).join("\n\n")
        hint     = type_hint_from(tags, memo)

        ai = GptWriter.rewrite(
          plain_text: combined,
          word:       word,
          memo:       memo,
          max_chars:  500,
          type_hint:  hint
        )

        # LLM が壊れた文字列（Ruby風）を返すことがあるのでガード
        ai_meaning = ai[:meaning]
        if ai_meaning.is_a?(String) && ai_meaning.strip.start_with?("{:meaning")
          ai_meaning = nil
        end

        fb       = summarize_ja(word: word, base: combined, memo: memo, tags: tags, target_chars: 500)
        meaning  = ai_meaning.presence || fb[:meaning]
        meaning  = hard_limit(meaning, 500)

        # タグは “単語のみ” で最終整形（失敗しても単語抽出にフォールバック）
        tags_ai =
          begin
            finalize_tags(
              ai_tags: ai[:tags],
              text:    combined,
              memo:    memo,
              word:    word,
              kw:      kw,
              limit:   5
            )
          rescue => e
            Rails.logger.warn("[MeaningFinder.tags] #{e.class}: #{e.message}")
            extract_terms("#{combined} #{memo} #{word}").first(5)
          end

        return { meaning: meaning, tags: tags_ai, sources: src, fallback: false }
      end

      # 取得失敗 → フォールバック
      summary = offline_fallback(word: word, memo: memo, target_chars: 500)
      tags_fb = extract_terms("#{word} #{memo}").first(5)
      { meaning: summary, tags: tags_fb, sources: [], fallback: true }
    rescue => e
      Rails.logger.warn("[MeaningFinder] #{e.class}: #{e.message}")
      kw ||= build_keywords(word, memo, tags)
      summary = offline_fallback(word: word, memo: memo, target_chars: 500)
      tags_fb = extract_terms("#{word} #{memo}").first(5)
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

    # -------------------------------
    # テキスト整形・キーワード
    # -------------------------------
    def sanitize_plain_text(text)
      t = text.to_s
      t = t.sub(/\A[【\[\(（"]?[^「【\(\)\]\}」]{1,50}の意味(?:とは)?[」】\)\]\}:：\-–—]*\s*/u, "")
      t.gsub(/\[[^\]]+\]/, "").gsub(/\s+/, " ").strip
    end

    def build_keywords(_word, memo, tags)
      memo_keys = memo.to_s.gsub(/[、，;]/, ",").split(/[,\s]+/).map(&:strip).reject(&:blank?)
      tag_keys  = Array(tags).map(&:to_s).map(&:strip).reject(&:blank?)
      (memo_keys + tag_keys).uniq.first(10)
    end

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

    # -------------------------------
    # 要約の取得戦略
    # -------------------------------
    # 1) exact title → 2) Wikipedia検索 → 3) Wikidata → 4) Wiktionary → 5) DuckDuckGo → 6) DBpedia
    def fetch_best_summary(query:, prefer_title:)
      cache_key = "meaning_finder:v4:#{normalize(query)}:#{normalize(prefer_title)}"
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
      t   = ERB::Util.url_encode(title.to_s.strip)
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

    # --- Wikidata: 検索→日本語説明 ---
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

    # --- Wiktionary: プレーンテキスト定義 ---
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
    HTTP_OPEN_TIMEOUT = ENV.fetch("HTTP_OPEN_TIMEOUT", "5").to_i
    HTTP_READ_TIMEOUT = ENV.fetch("HTTP_READ_TIMEOUT", "12").to_i
    HTTP_RETRY        = ENV.fetch("HTTP_RETRY", "2").to_i

    def http_get_json(url_or_uri, tries: HTTP_RETRY)
      uri = url_or_uri.is_a?(URI) ? url_or_uri : URI.parse(url_or_uri)

      Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: HTTP_OPEN_TIMEOUT,
        read_timeout: HTTP_READ_TIMEOUT
      ) do |http|
        res = http.get(uri.request_uri, {
          "User-Agent"      => "StudyApp/1.0 (+rails)",
          "Accept"          => "application/json",
          "Accept-Language" => "ja,en;q=0.7"
        })
        return JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[MeaningFinder.http] HTTP #{res.code} #{uri}")
      end
      {}
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT => e
      Rails.logger.warn("[MeaningFinder.http] timeout #{e.class} #{uri}")
      if (tries -= 1) >= 0
        sleep(0.2 * (HTTP_RETRY - tries))
        retry
      end
      {}
    rescue => e
      Rails.logger.warn("[MeaningFinder.http] #{e.class}: #{e.message} #{uri}")
      {}
    end

    # -------------------------------
    # LLM 整形
    # -------------------------------
    def summarize_ja(word:, base:, memo:, tags:, target_chars: 500)
      hint = type_hint_from(tags, memo)
      out  = GptWriter.rewrite(
        plain_text: base, word: word, memo: memo,
        max_chars: target_chars, type_hint: hint
      )
      out[:meaning] = hard_limit(out[:meaning], target_chars)
      out
    end

    def type_hint_from(tags, memo)
      arr = Array(tags).map(&:to_s) + memo.to_s.scan(/#\S+/)
      a = arr.map(&:downcase)
      return "person" if a.any? { |s|
        s.include?("人物") || s.include?("#人物") ||
        s.include?("vtuber") || s.include?("youtuber") ||
        s.include?("声優") || s.include?("俳優") || s.include?("歌手")
      }
      return "thing" if a.any? { |s|
        s.include?("物") || s.include?("#物") ||
        s.include?("製品") || s.include?("商品") ||
        s.include?("道具") || s.include?("デバイス") || s.include?("ガジェット")
      }
      nil
    end

    def hard_limit(text, max)
      s = text.to_s.strip
      m = max.to_i
      return s if m <= 0 || s.size <= m

      body = s[0, m - 1].rstrip   # 省略記号分を確保
      body + "…"                  # 仕上がりは必ず m 文字以内
    end

    # -------------------------------
    # Wikipedia セクション抽出
    # -------------------------------
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

    def wikipedia_section_indices(title)
      t = ERB::Util.url_encode(title.to_s)
      url = "https://ja.wikipedia.org/w/api.php?action=parse&page=#{t}&prop=sections&format=json&redirects=1"
      json = http_get_json(url)
      secs = Array(json.dig("parse", "sections"))

      find_idx = ->(patterns) do
        pat = Regexp.union(patterns)
        found = secs.find { |s| s["line"].to_s.match?(pat) }
        found && s = found["index"]
      end

      {
        overview: find_idx.call([/概要/]),
        bio:      find_idx.call([/来歴/, /経歴/, /略歴/, /年表/, /活動/]),
        episode:  find_idx.call([/人物/, /人物像/, /エピソード/, /特徴/])
      }
    rescue
      { overview: nil, bio: nil, episode: nil }
    end

    def wikipedia_section_html(title, index)
      return "" if index.blank?
      t = ERB::Util.url_encode(title.to_s)
      url = "https://ja.wikipedia.org/w/api.php?action=parse&page=#{t}&prop=text&section=#{index}&format=json&redirects=1"
      json = http_get_json(url)
      json.dig("parse", "text", "*").to_s
    rescue
      ""
    end

    def section_html_to_text(html)
      return "" if html.blank?
      txt = html.dup
      txt.gsub!(/<\/?li[^>]*>/i, "\n")
      txt.gsub!(/<br\s*\/?>/i, "\n")
      txt.gsub!(/<\/p>/i, "\n")
      txt = CGI.unescapeHTML(txt.gsub(/<[^>]+>/, ""))
      txt.lines.map(&:strip).reject(&:blank?).join("\n")
    end

    # 語頭として許すか（漢字/カタカナ/英字）
    def word_head?(t)
      !!(t =~ /\A[一-龥々]|[ァ-ヶ]|[A-Za-z]/)
    end

    # 小書きカナで始まる（左欠けの典型）は除外
    def small_kana_head?(t)
      !!(t =~ /\A[ァィゥェォャュョヮッ]/)
    end

    # 記号の正規化（比較用）：ハイフン類→長音「ー」
    def normalize_marks(s)
      s.to_s.gsub("－–—ｰ-‐", "ー")
    end

    # 単語だけ抽出（頻度順→長さ順）
    def extract_terms(str)
      return [] if str.blank?
      freq = Hash.new(0)
      str.to_s.scan(TERM_PATTERN) { |m| freq[m] += 1 }
      freq.sort_by { |(k,v)| [-v, -(k.length)] }.map(&:first)
    end

    def finalize_tags(ai_tags:, text:, memo:, word:, kw:, limit: 5)
      begin
        pool = []
        pool.concat Array(ai_tags).compact.map(&:to_s)
        pool.concat Array(kw).compact.map(&:to_s)
        pool << word.to_s
        pool.concat extract_terms(text)
        pool.concat extract_terms(memo)

        # 1) 単語だけに強制（非破壊メソッドでチェイン）
        pool = pool
          .flat_map { |t| t.to_s.scan(TERM_PATTERN) }
          .map     { |t| t.ascii_only? ? t.downcase : t }
          .map     { |t| t.strip }
          .reject  { |t| t.blank? }
          .uniq

        # 2) 語頭バリデーション（記号/小書きカナで始まる欠けを落とす）
        pool = pool.select { |t| word_head?(t) && !small_kana_head?(t) }

        # 3) 本文に“その語がそのまま出ている”ものだけ採用（記号正規化して照合）
        body_norm   = normalize_marks("#{text} #{memo} #{word}")
        valid_terms = extract_terms(body_norm)                            
        valid_kw    = Array(kw).flat_map { |k| extract_terms(normalize_marks(k.to_s)) }
        valid_set   = (valid_terms + valid_kw).uniq                     

        pool = pool.select { |t| valid_set.include?(normalize_marks(t)) }        
        end

        # 元語を優先候補に
        w = word.to_s.strip
        pool.unshift(w) if w.present? && (w =~ TERM_PATTERN)

        kw_norm = Array(kw).map { |k| normalize_marks(k.to_s) }

        pool = pool.sort_by { |t| -t.size }   # 長い順に並べる
        fixed = pool.dup                      # 比較用の固定リスト

        pool = pool.reject do |t|
          tn = normalize_marks(t)
          # 見出し語 w / kw に入っている語は保護
          next false if t == w || kw_norm.include?(tn)

          # 正規化してから「長い語がこの語で始まる」なら短い方を落とす
          fixed.any? { |u| u != t && normalize_marks(u).start_with?(tn) }
        end

        # スコアリング（切り詰めは絶対にしない）
        score = Hash.new(0.0)
        
        pool.each do |t|
          score[t] += 1.0
          score[t] += 1.2 if t == w
          score[t] += 0.8 if Array(kw).any? { |k| normalize_marks(k.to_s).include?(normalize_marks(t)) }
          score[t] += 0.6 if normalize_marks(memo).include?(normalize_marks(t))
          score[t] += 1.0 - ((t.size - 5).abs * 0.25) # “5文字くらいが好ましい”だけ
          score[t] += 0.2 if t =~ /[ァ-ヶー]/
          score[t] += 0.2 if t =~ /[一-龥々]/
        end

        pool.sort_by { |t| -score[t] }.first(limit)
      rescue => e
        Rails.logger.warn("[MeaningFinder.finalize_tags] #{e.class}: #{e.message}")
        extract_terms(normalize_marks("#{text} #{memo} #{word}")).first(limit)
      end
    end
  end
