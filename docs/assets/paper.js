/* Shared behaviour: the theme switch, the page scroll state, copy buttons, the contents rail,
   and the small tab bars. Everything reads the page it is on and does nothing when the element
   it wants is absent, so one file serves all four pages. */

const root = document.documentElement;

/* ── theme ──────────────────────────────────────────────────────────────── */
/* The head of each page sets the attribute before painting, from sessionStorage: a choice
   holds while the reader moves between pages and is forgotten on a reload, which returns the
   page to the system setting. */
const KEY = "moonmuse:theme";

function paintTheme(theme) {
  root.setAttribute("data-theme", theme);
  const chrome = document.getElementById("theme-color");
  if (chrome) chrome.setAttribute("content", theme === "dark" ? "#14110D" : "#F2EBDD");
  const button = document.getElementById("theme");
  if (!button) return;
  button.setAttribute("aria-label", theme === "dark" ? "Switch to the light desk" : "Switch to the dark desk");
  button.setAttribute("aria-pressed", theme === "dark" ? "true" : "false");
}

paintTheme(root.getAttribute("data-theme") || "light");

const switchButton = document.getElementById("theme");
if (switchButton) {
  switchButton.addEventListener("click", () => {
    const next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    paintTheme(next);
    try { sessionStorage.setItem(KEY, next); } catch (error) {}
  });
}

if (window.matchMedia) {
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", (event) => {
    let saved = null;
    try { saved = sessionStorage.getItem(KEY); } catch (error) {}
    if (!saved) paintTheme(event.matches ? "dark" : "light");
  });
}

/* ── the page scroll ─────────────────────────────────────────────────────── */
const bar = document.querySelector(".bar");
const totop = document.getElementById("totop");

let queued = false;
function onScroll() {
  queued = false;
  const y = window.scrollY || root.scrollTop;
  root.classList.toggle("at-top", y <= 2);
  if (bar) bar.classList.toggle("pinned", y > 6);
  if (totop) totop.classList.toggle("on", y > 640);
}

function schedule() {
  if (!queued) {
    queued = true;
    requestAnimationFrame(onScroll);
  }
}

window.addEventListener("scroll", schedule, { passive: true });
window.addEventListener("resize", schedule, { passive: true });
if (totop) totop.addEventListener("click", () => window.scrollTo({ top: 0 }));
onScroll();

/* ── the contents rail ───────────────────────────────────────────────────── */
const rail = document.querySelector(".rail");
if (rail) {
  const links = [...rail.querySelectorAll("a[href^='#']")];
  const targets = links.map((link) => document.getElementById(link.getAttribute("href").slice(1)));

  const mark = () => {
    let active = 0;
    targets.forEach((target, index) => {
      if (target && target.getBoundingClientRect().top <= 150) active = index;
    });
    links.forEach((link, index) => {
      if (index === active) link.setAttribute("aria-current", "true");
      else link.removeAttribute("aria-current");
    });
  };

  window.addEventListener("scroll", mark, { passive: true });
  window.addEventListener("load", mark);
  mark();
}

/* ── copy buttons ────────────────────────────────────────────────────────── */
/* The text comes from the rendered block, so what is copied is exactly what is read. The
   fallback exists because a page opened from disk refuses the clipboard API. */
function copied(button) {
  const before = button.textContent;
  button.textContent = "Copied";
  button.classList.add("done");
  clearTimeout(button._timer);
  button._timer = setTimeout(() => {
    button.textContent = before;
    button.classList.remove("done");
  }, 1400);
}

function fallbackCopy(text, done) {
  const area = document.createElement("textarea");
  area.value = text;
  area.setAttribute("readonly", "");
  area.style.cssText = "position:fixed;left:-9999px;top:0";
  document.body.appendChild(area);
  area.select();
  try { document.execCommand("copy"); done(); } catch (error) {}
  area.remove();
}

function copyFrom(button, text) {
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text).then(
      () => copied(button),
      () => fallbackCopy(text, () => copied(button)),
    );
  } else {
    fallbackCopy(text, () => copied(button));
  }
}

document.querySelectorAll(".listing").forEach((listing) => {
  const pre = listing.querySelector("pre");
  const row = listing.querySelector(".listing-bar");
  if (!pre || !row) return;
  const button = document.createElement("button");
  button.type = "button";
  button.className = "copy";
  button.textContent = "Copy";
  button.setAttribute("aria-label", "Copy this listing");
  button.addEventListener("click", () => copyFrom(button, pre.textContent.replace(/^\s+|\s+$/g, "")));
  row.appendChild(button);
});

/* ── tab bars ────────────────────────────────────────────────────────────── */
document.querySelectorAll("[data-tabs]").forEach((group) => {
  const buttons = [...group.querySelectorAll("[role='tab']")];
  const panels = buttons.map((button) => document.getElementById(button.getAttribute("aria-controls")));

  const choose = (index) => {
    buttons.forEach((button, at) => button.setAttribute("aria-selected", at === index ? "true" : "false"));
    panels.forEach((panel, at) => { if (panel) panel.hidden = at !== index; });
  };

  buttons.forEach((button, index) => {
    button.addEventListener("click", () => choose(index));
    button.addEventListener("keydown", (event) => {
      if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
      event.preventDefault();
      const next = (index + (event.key === "ArrowRight" ? 1 : buttons.length - 1)) % buttons.length;
      buttons[next].focus();
      choose(next);
    });
  });
});
