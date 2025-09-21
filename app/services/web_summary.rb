# frozen_string_literal: true
require "open-uri"
require "json"

class WebSummary
  class << self
    # 用語の要約を Web から取得して返す（日本語優先）
    # 1) Wikipedia(ja) → 2) DuckDuckGo (日本ロケール) の順に試す
    def fetch(term, lang: "ja")
      summary = fetch_from_wikipedia(term, lang) || fetch_from_duckduckgo(term, lang)
      summary&.strip.presence
    end

    private

    def fetch_from_wikipedia(term, lang)
      encoded = URI.encode_www_form_component(term)
      url     = "https://#{lang}.wikipedia.org/api/rest_v1/page/summary/#{encoded}"
      res     = URI.open(url, "User-Agent" => "StudyApp/1.0").read
      json    = JSON.parse(res) rescue nil
      json && json["extract"]
    rescue OpenURI::HTTPError, JSON::ParserError
      nil
    end

    def fetch_from_duckduckgo(term, lang)
      encoded = URI.encode_www_form_component(term)
      # kl=jp-ja で日本語寄りの要約
      url  = "https://api.duckduckgo.com/?q=#{encoded}&format=json&no_html=1&skip_disambig=1&kl=jp-ja"
      res  = URI.open(url, "User-Agent" => "StudyApp/1.0").read
      json = JSON.parse(res) rescue nil
      json && json["Abstract"]
    rescue OpenURI::HTTPError, JSON::ParserError
      nil
    end
  end
end
