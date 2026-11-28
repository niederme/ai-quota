const themeStorageKey = "aiquota-theme";
const legacyThemeStorageKey = "aiquota-docs-theme";
const themeColorByMode = {
  dark: "#0b060f",
  light: "#f4f1f7",
};

const root = document.documentElement;
const themeMediaQuery = window.matchMedia("(prefers-color-scheme: light)");
const themeColorMeta = document.querySelector('meta[name="theme-color"]');
const themeButtons = Array.from(document.querySelectorAll("[data-theme-choice]"));

const readStorage = (key) => {
  try {
    return window.localStorage.getItem(key);
  } catch (error) {
    return null;
  }
};

const writeStorage = (key, value) => {
  try {
    if (value === null) {
      window.localStorage.removeItem(key);
    } else {
      window.localStorage.setItem(key, value);
    }
  } catch (error) {}
};

// Carry a choice made on the 1.x site over to the new key.
const legacyTheme = readStorage(legacyThemeStorageKey);
if (legacyTheme !== null) {
  if (readStorage(themeStorageKey) === null && (legacyTheme === "light" || legacyTheme === "dark")) {
    writeStorage(themeStorageKey, legacyTheme);
  }
  writeStorage(legacyThemeStorageKey, null);
}

const getThemeMode = () => {
  const storedTheme = readStorage(themeStorageKey);
  return storedTheme === "light" || storedTheme === "dark" ? storedTheme : "system";
};

const applyThemeMode = (mode) => {
  const theme = mode === "system" ? (themeMediaQuery.matches ? "light" : "dark") : mode;
  root.dataset.theme = theme;

  if (themeColorMeta) {
    themeColorMeta.setAttribute("content", themeColorByMode[theme]);
  }

  themeButtons.forEach((button) => {
    button.setAttribute("aria-pressed", String(button.dataset.themeChoice === mode));
  });
};

applyThemeMode(getThemeMode());

themeButtons.forEach((button) => {
  button.addEventListener("click", () => {
    const mode = button.dataset.themeChoice;
    writeStorage(themeStorageKey, mode === "system" ? null : mode);
    applyThemeMode(mode);
  });
});

themeMediaQuery.addEventListener("change", () => {
  if (getThemeMode() === "system") {
    applyThemeMode("system");
  }
});

// Nav: raised shadow once the page scrolls, and the narrow-screen menu.
const nav = document.querySelector("[data-nav]");

if (nav) {
  const syncRaised = () => {
    nav.classList.toggle("aq-nav--raised", window.scrollY > 8);
  };
  syncRaised();
  window.addEventListener("scroll", syncRaised, { passive: true });
}

const menuToggle = document.querySelector("[data-menu-toggle]");
const menu = menuToggle ? document.getElementById(menuToggle.getAttribute("aria-controls")) : null;

let closeMenu = () => {};

if (menuToggle && menu) {
  const setMenuOpen = (open) => {
    menuToggle.setAttribute("aria-expanded", String(open));
    menu.hidden = !open;
  };

  closeMenu = () => setMenuOpen(false);

  menuToggle.addEventListener("click", () => {
    setMenuOpen(menuToggle.getAttribute("aria-expanded") !== "true");
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !menu.hidden) {
      setMenuOpen(false);
      menuToggle.focus();
    }
  });

  window.matchMedia("(min-width: 760px)").addEventListener("change", (event) => {
    if (event.matches) {
      setMenuOpen(false);
    }
  });
}

// Quota dials sweep in the first time they scroll into view.
const dials = Array.from(document.querySelectorAll(".aq-dial, .aq-adial"));
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

if (reducedMotion || !("IntersectionObserver" in window)) {
  dials.forEach((dial) => dial.classList.add("is-shown"));
} else {
  const dialObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-shown");
          dialObserver.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.4 }
  );
  dials.forEach((dial) => dialObserver.observe(dial));
}

// Sample reset notices: dismissing hides them; some offer "Show again".
document.querySelectorAll("[data-notice]").forEach((notice) => {
  const dismissed = notice.parentElement.querySelector("[data-notice-dismissed]");
  const dismiss = notice.querySelector("[data-notice-dismiss]");
  const restore = dismissed ? dismissed.querySelector("[data-notice-restore]") : null;

  dismiss.addEventListener("click", () => {
    notice.hidden = true;
    if (dismissed) {
      dismissed.hidden = false;
      if (restore) {
        restore.focus();
      }
    }
  });

  if (restore) {
    restore.addEventListener("click", () => {
      dismissed.hidden = true;
      notice.hidden = false;
      dismiss.focus();
    });
  }
});

// FAQ: one answer open at a time.
document.querySelectorAll("[data-faq]").forEach((list) => {
  const items = Array.from(list.querySelectorAll("details"));
  items.forEach((item) => {
    item.addEventListener("toggle", () => {
      if (!item.open) {
        return;
      }
      items.forEach((other) => {
        if (other !== item && other.open) {
          other.open = false;
        }
      });
    });
  });
});

// Get AIQuota: the nav Download button opens a dialog with the store badges.
// Without <dialog> support the button falls back to the download band.
const getDialog = document.getElementById("get-aiquota");

if (getDialog && typeof getDialog.showModal === "function") {
  const closeButton = getDialog.querySelector("[data-get-close]");

  document.querySelectorAll("[data-get-open]").forEach((opener) => {
    opener.addEventListener("click", (event) => {
      event.preventDefault();
      closeMenu();
      getDialog.showModal();
      closeButton.focus();
    });
  });

  closeButton.addEventListener("click", () => getDialog.close());

  // A click on the blurred backdrop lands on the dialog element itself.
  getDialog.addEventListener("click", (event) => {
    if (event.target === getDialog) {
      getDialog.close();
    }
  });
}

// Mock captions shrink to fit their line, the way the apps' widgets scale text
// down, so longer translations of "5h reset in 2h 14m" stay on one line.
const fitCaptions = () => {
  document.querySelectorAll(".widget__reset, .widget__foot, .aq-acct--sm .aq-acct__cap").forEach((caption) => {
    caption.style.fontSize = "";
    let size = parseFloat(getComputedStyle(caption).fontSize);
    while (caption.scrollWidth > caption.clientWidth + 0.5 && size > 7) {
      size -= 0.25;
      caption.style.fontSize = `${size}px`;
    }
  });
};

fitCaptions();
if (document.fonts && document.fonts.ready) {
  document.fonts.ready.then(fitCaptions);
}
window.addEventListener("resize", fitCaptions, { passive: true });

// Language picker: remember a pick so English pages stop sending this visitor
// to their browser's language, and close the list on Escape or an outside click.
const languageStorageKey = "aiquota-language";

document.querySelectorAll("[data-lang-picker]").forEach((picker) => {
  picker.querySelectorAll("a[data-lang]").forEach((link) => {
    link.addEventListener("click", () => writeStorage(languageStorageKey, link.dataset.lang));
  });

  document.addEventListener("click", (event) => {
    if (picker.open && !picker.contains(event.target)) {
      picker.open = false;
    }
  });

  picker.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && picker.open) {
      picker.open = false;
      picker.querySelector("summary").focus();
    }
  });
});
