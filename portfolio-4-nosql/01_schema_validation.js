// portfolio-4-nosql/01_schema_validation.js
// Schema validation for Crumble Studio's MongoDB collections.
//
// Two collections:
//   1. oven_logs     — a TIME-SERIES collection (oven sensor readings every
//                      minute). MongoDB does NOT allow a $jsonSchema validator
//                      on a time-series collection (still true in MongoDB 8.0),
//                      so the schema is enforced by the application layer and
//                      documented here. We still create the collection as a
//                      proper time-series collection so we get the storage and
//                      query benefits.
//
//   2. recipe_cards   — a regular collection with a $jsonSchema validator.
//                      Different product TYPES have different fields, so we use
//                      `oneOf` (MongoDB $jsonSchema supports oneOf/anyOf but
//                      NOT if/then in versions <= 8.0 — we deliberately use
//                      oneOf here).
//
// Mongosh convention: use `db = db.getSiblingDB("...")` at the top of every
// file. Never `use dbname;` in a script file.

db = db.getSiblingDB("crumble");

// =========================================================
// 1. oven_logs — time-series collection
// =========================================================
// Drop if exists so the script is idempotent.
db.oven_logs.drop();

db.createCollection("oven_logs", {
  timeseries: {
    timeField: "ts",
    metaField: "ovenId",
    granularity: "minutes"
  },
  expireAfterSeconds: 60 * 60 * 24 * 90   // keep 90 days of sensor data
});

// Time-series collections can't have a $jsonSchema validator, but we CAN
// document the expected shape here and enforce it in the seeding script.
// Expected shape per document:
//   {
//     ovenId:        "oven-1"        // string, the metaField
//     ts:            ISODate(...)    // the timeField
//     temperature:   220.5           // °C, double, 0..400
//     humidity:      65.0            // %, double, 0..100
//     doorOpen:      false           // bool
//     doorOpenCount: 0               // int, cumulative opens this minute
//   }

print("Created time-series collection: crumble.oven_logs");

// =========================================================
// 2. recipe_cards — regular collection with $jsonSchema + oneOf
// =========================================================
db.recipe_cards.drop();

db.createCollection("recipe_cards", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      title: "Crumble recipe card",
      required: ["productId", "name", "type", "steps", "bakingTimeMin",
                 "bakingTempC", "allergens"],
      properties: {
        productId:    { bsonType: "number", description: "must be an int and is required" },
        name:         { bsonType: "string", description: "must be a string and is required" },
        type:         { enum: ["bread", "pastry", "pie", "cookie"],
                        description: "must be one of bread/pastry/pie/cookie" },
        steps:        { bsonType: "array", items: { bsonType: "string" },
                        description: "ordered list of preparation steps" },
        bakingTimeMin:{ bsonType: "number", minimum: 1, maximum: 240 },
        bakingTempC:  { bsonType: "number", minimum: 50, maximum: 300 },
        variations:   { bsonType: "array", items: { bsonType: "string" } },
        allergens:    { bsonType: "array", items: { bsonType: "string" },
                        description: "e.g. [Gluten, Eggs, Milk]" }
      },
      // oneOf: depending on `type`, different extra fields are required.
      // MongoDB $jsonSchema supports oneOf/anyOf; it does NOT support
      // if/then/else — so we use oneOf with a discriminator (`type`).
      oneOf: [
        {
          properties: {
            type:               { enum: ["bread"] },
            hydrationPct:       { bsonType: "number", minimum: 50, maximum: 90 },
            fermentationHours:  { bsonType: "number",   minimum: 1,  maximum: 72 }
          },
          required: ["hydrationPct", "fermentationHours"]
        },
        {
          properties: {
            type:            { enum: ["pastry"] },
            laminationFolds: { bsonType: "number", minimum: 0, maximum: 6 },
            butterPct:       { bsonType: "number", minimum: 0, maximum: 100 }
          },
          required: ["laminationFolds", "butterPct"]
        },
        {
          properties: {
            type:        { enum: ["pie"] },
            crustType:   { enum: ["shortcrust", "puff", "flaky"] },
            filling:     { bsonType: "string" }
          },
          required: ["crustType", "filling"]
        },
        {
          properties: {
            type:           { enum: ["cookie"] },
            doughRestHours: { bsonType: "number", minimum: 0, maximum: 48 },
            spreadFactor:   { bsonType: "number", minimum: 0, maximum: 2 }
          },
          required: ["doughRestHours", "spreadFactor"]
        }
      ]
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

print("Created collection: crumble.recipe_cards (with $jsonSchema + oneOf validator)");

// Show the validator back so we can screenshot it.
printjson(db.getCollectionInfos({ name: "recipe_cards" })[0].options.validator);
