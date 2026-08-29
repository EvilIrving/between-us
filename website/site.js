(() => {
  const supportedLanguages = ["zh", "en", "ja", "ko"];
  const languageTags = { zh: "zh-Hans", en: "en", ja: "ja", ko: "ko" };
  const openGraphLocales = { zh: "zh_CN", en: "en_US", ja: "ja_JP", ko: "ko_KR" };
  const languageLabels = {
    zh: "选择语言",
    en: "Choose language",
    ja: "言語を選択",
    ko: "언어 선택"
  };
  const root = document.documentElement;
  const queryLanguage = new URLSearchParams(window.location.search).get("lang");
  const savedLanguage = localStorage.getItem("between-us-language");

  function normalizeLanguage(value) {
    if (!value) return null;
    const normalized = value.toLowerCase();
    if (normalized.startsWith("zh")) return "zh";
    if (normalized.startsWith("ja")) return "ja";
    if (normalized.startsWith("ko")) return "ko";
    if (normalized.startsWith("en")) return "en";
    return null;
  }

  function browserLanguage() {
    const preferences = navigator.languages?.length ? navigator.languages : [navigator.language];
    for (const preference of preferences) {
      const language = normalizeLanguage(preference);
      if (language) return language;
    }
    return "en";
  }

  function localizedAttribute(element, attribute, language) {
    const value = element.getAttribute(`data-${attribute}-${language}`);
    if (value === null) return;
    element.setAttribute(attribute === "label" ? "aria-label" : attribute, value);
  }

  function updatePageMetadata(language) {
    const page = document.body;
    if (!page) return;
    const title = page.getAttribute(`data-title-${language}`);
    const description = page.getAttribute(`data-description-${language}`);
    const socialTitle = page.getAttribute(`data-og-title-${language}`) || title;
    const socialDescription = page.getAttribute(`data-og-description-${language}`) || description;
    const socialImageAlt = page.getAttribute(`data-og-image-alt-${language}`);

    if (title) document.title = title;
    if (description) document.querySelector('meta[name="description"]')?.setAttribute("content", description);
    if (socialTitle) {
      document.querySelector('meta[property="og:title"]')?.setAttribute("content", socialTitle);
      document.querySelector('meta[name="twitter:title"]')?.setAttribute("content", socialTitle);
    }
    if (socialDescription) {
      document.querySelector('meta[property="og:description"]')?.setAttribute("content", socialDescription);
      document.querySelector('meta[name="twitter:description"]')?.setAttribute("content", socialDescription);
    }
    if (socialImageAlt) document.querySelector('meta[property="og:image:alt"]')?.setAttribute("content", socialImageAlt);
    document.querySelector('meta[property="og:locale"]')?.setAttribute("content", openGraphLocales[language]);
  }

  function setLanguage(language, { updateURL = false } = {}) {
    const nextLanguage = supportedLanguages.includes(language) ? language : "en";
    root.dataset.language = nextLanguage;
    root.lang = languageTags[nextLanguage];
    localStorage.setItem("between-us-language", nextLanguage);

    document.querySelectorAll(".language-switch").forEach((switcher) => {
      switcher.value = nextLanguage;
      switcher.setAttribute("aria-label", languageLabels[nextLanguage]);
    });
    document.querySelectorAll("[data-alt-zh], [data-alt-en], [data-alt-ja], [data-alt-ko]").forEach((element) => {
      localizedAttribute(element, "alt", nextLanguage);
    });
    document.querySelectorAll("[data-label-zh], [data-label-en], [data-label-ja], [data-label-ko]").forEach((element) => {
      localizedAttribute(element, "label", nextLanguage);
    });
    updatePageMetadata(nextLanguage);

    if (updateURL && window.history?.replaceState) {
      const url = new URL(window.location.href);
      url.searchParams.set("lang", nextLanguage);
      window.history.replaceState({}, "", url);
    }
  }

  const initialLanguage = normalizeLanguage(queryLanguage)
    || normalizeLanguage(savedLanguage)
    || browserLanguage();

  root.dataset.language = initialLanguage;
  root.lang = languageTags[initialLanguage];

  function initializePage() {
    setLanguage(initialLanguage);
    document.querySelectorAll(".language-switch").forEach((switcher) => {
      switcher.addEventListener("change", (event) => {
        setLanguage(event.currentTarget.value, { updateURL: true });
      });
    });

    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const elements = document.querySelectorAll(".reveal");
    if (reducedMotion || !("IntersectionObserver" in window)) {
      elements.forEach((element) => element.classList.add("is-visible"));
      return;
    }

    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.12 });

    elements.forEach((element) => observer.observe(element));
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initializePage, { once: true });
  } else {
    initializePage();
  }
})();
