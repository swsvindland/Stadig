// Every page, the JSON-LD and the llms.txt files render from this one module,
// so the site, Google and language models all read the same facts.

export const brand = {
  name: "Stadig",
  domain: "https://stadig.dev",
  tagline: "Six scores that move when you do the work.",
  description:
    "Stadig is two free apps for iPhone, iPad, Mac, Apple Vision Pro and Apple Watch. Stadig Lift plans your strength training set by set; Stadig Macro learns your real maintenance and adjusts your nutrition targets every week. Both score the result out of 100. No account, no ads, and they work offline.",
  lede: "Stadig is two apps. Stadig Lift plans your training, set by set. Stadig Macro works out your real maintenance and adjusts your targets every week. Both score the result out of 100.",
  pronunciation: "STAH-dig",
  meaning: "Norwegian for steady.",
  publisher: "Sam Svindland",
  platforms: ["iPhone", "iPad", "Mac", "Apple Vision Pro", "Apple Watch"],
  // The line under every App Store button.
  // Open source: once the repository is public and has a licence, this line becomes
  // "Free and open source. No account.", the Free section gets a "Read the source" link with
  // the licence's name beside it, and the footer's Stadig column gets "Source". Until then
  // the site doesn't say it.
  free: "Free. No account, no ads.",
};

/** A phone screenshot: 624 × 1357, the status bar painted out. */
export type Shot = { src: string; alt: string };
/** A figure on the page: one phone, or Watch faces stacked. */
export type Figure = { label: string; caption: string; phone?: Shot; watch?: Shot[] };

export const phoneSize = { width: 624, height: 1357 };
export const watchSize = { width: 416, height: 496 };

const shot = (name: string, alt: string): Shot => ({ src: `/shots/${name}.webp`, alt });

export const shots = {
  liftToday: shot(
    "lift-today.527cb3cf",
    "Stadig Lift's Today screen: Friday 13 November, the week's days with the trained ones marked, session 4 of 4 of the assessment, Lower B, Deadlift and 3 more, 20 sets, about 62 minutes, a Start session button and Short on time choices of 30 or 45 minutes, and the scores under it: Strength 56, Endurance 97, Agility 62 and Discipline 100.",
  ),
  liftSet: shot(
    "lift-set.26d44e70",
    "A set in Stadig Lift: Conventional Deadlift, warm-ups done and 120 kg for 7 reps marked Now, with 50 kg a side, weight and reps in wells, and three buttons, Easy, Just right and Missed.",
  ),
  liftRest: shot(
    "lift-rest.2cb68ccb",
    "Rest in Stadig Lift after the first deadlift set, rated Just right: a 2:24 countdown over a draining ruler of 2:30, with Undo, −15, +15 and Skip, and the next set, 120 kg for 6.",
  ),
  liftShape: shot(
    "lift-shape.1690ba54",
    "Your shape in Stadig Lift: five scores drawn as a hexagon, Strength 56, Endurance 97, Agility 62, Discipline 100 and Physique 77, with Vitality waiting on Stadig Macro, and a row for each score.",
  ),
  liftExercise: shot(
    "lift-exercise.950b9543",
    "Barbell Bench Press in Stadig Lift: an estimated one-rep max of 89 kg, up 3 kg in 2 weeks, its line over three weeks, a strength score of 51, Novice, and its best sets.",
  ),
  liftWatchRate: shot("lift-watch-rate.0535df18", "Stadig Lift on Apple Watch: the set rated with one tap, Easy, Just right or Missed, each filling a third of the face."),
  liftWatchRest: shot("lift-watch-rest.3807998a", "Stadig Lift on Apple Watch: rest at 1:25, its level rising toward go, next 82.5 for 8, and Go now."),
  macroToday: shot(
    "macro-today.9f26a47d",
    "Stadig Macro's Today screen at lunch: 1,299 kcal left of 2,200 in week 1 of a cut, protein, carbs and fat left, lunch on the thread (chicken breast, white rice and broccoli), and four foods usually eaten around now, one tap each, above the box to add food.",
  ),
  macroTyping: shot(
    "macro-typing.ce7d5422",
    "Typing “chick 200” on Stadig Macro's Today: the best match, Chicken breast, roasted, 200 g, 330 kcal, marked with a return key, and the target already showing 2,200 going to 1,870 kcal left.",
  ),
  macroLogged: shot(
    "macro-logged.bde8518d",
    "Stadig Macro after typing “2 eggs, toast, coffee” and pressing Return: Egg, fried, Wheat bread, toasted and Coffee, brewed logged together at 1:31 PM, 271 kcal with one Undo, and 1,929 kcal left.",
  ),
  macroTonight: shot(
    "macro-tonight.8b70d164",
    "Stadig Macro in the evening: 1,045 kcal left, almonds and apples at the end of the day's thread, and What fits tonight offering potatoes with salmon, leaving 323 kcal, or chicken breast with white rice, leaving 480.",
  ),
  macroShape: shot(
    "macro-shape.4030021b",
    "Your shape in Stadig Macro: Vitality 92, logged 92% of days, and Discipline 28 for nutrition, with the four scores Stadig Lift measures left open.",
  ),
  macroPlan: shot(
    "macro-plan.bd865100",
    "Stadig Macro's Plan: a cut, week 1 of 4, losing 0.5% a week, at 2,200 kcal a day with 165 g protein, 240 g carbs and 65 g fat, the trend at −1.09 kg a week, faster than planned, a Why? link, and the year ahead.",
  ),
  macroWatchToday: shot("macro-watch-today.d5179cbd", "Stadig Macro on Apple Watch: 1,738 kcal left today, 602 eaten of 2,340, 130 g of protein left, over a level filling from the foot."),
  macroWatchAgain: shot("macro-watch-again.79bca3b5", "Stadig Macro on Apple Watch: Log Again with Greek yogurt, 200 g, usually eaten now, and a Log button that leaves 1,620 kcal."),
};

export type Rate = { tone: "good" | "ok" | "bad" | "accent"; eyebrow: string; word: string; body: string };
export type Step = { title: string; body: string };
export type Feature = { title: string; body: string };

export type App = {
  slug: "lift" | "macro";
  name: string;
  short: string;
  oneLiner: string;
  description: string;
  platforms: string[];
  category: string;
  appStoreUrl: string | null;
  headline: string;
  lede: string;
  /** The home page's chapter for this app. */
  home: { lede: string };
  hero: Figure[];
  rates: { eyebrow: string; aside: string; items: Rate[] };
  session: { eyebrow: string; title: string; lede: string; points: Feature[]; figures: Figure[] };
  how: Step[];
  features: Feature[];
  progress: {
    title: [string, string];
    reading: { value: number; name: string; trend?: string; note: string; levels: boolean };
    lede: string;
    body: string;
    figures: Figure[];
  };
  free: { lede: string; items: string[] };
  other: { title: string; lede: string; shot: Shot };
  keywords: string[];
};

export const apps: App[] = [
  {
    slug: "lift",
    name: "Stadig Lift",
    short: "Strength training",
    oneLiner: "Every session prescribed. Every set adjusted to how it went.",
    description:
      "Stadig Lift is a free strength training app for iPhone, iPad, Mac, Apple Vision Pro and Apple Watch. It writes your program, sets every weight, adjusts each set to how the last one felt, and tells you when to push, hold or deload. It learns how honest your effort ratings are, budgets fatigue across lifting and everything else you do, and moves your scores only on real tests.",
    platforms: ["iPhone", "iPad", "Mac", "Apple Vision Pro", "Apple Watch"],
    category: "HealthApplication",
    appStoreUrl: "https://apps.apple.com/app/stadig-lift/id6824198193",
    headline: "A program that writes itself around you.",
    lede: "Stadig Lift writes your program, adjusts every set to how the last one felt, and tells you when to push, hold or deload.",
    home: {
      lede: "Most training apps are notebooks: you decide what to do, they remember it. Stadig Lift decides. It builds the block, sets the weight, and after every set asks one thing: how did that go?",
    },
    hero: [
      { label: "Today", caption: "The session is already written.", phone: shots.liftToday },
      { label: "Mid-session", caption: "The set in front of you, filled in. One tap logs it.", phone: shots.liftSet },
    ],
    rates: {
      eyebrow: "Mid-session, this is the whole interface",
      aside: "One tap logs the set and starts your rest",
      items: [
        { tone: "good", eyebrow: "3 or more reps left", word: "Easy", body: "Bumps the weight or the reps." },
        { tone: "ok", eyebrow: "0 to 2 left", word: "Just right", body: "Holds." },
        { tone: "bad", eyebrow: "Fell short", word: "Missed", body: "Drops a little, because missed reps are data, not failure." },
      ],
    },
    session: {
      eyebrow: "A session, start to finish",
      title: "You lift. It does the arithmetic.",
      lede: "Warm-ups, the plates a side, rest and the next weight are worked out before you ask. Change a set with − and +, no keyboard needed.",
      points: [
        {
          title: "Rest that listens",
          body: "The countdown takes the set's place, with −15, +15 and Skip. With the Watch on, a rest guided by heart rate ends early once you've recovered.",
        },
        {
          title: "A last set that tells the truth",
          body: "As many as you can. A rep-out after a rated set shows how honest the rating was.",
        },
        {
          title: "On the wrist",
          body: "The Watch app logs and rates sets, times rest by heart rate and runs conditioning by zone. A Live Activity holds the rest on the phone.",
        },
      ],
      figures: [
        { label: "1 · Set", caption: "Target filled in. Tap how it felt.", phone: shots.liftSet },
        { label: "2 · Rest", caption: "The next set waits under the clock.", phone: shots.liftRest },
        { label: "3 · Watch", caption: "Rate the set and rest from your wrist.", watch: [shots.liftWatchRate, shots.liftWatchRest] },
      ],
    },
    how: [
      { title: "Set up once", body: "Days, time, equipment, experience, and goals as outcomes. If Stadig Macro already asked, Stadig Lift doesn't." },
      {
        title: "A short assessment block",
        body: "Safe-to-fail anchors find your real numbers and calibrate your ratings. Weekly notes say what was learned. Experienced lifters finish early.",
      },
      { title: "One plan, with a why", body: "After the assessment you get one block, not a menu. Stadig Macro's phase sets its direction if you use both." },
      { title: "Train, rate, repeat", body: "Sets autoregulate, stalls get read in context, and check-ins keep the scores honest." },
    ],
    features: [
      {
        title: "It learns whether to believe you",
        body: "Everyone misjudges reps in reserve. Stadig Lift starts with a guess from your experience and rebuilds its trust in your ratings from evidence: a rep-out after a rated set reveals the truth, and a heavier later set proves more was left.",
      },
      {
        title: "A fatigue budget, never a score",
        body: "Every set has a systemic and a local cost. Martial arts classes, runs and anything from Health spend the same budget. Sleep, HRV, resting heart rate, soreness and life stress feed it. When signals stack, the deload comes early.",
      },
      {
        title: "Blocks that bend around life",
        body: "Five weeks plus a deload by default, shorter in a cut, longer in a bulk. A vacation near the deload becomes it. Crunch, injury and illness modes change the plan instead of breaking it.",
      },
      {
        title: "Scores that only move on tests",
        body: "Strength is scored against bodyweight standards, free weights only, and imbalances become priorities. Endurance from VO₂ max, resting heart rate and benchmarks. Agility from five mobility tests. Physique from the tape.",
      },
      {
        title: "Your equipment, your joints",
        body: "It picks the exercises your equipment and joints allow, says how hard each one is on a shoulder or an elbow, and lists the substitutes in your gym.",
      },
      {
        title: "Offline, and yours",
        body: "The exercise library ships inside the app, so it works in a basement gym. No account, no analytics. Export to CSV and back up whenever you like.",
      },
    ],
    progress: {
      title: ["Am I progressing?", "One number answers."],
      reading: { value: 57, name: "Strength · Novice", trend: "Rising", note: "3 points to Intermediate.", levels: true },
      lede: "Overhead press is the limiter, so the next block makes it a priority. The number moves only on what you lift, never on time in the app.",
      body: "Stadig Lift measures Strength, Physique, Endurance and Agility, and the training half of Discipline. Add Stadig Macro and both apps show all six scores.",
      figures: [
        { label: "Your shape", caption: "Five scores, each with what holds it back. Vitality waits on Stadig Macro.", phone: shots.liftShape },
        { label: "Every lift", caption: "Its estimated max, its line, and its own score on the levels.", phone: shots.liftExercise },
      ],
    },
    free: {
      lede: "Stadig Lift is free, all of it: every training block, every deload, every life mode.",
      items: ["Logging", "The exercise library", "The assessment", "Every training block", "Deloads", "Life modes", "CSV export", "Backups"],
    },
    other: {
      title: "Stadig Macro sets the phase. Stadig Lift builds around it.",
      lede: "Stadig Macro learns your real maintenance, picks the phase and adjusts your targets weekly. A cut shortens the block and reads stalls as expected. A bulk lengthens it.",
      shot: shots.macroToday,
    },
    keywords: [
      "strength training app",
      "autoregulation",
      "RPE",
      "progressive overload",
      "workout program generator",
      "Apple Watch lifting app",
      "deload",
      "fatigue management",
      "free workout planner",
    ],
  },
  {
    slug: "macro",
    name: "Stadig Macro",
    short: "Nutrition",
    oneLiner: "Learns your real maintenance. Picks the phase. Adjusts weekly.",
    description:
      "Stadig Macro is a free nutrition app for iPhone, iPad, Mac, Apple Vision Pro and Apple Watch. It works out your actual maintenance calories from what you log and weigh, recommends one phase (cut, bulk or maintenance) with its reasons, and adapts your targets every week. Today is the logger: one tap for what you usually eat around now, or type “chick 200” and press Return. Barcode, label, photo and voice logging are read by Apple's on-device models, over offline food, supplement and drink catalogs.",
    platforms: ["iPhone", "iPad", "Mac", "Apple Vision Pro", "Apple Watch"],
    category: "HealthApplication",
    appStoreUrl: "https://apps.apple.com/app/stadig-macro/id6824204323",
    headline: "Spend less time in your food app.",
    lede: "Stadig Macro fits your maintenance to what the scale actually did, picks one phase, and moves your targets a little each week. Logging is a tap, or a few letters and Return.",
    home: {
      lede: "Calorie counting fails for two reasons: the target is a guess, and logging is a chore. Stadig Macro fits your maintenance to what the scale actually did, then moves the targets a little each week.",
    },
    hero: [
      { label: "Today", caption: "What you usually eat around now, one tap each.", phone: shots.macroToday },
      { label: "Typing", caption: "“chick 200”, then Return. Logged.", phone: shots.macroTyping },
    ],
    rates: {
      eyebrow: "On Today, this is the whole interface",
      aside: "Every log comes with an Undo",
      items: [
        { tone: "accent", eyebrow: "Usually around now", word: "Tap", body: "A food you often eat at this hour, logged at its usual amount." },
        {
          tone: "accent",
          eyebrow: "Return logs it",
          word: "Type",
          body: "“chick 200” finds roasted chicken breast at 200 g. A whole line logs every food in it.",
        },
        { tone: "accent", eyebrow: "Camera and microphone", word: "Scan", body: "A barcode, a label or a photo. Or say what you ate." },
      ],
    },
    session: {
      eyebrow: "A day, start to finish",
      title: "You eat. It keeps count.",
      lede: "The day is a thread of what you ate, the newest by the box. Tap a food to change its amount in place; a swipe deletes it.",
      points: [
        { title: "Goes with", body: "Right after a meal, the tiles turn to what you usually eat with it." },
        {
          title: "What fits tonight",
          body: "From 5 PM, the foods you usually eat that fit what's left, alone or in pairs you've eaten together, ranked by the protein they cover.",
        },
        { title: "On the wrist", body: "Calories left on a Watch face, and Log Again with the foods you eat around now." },
      ],
      figures: [
        { label: "1 · One line", caption: "“2 eggs, toast, coffee” and Return: three foods, one Undo.", phone: shots.macroLogged },
        { label: "2 · Tonight", caption: "Two dinners that fit, and what each leaves.", phone: shots.macroTonight },
        { label: "3 · Watch", caption: "Calories left, and one tap for your usual.", watch: [shots.macroWatchToday, shots.macroWatchAgain] },
      ],
    },
    how: [
      { title: "Log for a couple of weeks", body: "Daily weigh-ins and whatever you eat. Complete days are what count; nothing is judged." },
      { title: "Get an assessment", body: "Maintenance, trend, and one recommended phase with its reasons. You can pick another." },
      { title: "Targets adapt each week", body: "Damped and capped, holding on jumps. In a cut, falling steps are read before calories are." },
      {
        title: "Never open it if you'd rather not",
        body: "Siri, Shortcuts, widgets with buttons, the Action Button and Controls all log without the app.",
      },
    ],
    features: [
      {
        title: "Your maintenance, measured",
        body: "A smoothed weight trend against mean intake on complete days gives your real maintenance. Weekly check-ins move it a third of the way and cap target changes at 150 kcal, so one bad weigh-in can't swing your week.",
      },
      {
        title: "One phase, with reasons",
        body: "Cut, bulk, maintenance, recomp or a diet break. Stadig Macro recommends one and says why, from your trend, your strength standards and how long you've been dieting. Stadig Lift builds its block around the answer.",
      },
      {
        title: "Live label scanning",
        body: "Keep the camera on the Nutrition Facts panel. It reads line by line as you pan, so a label too tall for one photo still gets read. Barcodes jump straight to the food.",
      },
      {
        title: "A photo or a sentence",
        body: "“Two eggs, toast with butter and a flat white.” Apple's on-device model names the foods and amounts. The nutrients always come from the catalog, never from a guess.",
      },
      {
        title: "Food quality, not just macros",
        body: "Ultra-processed share of calories by NOVA group, fermented foods counted by the day, and a week of prep-friendly meals sized to your targets, with the grocery list and a timed prep day.",
      },
      {
        title: "Supplements, drinks and caffeine",
        body: "Scan a bottle and its label comes from the NIH database, offline. Doses by time of day, with upper-limit warnings that name the fix. Water, coffee and caffeine with a half-life model, if you want them.",
      },
    ],
    progress: {
      title: ["Am I keeping it up?", "One number answers."],
      reading: { value: 92, name: "Vitality", note: "Logged 92% of days", levels: false },
      lede: "Vitality is the share of days you log. Under your shape: the weight trend, calories against target and maintenance, and food quality.",
      body: "Stadig Macro measures Vitality and the nutrition half of Discipline. Add Stadig Lift and both apps show all six scores.",
      figures: [
        { label: "Your shape", caption: "Two scores from your food. Stadig Lift measures the rest.", phone: shots.macroShape },
        { label: "Plan", caption: "One phase, its targets, and why.", phone: shots.macroPlan },
      ],
    },
    free: {
      lede: "Stadig Macro is free, all of it: the phase plan, the weekly targets, every way to log.",
      items: [
        "Logging",
        "Barcode and label scans",
        "Photo and voice",
        "The assessment",
        "The phase plan",
        "Weekly targets",
        "Meal plans",
        "Supplements",
        "CSV export",
        "Backups",
      ],
    },
    other: {
      title: "Stadig Lift builds the block around your phase.",
      lede: "Stadig Lift writes your program, sets every weight and adjusts each set to how the last one felt. In a cut it shortens the block and reads a stall as expected.",
      shot: shots.liftToday,
    },
    keywords: [
      "calorie tracking app",
      "macro tracker",
      "adaptive TDEE",
      "maintenance calories",
      "barcode scanner nutrition",
      "AI food logging",
      "offline food database",
      "supplement tracker",
      "free calorie counter",
    ],
  },
];

export const appBySlug = (slug: App["slug"]) => apps.find((a) => a.slug === slug)!;

/** The home page's chapter on Stadig Macro: the facts beside its two screens. */
export const macroFacts = [
  { n: "1", unit: "tap", body: "logs what you usually eat around now." },
  { n: "3", unit: "foods", body: "from one line. Type “2 eggs, toast, coffee” and all three are logged. Or scan it, photograph it or say it." },
  { n: "150", unit: "kcal", body: "is the most a target moves in a week, so one bad weigh-in can't swing it." },
];
export const homeFigures = {
  lift: [
    {
      label: "1 · Today",
      caption: "Open the app and the session is already written. Short on time? Tap 30 or 45 minutes and it fits.",
      phone: shots.liftToday,
    },
    { label: "2 · Set", caption: "Every set comes filled in. One tap logs it: Easy, Just right or Missed.", phone: shots.liftSet },
    { label: "3 · Rest", caption: "The timer starts itself. With the Watch on, it ends early once your heart rate has recovered.", phone: shots.liftRest },
    { label: "4 · Your shape", caption: "Every score Stadig Lift measures, each with the thing holding it back.", phone: shots.liftShape },
  ] as Figure[],
  macro: [
    {
      label: "Today",
      caption: "Type “chick 200” and press Return: the best match is logged at 200 g. Nothing asks you to confirm.",
      phone: shots.macroTyping,
    },
    {
      label: "What fits tonight",
      caption: "After 5 PM, the foods you usually eat that fit what's left, ranked by the protein they cover.",
      phone: shots.macroTonight,
    },
  ] as Figure[],
};

/** The six scores, in the order the apps draw them, clockwise from the top. Sample values, as the apps show them:
 *  each with a trend word, not a month's change, since the apps don't keep a score's history yet. */
export type Score = {
  name: string;
  apps: ("lift" | "macro")[];
  source: string;
  value: number;
  trend: "rising" | "on pace" | "steady" | "slipping";
  next: string;
  split?: { label: string; value: number; app: "lift" | "macro" }[];
};
export const trendTone = { rising: "good", "on pace": "good", steady: "steady", slipping: "ok" } as const;
export const scores: Score[] = [
  {
    name: "Strength",
    apps: ["lift"],
    source: "Estimated maxes on free-weight lifts, against bodyweight standards.",
    value: 57,
    trend: "rising",
    next: "Overhead press is the limiter",
  },
  {
    name: "Endurance",
    apps: ["lift"],
    source: "VO₂ max, resting heart rate, benchmarks and weekly cardio.",
    value: 48,
    trend: "on pace",
    next: "Add 20 minutes of Zone 2 this week",
  },
  {
    name: "Agility",
    apps: ["lift"],
    source: "Five mobility tests. The weakest is named.",
    value: 61,
    trend: "steady",
    next: "Hip mobility is the limiter",
  },
  {
    name: "Vitality",
    apps: ["macro"],
    source: "How steadily you log your food.",
    value: 72,
    trend: "slipping",
    next: "Logged 72% of days",
  },
  {
    name: "Discipline",
    apps: ["lift", "macro"],
    source: "Four weeks of the plan kept, in the gym and at the table.",
    value: 86,
    trend: "rising",
    next: "Training 88% · Nutrition 84%",
    split: [
      { label: "Training", value: 88, app: "lift" },
      { label: "Nutrition", value: 84, app: "macro" },
    ],
  },
  {
    name: "Physique",
    apps: ["lift"],
    source: "The tape: waist to height and your proportions.",
    value: 64,
    trend: "rising",
    next: "Tape your waist this week",
  },
];
/** The table lists them in reading order: what you lift first, what you keep last. */
export const scoreRows = ["Strength", "Physique", "Endurance", "Agility", "Discipline", "Vitality"].map(
  (n) => scores.find((s) => s.name === n)!,
);

export const different = [
  {
    title: "It plans itself.",
    body: "Stadig Lift writes the block, sets every weight and brings the deload early when the signals stack. Stadig Macro recommends one phase, says why, and adjusts your targets weekly.",
  },
  {
    title: "Logging is one tap.",
    body: "Rate a set Easy, Just right or Missed and it is logged. Log a usual meal again with a tap, type a few letters and press Return, or scan a label, take a photo or say what you ate.",
  },
  {
    title: "No account. No ads.",
    body: "Nothing to sign up for, no analytics and no third-party code. Your data lives on your devices and in your own iCloud.",
  },
  {
    title: "No streaks to protect.",
    body: "Discipline is a four-week adherence rate. One miss barely dents it, rest days are part of the plan, and a day you didn't log is unknown, not a failure.",
  },
  {
    title: "It works offline.",
    body: "The exercise library and the food and supplement catalogs ship inside the apps. They work on a plane and in a basement gym.",
  },
];

/** Everything in both apps, for the Free section: which app has each. */
export const everything: { name: string; apps: ("lift" | "macro")[] }[] = [
  { name: "Logging", apps: ["lift", "macro"] },
  { name: "The assessment", apps: ["lift", "macro"] },
  { name: "Every training block", apps: ["lift"] },
  { name: "Deloads", apps: ["lift"] },
  { name: "Life modes", apps: ["lift", "macro"] },
  { name: "The phase plan", apps: ["macro"] },
  { name: "Weekly adaptive targets", apps: ["macro"] },
  { name: "Photo and voice logging", apps: ["macro"] },
  { name: "Export", apps: ["lift", "macro"] },
  { name: "Backup", apps: ["lift", "macro"] },
];

export const principles = [
  {
    title: "Prescribe, don't describe",
    body: "A chart tells you what happened. Stadig apps tell you what to do next. Every insight ends in one concrete action, and the plan is written for you, with a Why if you want it.",
  },
  {
    title: "Real-world tests, not time in the app",
    body: "Strength moves on lifts, Endurance on heart-rate benchmarks, Agility on mobility tests, Physique on the tape. Opening the app or time spent in it moves nothing.",
  },
  {
    title: "No XP and no streaks",
    body: "Discipline is a rolling four-week adherence rate with an 80 to 90 percent target band. Above it earns nothing extra, and one miss barely dents it. Rest is part of the plan. A day you didn't log is unknown, not a failure.",
  },
  {
    title: "Offline first",
    body: "The exercise library and the food and supplement catalogs ship inside the apps. They work on a plane and in a basement gym. iCloud sync is there for your own devices.",
  },
  {
    title: "Private by construction",
    body: "No account. No analytics. Your data lives on your devices and in your iCloud. Where an app uses a language model, it's Apple's on-device model, or Private Cloud Compute only when you allow it. Progress photos are never analysed.",
  },
  {
    title: "Free, all of it",
    body: "Both apps are free: every plan, every target, every way to log. Nothing to unlock, no tiers and no ads. Export and backups are built in, so your data is always yours to take.",
  },
  {
    title: "No third-party code",
    body: "Swift, SwiftUI, SwiftData and Apple's frameworks. No SDKs phoning home, no trackers, nothing to break when a vendor changes terms.",
  },
];

export const together = [
  {
    title: "Stadig Macro sets the phase. Stadig Lift builds around it.",
    body: "A cut shortens the block and reads stalls as expected. A bulk lengthens it. Stadig Lift waits with a neutral block while Stadig Macro is still deciding.",
  },
  {
    title: "Steps are read before calories are cut.",
    body: "Stadig Lift sets a daily step aim from your usual count, never a universal 10,000. When steps fall in a cut, Stadig Macro reads that before it cuts calories.",
  },
  {
    title: "Life modes are shared.",
    body: "Say you're on vacation, ill or in crunch once. Both apps reflow: the block and the targets. None of those days count against you.",
  },
  {
    title: "Six scores, in both.",
    body: "Each app shows the scores it measures. With both set up, each shows all six, labelled with the app that measures each one.",
  },
];

export const faq = [
  {
    q: "What is Stadig?",
    a: "Stadig is two free apps for training and nutrition on iPhone, iPad, Mac, Apple Vision Pro and Apple Watch: Stadig Lift and Stadig Macro. They share one idea: use your own data to prescribe the next thing to do, instead of charting what you did. The name is Norwegian for steady.",
  },
  {
    q: "What does it cost?",
    a: "Nothing. Both apps are free, all of it: every plan, every target, every way to log. There's nothing to unlock, no ads and no account.",
  },
  {
    q: "Do I need both apps?",
    a: "No. Each app works alone. Together they share a profile, life modes and a calendar, so Stadig Macro's phase shapes Stadig Lift's block and Stadig Lift's step count is read before Stadig Macro cuts calories. With both set up, each app shows all six scores.",
  },
  {
    q: "What are the six scores?",
    a: "Strength, Physique, Endurance, Agility, Vitality and Discipline, each from 0 to 100 and drawn together as your shape. Stadig Lift measures Strength, Physique, Endurance and Agility; Stadig Macro measures Vitality; Discipline is shared, the plan kept in the gym and at the table. Each app shows its own scores, and with both set up each shows all six, labelled with the app that measures it.",
  },
  {
    q: "Do the apps work offline?",
    a: "Yes. The exercise library and the food and supplement catalogs ship inside the apps. Sync between your own devices uses iCloud when you're online.",
  },
  {
    q: "Where does my data go?",
    a: "Your devices and your private iCloud database. There is no account and no analytics. Stadig Macro's photo and label reading uses Apple's on-device model, and Apple's Private Cloud Compute only when you turn that on.",
  },
  {
    q: "What does \"prescribe, don't describe\" mean?",
    a: "A tracker describes: here is your volume, here is your calorie average. Stadig apps prescribe: add 2.5 kg to the next set, eat 150 kcal less this week. Every screen ends in an action.",
  },
  {
    q: "Why no streaks?",
    a: "Streaks reward showing up, not improving, and they punish the rest days a good plan contains. Discipline in Stadig apps is a four-week adherence rate with a target band, where one missed day barely registers and vacations and illness don't count at all.",
  },
  {
    q: "What devices are supported?",
    a: "Both run on iPhone, iPad, Mac and Apple Vision Pro, and both have Apple Watch apps. On the iPad and the Mac each does more than on the phone: Stadig Lift lays out your program and exercise library, and Stadig Macro compares foods and plans the week. Your data syncs between your devices through iCloud.",
  },
  {
    q: "Which AI models do the apps use?",
    a: "Only Apple's. Stadig Macro uses the on-device Foundation Model to name foods and amounts from a photo, a sentence or a label scan. The nutrients always come from the offline catalog. No third-party AI service ever sees your data.",
  },
  {
    q: "How do I pronounce Stadig?",
    a: "STAH-dig. It is the Norwegian word for steady.",
  },
];

export const nav = [
  { href: "/lift", label: "Stadig Lift" },
  { href: "/macro", label: "Stadig Macro" },
  { href: "/#scores", label: "Scores" },
  { href: "/#free", label: "Free" },
  { href: "/principles", label: "Principles" },
  { href: "/faq", label: "FAQ" },
];
