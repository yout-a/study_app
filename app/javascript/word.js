(() => {
  // フォーム要素
  const termInput   = document.getElementById("term_input");
  const memoInput   = document.getElementById("memo_textarea");
  const meaningArea = document.getElementById("meaning_textarea");
  const tagsInput   = document.getElementById("tags_input");

  const btnMeaning  = document.getElementById("btn-suggest-meaning");
  const btnTags     = document.getElementById("btn-suggest-tags");

  // このページに単語フォームが無い場合は何もしない
  if (!termInput || (!btnMeaning && !btnTags)) return;

  // CSRF token
  const token = document.querySelector('meta[name="csrf-token"]')?.content;

  async function callSuggest({ forTags = false } = {}) {
    const term = termInput.value.trim();
    if (!term) { alert("先に『単語』を入力してください。"); return; }

    const body = {
      term,
      memo: memoInput?.value || "",
      existing_meaning: meaningArea?.value || ""
    };

    const btn = forTags ? btnTags : btnMeaning;
    const originalText = btn?.innerText;
    if (btn) {
      btn.disabled = true;
      btn.innerText = "生成中…";
    }

    try {
      const res = await fetch("/api/chat/suggest_word", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": token
        },
        credentials: "same-origin",
        body: JSON.stringify(body)
      });

      // 先に ok を確認
      let data;
      try {
        data = await res.json();
      } catch {
        throw new Error("サーバから不正なJSONが返されました。");
      }
      if (!res.ok) {
        throw new Error(data?.error || res.statusText || "生成に失敗しました。");
      }

      // ===== 反映 =====
      if (!forTags && meaningArea) {
        // 意味の反映（空なら上書き／既にあれば追記したい場合は好みで）
        meaningArea.value = data.meaning ?? meaningArea.value;
      }

      if (forTags && tagsInput) {
        const incoming = Array.isArray(data.tags) ? data.tags : [];
        const current  = tagsInput.value
          .split(",")
          .map(s => s.trim())
          .filter(Boolean);

        const merged = [...new Set([...current, ...incoming])];
        tagsInput.value = merged.join(", ");
      }
    } catch (e) {
      console.error(e);
      alert(e.message || "生成に失敗しました。");
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.innerText = originalText;
      }
    }
  }

  btnMeaning?.addEventListener("click", () => callSuggest({ forTags: false }));
  btnTags?.addEventListener("click",    () => callSuggest({ forTags: true  }));
})();
