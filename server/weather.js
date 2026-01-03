
const https = require('https');

/* ───── PLATS: ÖRNSKÖLDSVIK ───── */
const LAT = 63.2909;
const LON = 18.7153;

/* ───── CACHE ───── */
let cache = null;
let lastFetch = 0;
const CACHE_TIME = 30 * 60 * 1000; // 30 min

/* ───── FETCH FROM SMHI ───── */
function fetchSMHI() {
  return new Promise((resolve, reject) => {
    const url =
      'https://opendata-download-metfcst.smhi.se/api/' +
      'category/pmp3g/version/2/geotype/point/' +
      `lon/${LON}/lat/${LAT}/data.json`;

    const req = https.get(url, { timeout: 10000 }, res => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => {
        clearTimeout(timeout);
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(e);
        }
      });
    });

    const timeout = setTimeout(() => {
      req.destroy();
      reject(new Error('Request timeout'));
    }, 10000); // 10 second timeout

    req.on('error', err => {
      clearTimeout(timeout);
      reject(err);
    });

    req.on('timeout', () => {
      req.destroy();
      clearTimeout(timeout);
      reject(new Error('Request timeout'));
    });
  });
}

/* ───── MAIN LOGIC ───── */
async function getWeather() {
  if (cache && Date.now() - lastFetch < CACHE_TIME) {
    return cache;
  }

  const raw = await fetchSMHI();

  /*
    Vi grupperar per dag och samlar:
    - min/max temp
    - medelvind
    - om nederbörd förekommer
    - vanligaste vädersymbol
  */
  const days = {};

  raw.timeSeries.forEach(t => {
    const date = t.validTime.slice(0, 10);
    const hour = Number(t.validTime.slice(11, 13));

    // Vi ignorerar natt (00–05) för snyggare dagprognos
    if (hour < 6) return;

    if (!days[date]) {
      days[date] = {
        temps: [],
        winds: [],
        symbols: [],
        precip: false
      };
    }

    const params = Object.fromEntries(
      t.parameters.map(p => [p.name, p.values[0]])
    );

    days[date].temps.push(params.t);
    days[date].winds.push(params.ws);
    days[date].symbols.push(params.Wsymb2);

    // Nederbörd: regn eller snö
    if (params.pmean > 0 || params.pcat > 0) {
      days[date].precip = true;
    }
  });

  /* ───── REDUCERA TILL DAGSVÄRDEN ───── */
  const result = Object.entries(days)
    .slice(0, 5)
    .map(([date, d]) => {
      const min = Math.min(...d.temps);
      const max = Math.max(...d.temps);
      const wind =
        d.winds.reduce((a, b) => a + b, 0) / d.winds.length;

      // vanligaste symbolen för dagen (optimized - count frequencies once)
      const symbolCounts = {};
      d.symbols.forEach(s => {
        symbolCounts[s] = (symbolCounts[s] || 0) + 1;
      });
      const symbol = Object.entries(symbolCounts)
        .sort((a, b) => b[1] - a[1])[0]?.[0] || d.symbols[0];

      return {
        date,
        min,
        max,
        wind,
        precip: d.precip,
        symbol
      };
    });

  cache = result;
  lastFetch = Date.now();
  return result;
}

module.exports = { getWeather };
