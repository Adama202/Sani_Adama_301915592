// portfolio-4-nosql/05_indexes.js
// Index demo: COLLSCAN -> IXSCAN on 40k+ documents.
// oven_logs is a time-series collection, so we copy it into an ordinary collection
// (oven_readings) and index that. Query: hot readings for one oven.
// All numbers printed below come from this run's explain("executionStats").
db = db.getSiblingDB("crumble");

db.oven_readings.drop();
db.oven_logs.aggregate([{ $project: { _id: 0, ovenId: 1, ts: 1, temperature: 1, humidity: 1 } },
                        { $out: "oven_readings" }]);
print("oven_readings documents: " + db.oven_readings.countDocuments());

const QUERY = { ovenId: "oven-2", temperature: { $gt: 235 } };

function stageNames(s) {            // walk the plan tree, collect stage names
  let out = [s.stage];
  if (s.inputStage) out = out.concat(stageNames(s.inputStage));
  if (s.inputStages) s.inputStages.forEach(x => { out = out.concat(stageNames(x)); });
  return out;
}
function run(label) {
  const e = db.oven_readings.find(QUERY).explain("executionStats");
  const st = e.executionStats;
  return { label,
           stage: stageNames(st.executionStages).join(" > "),
           docsExamined: st.totalDocsExamined, keysExamined: st.totalKeysExamined,
           returned: st.nReturned, ms: st.executionTimeMillis };
}

// BEFORE: make sure no secondary index exists (safe even if it was never created)
try { db.oven_readings.dropIndex("ovenId_1_temperature_1"); } catch (e) { print("(no index to drop)"); }
const before = run("BEFORE (no index)");

db.oven_readings.createIndex({ ovenId: 1, temperature: 1 }, { name: "ovenId_1_temperature_1" });
print("Index created: ovenId_1_temperature_1");
const after = run("AFTER (compound index)");

print("\n=== P4 INDEX SUMMARY (real explain output) ===");
print("Query: " + JSON.stringify(QUERY));
print("Label                  | Stage                 | Docs examined | Keys examined | Docs returned | Time ms");
[before, after].forEach(r =>
  print(r.label.padEnd(22) + " | " + r.stage.padEnd(21) + " | " + String(r.docsExamined).padStart(13) + " | " +
        String(r.keysExamined).padStart(13) + " | " + String(r.returned).padStart(13) + " | " + r.ms));
