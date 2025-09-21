function initWordForm() {
  // フォームがないページでは何もしない
  const termInput   = document.getElementById("term_input");
  if (!termInput) return;

  const memoInput   = document.getElementById("memo_textarea");
  const meaningArea = document.getElementById("meaning_textarea");
  const tagsInput   = document.getElementById("tags_input");
  const btnMeaning  = document.getElementById("btn-suggest-meaning");
  const btnTags     = document.getElementById("btn-suggest-tags");

  // Turbo: 同じページに戻ったときの二重バインド防止
  if (btnMeaning?.dataset.bound === "1") return;
  if (btnMeaning) btnMeaning.dataset.bound = "1";
  if (btnTags)    btnTags.dataset.bound    = "1";

  async function callSuggest({ forTags = false } = {}) {
    const term = termInput.value.trim();
    if (!term) { alert("先に「単語」を入力してください。"); return; }

    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    const body = {
      term,
      memo: memoInput?.value || "",
      existing_meaning: meaningArea?.value || ""
    };

    const btn = forTags ? btnTags : btnMeaning;
    if (btn) {
      btn.disabled = true;
      btn.dataset.originalText = btn.innerText;
      btn.innerText = "生成中...";
    }

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
      if (!res.ok) throw new Error(data.error || "生成に失敗しました。");

      if (!forTags && meaningArea) {
        meaningArea.value = data.meaning || meaningArea.value;
      }
      if (tagsInput && Array.isArray(data.tags)) {
        tagsInput.value = data.tags.join(", ");
      }
    } catch (e) {
      console.error(e);
      alert(e.message || "生成に失敗しました。");
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.innerText = btn.dataset.originalText || btn.innerText;
      }
    }
  }

  btnMeaning?.addEventListener("click", () => callSuggest({ forTags: false }));
  btnTags?.addEventListener("click", () => callSuggest({ forTags: true }));
}

// Turbo遷移ごとに初期化（重要）
document.addEventListener("turbo:load",   initWordForm);
document.addEventListener("turbo:render", initWordForm); // 差し替え描画の保険

