// app/javascript/ai_word.js
function attachAiMeaning() {
  const btn   = document.getElementById("btn-ai-meaning");
  const wEl   = document.getElementById("word_input");
  const mEl   = document.getElementById("memo_textarea");
  const meanEl= document.getElementById("meaning_textarea");
  const tEl   = document.getElementById("tags_input");
  if (!btn || !wEl) return;

  btn.addEventListener("click", async () => {
    btn.disabled = true;
    const prev = btn.textContent;
    btn.textContent = "生成中…";

    try {
      const token = document.querySelector('meta[name="csrf-token"]').content;
      const res = await fetch("/words/ai_suggest", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": token
        },
        body: JSON.stringify({
          word: wEl.value || "",
          memo: mEl ? mEl.value : ""
        })
      });

      const data = await res.json();
      if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);

      if (meanEl && data.meaning) meanEl.value = data.meaning;

      if (tEl && Array.isArray(data.tags)) {
        const current = (tEl.value || "").split(",").map(s => s.trim()).filter(Boolean);
        const merged = Array.from(new Set([...current, ...data.tags]));
        tEl.value = merged.slice(0, 5).join(", ");
      }
      // 参考URLをコンソールに出す（必要なら画面表示へ）
    } catch (e) {
      alert(`AI提案に失敗しました：${e.message}`);
      console.error(e);
    } finally {
      btn.disabled = false;
      btn.textContent = prev;
    }
  });
}

document.addEventListener("turbo:load", attachAiMeaning);
document.addEventListener("DOMContentLoaded", attachAiMeaning);
