// portfolio-4-nosql/02_seed_oven_logs.js
// Seed the oven_logs time-series collection with 40k+ sensor readings.
//
// 4 ovens x 1 reading per minute x 7 days = 4 * 7 * 24 * 60 = 40,320 documents.
// Each document: { ovenId, ts, temperature, humidity, doorOpen, doorOpenCount }
//
// Realistic-ish patterns:
//   * Each oven has a target temperature (220, 230, 240, 200 °C for the four)
//   * Readings oscillate ±10°C around the target
//   * Humidity 50-80%
//   * doorOpen = true ~4% of the time (when the baker opens to load/unload)
//   * Slight upward drift during Ramadan evening baking (18:00-22:00)
//
// Inserted in batches of 1000 to keep memory bounded. Uses insertMany with
// ordered:false so a single bad doc does not abort the rest.

db = db.getSiblingDB("crumble");

const OVEN_DEFS = [
  { ovenId: "oven-1", targetTempC: 220 },
  { ovenId: "oven-2", targetTempC: 230 },
  { ovenId: "oven-3", targetTempC: 240 },
  { ovenId: "oven-4", targetTempC: 200 }
];

const now    = new Date();
const start  = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);  // 7 days ago
const STEP_MS = 60 * 1000;                                          // 1 minute

let totalInserted = 0;
let batch = [];

for (let t = start.getTime(); t < now.getTime(); t += STEP_MS) {
  const d = new Date(t);
  const hour = d.getHours();
  // Ramadan-evening baking boost: 18:00-22:00
  const eveningBoost = (hour >= 18 && hour <= 22) ? 8 : 0;

  for (const oven of OVEN_DEFS) {
    const temp = oven.targetTempC
               + (Math.random() * 20 - 10)        // ±10°C noise
               + eveningBoost;
    const humidity = 50 + Math.random() * 30;
    const doorOpen = Math.random() < 0.04;

    batch.push({
      ovenId:        oven.ovenId,
      ts:            d,
      temperature:   Math.round(temp * 10) / 10,
      humidity:      Math.round(humidity * 10) / 10,
      doorOpen:      doorOpen,
      doorOpenCount: doorOpen ? 1 : 0
    });

    if (batch.length >= 1000) {
      db.oven_logs.insertMany(batch, { ordered: false });
      totalInserted += batch.length;
      batch = [];
    }
  }
}
if (batch.length > 0) {
  db.oven_logs.insertMany(batch, { ordered: false });
  totalInserted += batch.length;
}

print(`Inserted ${totalInserted} oven log documents.`);
print(`Count check: ${db.oven_logs.estimatedDocumentCount()}`);
