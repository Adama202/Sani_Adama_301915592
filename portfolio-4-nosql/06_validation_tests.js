// Two BAD documents that the oneOf validator must REJECT, and one good one that must be accepted.
db = db.getSiblingDB("crumble");
function attempt(label, doc) {
  try { db.recipe_cards.insertOne(doc); print(label + " -> ACCEPTED"); db.recipe_cards.deleteOne({ productId: doc.productId }); }
  catch (e) { print(label + " -> REJECTED: " + e.codeName + " (" + e.message.split("\n")[0] + ")"); }
}
const base = { name: "Test bake", steps: ["mix", "bake"], bakingTimeMin: 30, bakingTempC: 200, allergens: ["Gluten"] };
attempt("bad 1: bread without hydrationPct/fermentationHours", { ...base, productId: 9001, type: "bread" });
attempt("bad 2: pie with crustType 'rubbery'", { ...base, productId: 9002, type: "pie", crustType: "rubbery", filling: "beef" });
attempt("good : valid cookie (control, must be accepted)", { ...base, productId: 9003, type: "cookie", doughRestHours: 2, spreadFactor: 1.2 });
