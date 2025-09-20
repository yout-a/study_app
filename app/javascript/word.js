// app/javascript/word.js
(() => {
  // 単語フォームがあるページだけで動作
  const termInput   = document.getElementById("term_input");
  const memoInput   = document.getElementById("memo_textarea");
  const meaningArea = document.getElementById("meaning_textarea");
  const tagsInput   = document.getElementById("tags_input");

  const btnMeaning  = document.getElementById("btn-suggest-meaning");
  const btnTags     = document.getElementById("btn-suggest-tags");

  if (!termInput) return;

  // CSRF token
  const token = document.querySelector('meta[name="csrf-token"]')?.content;

  async function callSuggest({ forTags = false }) {
    const term  = termInput.value.trim();
    if (!term) { alert("先に『単語』を入力してください。"); return; }

    const body = {
      term: term,
      memo: memoInput?.value || "",
      existing_meaning: meaningArea?.value || ""
    };

    const btn = forTags ? btnTags : btnMeaning;
    const originalText = btn.innerText;
    btn.disabled = true;
    btn.innerText = "生成中…";

    try {
      const res = await fetch("/api/chat/suggest_word", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": token
        },
        body: JSON.stringify(body)
      });

      const data = await res.json();

      if (!res.ok) throw new Error(data.error || "生成に失敗しました");

      // 反映
      if (!forTags && meaningArea) {
        meaningArea.value = data.meaning || meaningArea.value;
      }
      if (tagsInput && Array.isArray(data.tags)) {
        const newTags = data.tags.join(", ");
        // 既存のタグとマージしたい場合は以下でもOK
        // tagsInput.value = [tagsInput.value, newTags].filter(Boolean).join(", ");
        tagsInput.value = newTags;
      }
    } catch (e) {
      console.error(e);
      alert(e.message || "生成に失敗しました");
    } finally {
      btn.disabled = false;
      btn.innerText = originalText;
    }
  }

  btnMeaning?.addEventListener("click", () => callSuggest({ forTags: false }));
  btnTags?.addEventListener("click", () => callSuggest({ forTags: true }));
})();
