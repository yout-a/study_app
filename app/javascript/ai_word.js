// app/javascript/ai_word.js

// 既存の関数名は変更しない
let __aiWordInflight; // 直近のリクエストを中断するための AbortController(グローバルに確保)

function attachAiMeaning() {
  const btn    = document.getElementById("btn-ai-meaning");
  const wEl    = document.getElementById("word_input");
  const mEl    = document.getElementById("memo_textarea");
  const meanEl = document.getElementById("meaning_textarea");
  const tEl    = document.getElementById("tags_input");

  // 必要要素が無い画面では何もしない
  if (!btn || !wEl) return;

  // Turbo遷移で何度も読み込まれても click を2重で付けない
  if (btn.dataset.bound === "1") return;
  btn.dataset.bound = "1";

  btn.addEventListener("click", async () => {
    const word = (wEl.value || "").trim();
    if (!word) { wEl.focus(); return; }

    // 直前の未完了リクエストがあれば中断
    try { __aiWordInflight?.abort(); } catch (_) {}
    __aiWordInflight = new AbortController();

    btn.disabled = true;
    const prev = btn.textContent;
    btn.textContent = "生成中…";

    try {
      const tokenEl = document.querySelector('meta[name="csrf-token"]');
      const headers = {
        "Content-Type": "application/json",
        "Accept": "application/json"
      };
      if (tokenEl && tokenEl.content) headers["X-CSRF-Token"] = tokenEl.content;

      const res = await fetch("/words/ai_suggest", {
        method: "POST",
        headers,
        body: JSON.stringify({
          word,
          memo: mEl ? mEl.value : ""
        }),
        signal: __aiWordInflight.signal
      });

      // fetchの戻りが text/json どちらでも安全にパース
      const raw = await res.text();
      let data = {};
      try { data = raw ? JSON.parse(raw) : {}; } catch { data = { error: raw }; }

      if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);

      if (meanEl && data.meaning) meanEl.value = data.meaning;

      if (tEl && Array.isArray(data.tags)) {
        // 既存タグは「, ・、・空白」で分割 → trim → 重複除去
        const current = (tEl.value || "")
          .split(/[,、\s]+/)
          .map(s => s.trim())
          .filter(Boolean);

        const merged = Array.from(new Set([...current, ...data.tags]));
        tEl.value = merged.slice(0, 5).join(", "); // 5件まで
      }

      // 参考: 返ってくるソースURLがあればコンソールに出す（元のコメントを活かす）
      if (Array.isArray(data.sources)) {
        console.info("AI sources:", data.sources);
      }
    } catch (e) {
      // ユーザーの連打でAbortした場合は無視
      if (e.name !== "AbortError") {
        console.error(e);
        alert(`AI提案に失敗しました：${e.message}`);
      }
    } finally {
      btn.disabled = false;
      btn.textContent = prev;
      __aiWordInflight = null;
    }
  }, { passive: true });
}

// Turbo/直リンクの両方で確実にバインド
document.addEventListener("turbo:load",   attachAiMeaning);
document.addEventListener("turbo:render", attachAiMeaning);
document.addEventListener("DOMContentLoaded", attachAiMeaning);
