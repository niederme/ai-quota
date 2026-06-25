const dailyValue = [
  0.08, 0.03, 0.14, 0.05, 0.03, 0.09, 0.02, 0.07, 0.04, 0.11,
  0.13, 0.48, 0.22, 0.53, 0.21, 0.15, 0.12, 0.18, 0.29, 0.12,
  0.23, 0.08, 0.07, 0.07, 0.71, 0.39, 0.17, 0.08, 0.34, 3.12
];

const dailyTokens = dailyValue.map((value, index) => {
  const multiplier = index === dailyValue.length - 1 ? 737_180 : 492_000;
  return Math.round(value * multiplier);
});

const framingCopy = {
  cost: {
    title: "Estimated cost",
    metric: "~$7.71",
    caption: "Estimated API cost · last 30 days",
    note: "Very easy to understand, but it overstates certainty and can feel like an unexpected charge.",
    disclosure: "Estimated from local Claude logs at current API rates. Not charged by AIQuota."
  },
  value: {
    title: "Usage value",
    metric: "~$7.71",
    caption: "API-equivalent value · last 30 days",
    note: "This is the strongest default: it makes tokens legible without implying that Claude charged another $7.71.",
    disclosure: "Estimated from local Claude logs at current API rates. Not an actual bill."
  },
  subscription: {
    title: "Subscription value",
    metric: "8%",
    caption: "of subscription price realized · last 30 days",
    note: "This answers the most human question, but only works if the user supplies an accurate subscription price.",
    disclosure: "Compares estimated API-equivalent value with the subscription price you entered."
  }
};

const chart = document.querySelector("#chart");
const panelTitle = document.querySelector("#panel-title");
const heroMetric = document.querySelector("#hero-metric");
const metricCaption = document.querySelector("#metric-caption");
const studyNote = document.querySelector("#study-note");
const disclosure = document.querySelector("#disclosure");
const price = document.querySelector("#price");
const priceOutput = document.querySelector("#price-output");
const planPrice = document.querySelector("#plan-price");
const breakEven = document.querySelector("#break-even");
const realized = document.querySelector("#realized");
const progressFill = document.querySelector("#progress-fill");
const subscriptionSection = document.querySelector("#subscription-section");
const comparison = document.querySelector("#comparison");
const axisTop = document.querySelector("#axis-top");
const axisMid = document.querySelector("#axis-mid");
const opusValue = document.querySelector("#opus-value");
const sonnetValue = document.querySelector("#sonnet-value");

let framing = "value";
let mode = "value";

function compactTokens(value) {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
  if (value >= 1_000) return `${Math.round(value / 1_000)}k`;
  return String(value);
}

function renderChart() {
  const data = mode === "value" ? dailyValue : dailyTokens;
  const max = Math.max(...data) * 1.03;

  chart.replaceChildren(...data.map((value, index) => {
    const bar = document.createElement("span");
    bar.className = `chart-bar${index === data.length - 1 ? " is-today" : ""}`;
    bar.style.setProperty("--height", Math.max(2.5, (value / max) * 100));
    bar.title = mode === "value" ? `~$${value.toFixed(2)}` : `${compactTokens(value)} tokens`;
    return bar;
  }));

  if (mode === "value") {
    axisTop.textContent = "$3.20";
    axisMid.textContent = "$1.60";
    comparison.innerHTML = `
      <span class="today-dot"></span>
      <span>Today <strong>~$3.12</strong></span>
      <span class="comparison-divider"></span>
      <span>Typical day <strong class="cyan">~$0.26</strong></span>
    `;
    opusValue.textContent = "$6.88";
    sonnetValue.textContent = "$0.83";
  } else {
    axisTop.textContent = "2.3M";
    axisMid.textContent = "1.15M";
    comparison.innerHTML = `
      <span class="today-dot"></span>
      <span>Today <strong>2.3M</strong></span>
      <span class="comparison-divider"></span>
      <span>Typical day <strong class="cyan">128k</strong></span>
    `;
    opusValue.textContent = "3.1M";
    sonnetValue.textContent = "0.7M";
  }
}

function updatePrice() {
  const monthlyPrice = Number(price.value);
  const percent = Math.min(100, Math.round((7.71 / monthlyPrice) * 100));

  priceOutput.textContent = `$${monthlyPrice}`;
  planPrice.textContent = `$${monthlyPrice}/mo`;
  breakEven.textContent = `${percent}%`;
  realized.textContent = `${percent}% of subscription value realized`;
  progressFill.style.width = `${Math.max(1, percent)}%`;

  if (framing === "subscription" && mode === "value") {
    heroMetric.textContent = `${percent}%`;
  }
}

function updateFraming(nextFraming) {
  framing = nextFraming;
  const copy = framingCopy[framing];

  panelTitle.textContent = copy.title;
  studyNote.textContent = copy.note;
  disclosure.textContent = copy.disclosure;
  subscriptionSection.classList.toggle("is-deemphasized", framing === "cost");

  if (mode === "value") {
    heroMetric.textContent = copy.metric;
    metricCaption.textContent = copy.caption;
    updatePrice();
  }
}

function updateMode(nextMode) {
  mode = nextMode;
  document.querySelectorAll(".mode-button").forEach((button) => {
    button.classList.toggle("is-selected", button.dataset.mode === mode);
  });

  if (mode === "tokens") {
    heroMetric.textContent = "3.8M";
    metricCaption.textContent = "tokens · last 30 days";
  } else {
    const copy = framingCopy[framing];
    heroMetric.textContent = copy.metric;
    metricCaption.textContent = copy.caption;
    updatePrice();
  }

  renderChart();
}

document.querySelectorAll('input[name="framing"]').forEach((input) => {
  input.addEventListener("change", (event) => updateFraming(event.target.value));
});

document.querySelectorAll(".mode-button").forEach((button) => {
  button.addEventListener("click", () => updateMode(button.dataset.mode));
});

price.addEventListener("input", updatePrice);

renderChart();
updatePrice();
