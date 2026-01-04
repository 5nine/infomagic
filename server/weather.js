
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

    https.get(url, res => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
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
        precipTypes: [], // Collect all precipitation types (1=rain, 3=snow)
        precipAmount: 0 // mm
      };
    }

    const params = Object.fromEntries(
      t.parameters.map(p => [p.name, p.values[0]])
    );

    days[date].temps.push(params.t);
    days[date].winds.push(params.ws);
    days[date].symbols.push(params.Wsymb2);

    // Nederbörd: regn eller snö
    // pcat: 0=no, 1=rain, 2=sleet, 3=snow
    if (params.pcat > 0) {
      // Collect precipitation types (only rain=1 or snow=3, ignore sleet=2)
      if (params.pcat === 1 || params.pcat === 3) {
        days[date].precipTypes.push(params.pcat);
      }
      // Sum up precipitation amount in mm
      if (params.pmean > 0) {
        days[date].precipAmount += params.pmean;
      }
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

      // vanligaste symbolen för dagen
      const symbol = d.symbols
        .sort(
          (a, b) =>
            d.symbols.filter(x => x === a).length -
            d.symbols.filter(x => x === b).length
        )
        .pop();

      // vanligaste nederbördstypen för dagen (1=rain, 3=snow)
      let precipType = d.precipTypes.length > 0
        ? d.precipTypes
            .sort(
              (a, b) =>
                d.precipTypes.filter(x => x === a).length -
                d.precipTypes.filter(x => x === b).length
            )
            .pop()
        : null;

      // Korrigera baserat på temperatur: om max-temp är under 0°C måste det vara snö
      // Temperaturkontrollen går före API:ns klassificering, även om precipAmount är 0
      if (d.precipAmount > 0 || precipType !== null) {
        // Vid minusgrader MÅSTE det vara snö, oavsett vad API säger
        if (max < 0) {
          precipType = 3;
        }
        // Om max-temp är under 2°C och API säger regn, ändra till snö
        else if (precipType === 1 && max < 2) {
          precipType = 3;
        }
        // Om det finns nederbörd men ingen typ, använd snö vid låg temperatur
        else if (precipType === null && d.precipAmount > 0 && max < 2) {
          precipType = 3;
        }
      }

      return {
        date,
        min,
        max,
        wind,
        precipType, // 1=rain, 3=snow, null=no precip
        precipAmount: Math.round(d.precipAmount * 10) / 10, // Round to 1 decimal
        symbol
      };
    });

  cache = result;
  lastFetch = Date.now();
  return result;
}

module.exports = { getWeather };
