// portfolio-4-nosql/04_aggregations.js
// Aggregation pipelines for Crumble Studio's MongoDB data.
//
// Three pipelines required by the CA brief:
//   A. average baking temperature per oven per day
//   B. ovens running too hot (avg temp > target + 15C)
//   C. allergens per product (and a summary across all products)
//
// Honesty rule: results are printed live; do NOT invent them in this file.

db = db.getSiblingDB("crumble");

print("==================================================");
print("A. Average baking temperature per oven per day");
print("==================================================");
// Time-series collections store the date in the timeField `ts`. We bucket by
// ovenId (the metaField) and by the calendar day of `ts`.
const avgTempPerOvenPerDay = db.oven_logs.aggregate([
  {
    $group: {
      _id: {
        ovenId: "$ovenId",
        day:    { $dateToString: { format: "%Y-%m-%d", date: "$ts" } }
      },
      avgTempC:    { $avg: "$temperature" },
      maxTempC:    { $max: "$temperature" },
      minTempC:    { $min: "$temperature" },
      readingCount:{ $sum: 1 }
    }
  },
  { $sort: { "_id.day": 1, "_id.ovenId": 1 } }
]);
printjson(avgTempPerOvenPerDay.toArray());

print("==================================================");
print("B. Ovens running too hot (avg daily temp > target + 15C)");
print("==================================================");
// Targets: oven-1 220, oven-2 230, oven-3 240, oven-4 200.
// An oven is "too hot" on a given day if its daily avg is more than 15C above
// its target.
const OVEN_TARGETS = {
  "oven-1": 220, "oven-2": 230, "oven-3": 240, "oven-4": 200
};

const tooHot = db.oven_logs.aggregate([
  {
    $group: {
      _id: {
        ovenId: "$ovenId",
        day:    { $dateToString: { format: "%Y-%m-%d", date: "$ts" } }
      },
      avgTempC:    { $avg: "$temperature" },
      maxTempC:    { $max: "$temperature" }
    }
  },
  {
    $addFields: {
      targetTempC: {
        $switch: {
          branches: [
            { case: { $eq: ["$_id.ovenId", "oven-1"] }, then: 220 },
            { case: { $eq: ["$_id.ovenId", "oven-2"] }, then: 230 },
            { case: { $eq: ["$_id.ovenId", "oven-3"] }, then: 240 },
            { case: { $eq: ["$_id.ovenId", "oven-4"] }, then: 200 }
          ],
          default: 0
        }
      }
    }
  },
  {
    $match: {
      $expr: { $gt: ["$avgTempC", { $add: ["$targetTempC", 15] }] }
    }
  },
  { $sort: { "_id.day": 1, "_id.ovenId": 1 } }
]);
printjson(tooHot.toArray());

print("==================================================");
print("C. Allergens per product (and an allergen roll-up)");
print("==================================================");
// C1. Per product: list its allergens
const allergensPerProduct = db.recipe_cards.aggregate([
  { $project: { _id: 0, productId: 1, name: 1, allergens: 1 } },
  { $sort: { productId: 1 } }
]);
print("--- allergens per product ---");
printjson(allergensPerProduct.toArray());

// C2. Roll-up: count how many products contain each allergen
const allergenRollup = db.recipe_cards.aggregate([
  { $unwind: "$allergens" },
  { $group: { _id: "$allergens", productCount: { $sum: 1 } } },
  { $sort: { productCount: -1 } }
]);
print("--- allergen roll-up (how many products contain each allergen) ---");
printjson(allergenRollup.toArray());

print("==================================================");
print("Bonus: door-open events per oven per day");
print("==================================================");
const doorEvents = db.oven_logs.aggregate([
  { $match: { doorOpen: true } },
  {
    $group: {
      _id: {
        ovenId: "$ovenId",
        day:    { $dateToString: { format: "%Y-%m-%d", date: "$ts" } }
      },
      openCount: { $sum: 1 }
    }
  },
  { $sort: { "_id.day": 1, "_id.ovenId": 1 } }
]);
printjson(doorEvents.toArray());
