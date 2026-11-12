// portfolio-4-nosql/03_seed_recipe_cards.js
// Seed the recipe_cards collection. Each document corresponds to one product
// from the SQL `product` table, but with a richer document shape: ordered
// preparation steps, baking time/temp, variations, allergen notes, and a
// type-specific block chosen by $jsonSchema oneOf:
//
//   bread  -> { hydrationPct, fermentationHours }
//   pastry -> { laminationFolds, butterPct }
//   pie    -> { crustType, filling }
//   cookie -> { doughRestHours, spreadFactor }
//
// Note: productId values must match the SQL seed (03_seed.sql) so we can
// join across systems if needed: 1..10 in the same order as the SQL insert.

db = db.getSiblingDB("crumble");

db.recipe_cards.deleteMany({});

const recipes = [
  // 1. Sourdough loaf — bread
  {
    productId: 1,
    name: "Sourdough loaf",
    type: "bread",
    steps: [
      "Feed the starter 8 hours before mixing",
      "Autolyse flour and water for 1 hour",
      "Mix in starter and salt, fold every 30 min for 3 hours",
      "Bulk ferment at 24C for 4 hours",
      "Shape into rounds and proof in banneton 1 hour",
      "Bake in preheated Dutch oven at 240C for 25 min covered, 20 min uncovered"
    ],
    bakingTimeMin: 45,
    bakingTempC: 240,
    variations: ["whole wheat", "olive", "cranberry walnut"],
    allergens: ["Gluten"],
    hydrationPct: 75.0,
    fermentationHours: 6
  },
  // 2. Baguette — bread
  {
    productId: 2,
    name: "Baguette",
    type: "bread",
    steps: [
      "Mix flour, water, yeast, salt to 70% hydration",
      "Bulk ferment 2 hours with one fold at 45 min",
      "Divide and pre-shape, rest 20 min",
      "Final shape into baguette, proof 45 min",
      "Score and bake at 230C with steam for 10 min, then dry 15 min"
    ],
    bakingTimeMin: 35,
    bakingTempC: 230,
    variations: ["traditional", "epi", "whole wheat"],
    allergens: ["Gluten"],
    hydrationPct: 70.0,
    fermentationHours: 3
  },
  // 3. Brioche — bread
  {
    productId: 3,
    name: "Brioche",
    type: "bread",
    steps: [
      "Mix flour, sugar, yeast, eggs, milk to a sticky dough",
      "Add softened butter in 4 additions, mix until windowpane",
      "Bulk ferment 1 hour at room temp then refrigerate overnight",
      "Shape into briochette, proof 2 hours",
      "Egg wash and bake at 180C for 25 min"
    ],
    bakingTimeMin: 25,
    bakingTempC: 180,
    variations: ["nanterre", "brioche a tete", "chocolate chip"],
    allergens: ["Gluten", "Eggs", "Milk"],
    hydrationPct: 60.0,
    fermentationHours: 12
  },
  // 4. Croissant — pastry
  {
    productId: 4,
    name: "Croissant",
    type: "pastry",
    steps: [
      "Make detrempe with flour, milk, yeast, sugar, salt",
      "Encase butter block and laminate 3 single folds",
      "Rest 1 hour in fridge between folds",
      "Roll to 4mm and cut triangles",
      "Shape and proof 2 hours",
      "Egg wash and bake at 220C for 18 min"
    ],
    bakingTimeMin: 18,
    bakingTempC: 220,
    variations: ["plain", "almond", "chocolate"],
    allergens: ["Gluten", "Eggs", "Milk"],
    laminationFolds: 3,
    butterPct: 25.0
  },
  // 5. Pain au chocolat — pastry
  {
    productId: 5,
    name: "Pain au chocolat",
    type: "pastry",
    steps: [
      "Make croissant dough (detrempe + butter)",
      "Laminate 3 single folds",
      "Roll to 4mm and cut rectangles",
      "Place two chocolate batons and roll up",
      "Proof 2 hours, egg wash",
      "Bake at 220C for 18 min"
    ],
    bakingTimeMin: 18,
    bakingTempC: 220,
    variations: ["dark chocolate", "milk chocolate", "pistachio"],
    allergens: ["Gluten", "Eggs", "Milk", "Soy (in some chocolate)"],
    laminationFolds: 3,
    butterPct: 25.0
  },
  // 6. Cinnamon roll — pastry
  {
    productId: 6,
    name: "Cinnamon roll",
    type: "pastry",
    steps: [
      "Mix enriched dough with butter, milk, eggs",
      "Bulk ferment 1 hour",
      "Roll to 1cm, spread butter+cinnamon+sugar filling",
      "Roll up and slice into 12",
      "Proof 45 min in pan",
      "Bake at 190C for 22 min, top with cream cheese glaze"
    ],
    bakingTimeMin: 22,
    bakingTempC: 190,
    variations: ["pecan", "raisin", "pumpkin spice"],
    allergens: ["Gluten", "Eggs", "Milk"],
    laminationFolds: 0,
    butterPct: 15.0
  },
  // 7. Meat pie — pie
  {
    productId: 7,
    name: "Meat pie",
    type: "pie",
    steps: [
      "Brown minced beef with onions, tomatoes, seasoning",
      "Make shortcrust pastry: flour, butter, salt, cold water",
      "Rest dough 30 min",
      "Roll out bottom crust, add cooled filling, top crust",
      "Egg wash, slit steam vents",
      "Bake at 200C for 35 min"
    ],
    bakingTimeMin: 35,
    bakingTempC: 200,
    variations: ["Nigerian style", "spicy", "curry"],
    allergens: ["Gluten", "Eggs"],
    crustType: "shortcrust",
    filling: "minced beef and onions"
  },
  // 8. Chicken pie — pie
  {
    productId: 8,
    name: "Chicken pie",
    type: "pie",
    steps: [
      "Cook diced chicken with onions, tomatoes, seasoning",
      "Make flaky pastry with butter",
      "Rest 30 min, roll and line dish",
      "Add filling, top crust, crimp edges",
      "Egg wash",
      "Bake at 200C for 35 min"
    ],
    bakingTimeMin: 35,
    bakingTempC: 200,
    variations: ["Nigerian style", "mushroom", "curry"],
    allergens: ["Gluten", "Eggs", "Milk"],
    crustType: "flaky",
    filling: "shredded chicken and vegetables"
  },
  // 9. Chocolate chip cookie — cookie
  {
    productId: 9,
    name: "Chocolate chip cookie",
    type: "cookie",
    steps: [
      "Cream butter and sugars",
      "Beat in eggs and vanilla",
      "Mix in flour, baking powder, salt",
      "Fold in chocolate chips",
      "Scoop and chill 2 hours",
      "Bake at 180C for 12 min until edges are golden"
    ],
    bakingTimeMin: 12,
    bakingTempC: 180,
    variations: ["dark chocolate", "white chocolate macadamia", "double chocolate"],
    allergens: ["Gluten", "Eggs", "Milk", "Soy (in some chocolate)"],
    doughRestHours: 2.0,
    spreadFactor: 1.2
  },
  // 10. Oatmeal raisin cookie — cookie
  {
    productId: 10,
    name: "Oatmeal raisin cookie",
    type: "cookie",
    steps: [
      "Cream butter and brown sugar",
      "Beat in eggs and vanilla",
      "Mix in flour, baking soda, cinnamon, salt",
      "Fold in oats and raisins",
      "Scoop, chill 1 hour",
      "Bake at 180C for 14 min"
    ],
    bakingTimeMin: 14,
    bakingTempC: 180,
    variations: ["cranberry", "white chocolate", "coconut"],
    allergens: ["Gluten", "Eggs", "Milk"],
    doughRestHours: 1.0,
    spreadFactor: 1.0
  }
];

db.recipe_cards.insertMany(recipes, { ordered: true });

print(`Inserted ${recipes.length} recipe card documents.`);
print(`Count check: ${db.recipe_cards.countDocuments()}`);

// Show one example per type so we can screenshot the different shapes.
for (const t of ["bread", "pastry", "pie", "cookie"]) {
  print(`--- example recipe_card of type ${t} ---`);
  printjson(db.recipe_cards.findOne({ type: t }));
}
