document.addEventListener("DOMContentLoaded", () => {
  const btn = document.getElementById("suggest-btn");
  if (!btn) return;

  btn.addEventListener("click", () => {
    const term = document.getElementById("word_term").value;

    fetch("/words/suggest", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({ term: term })
    })
      .then(res => res.json())
      .then(data => {
        if (data.meaning) {
          document.getElementById("word_meaning").value = data.meaning;
        }
        if (data.tags) {
          document.getElementById("word_tags").value = data.tags;
        }
      });
  });
});
