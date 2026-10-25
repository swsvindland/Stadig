// Every page, the JSON-LD and the llms.txt files render from this one module,
// so the site, Google and language models all read the same facts.

export const brand = {
  name: "Stadig",
  domain: "https://stadig.dev",
  tagline: "Apps that tell you what to do next.",
  description:
    "Stadig is three fast, offline-first apps for training, nutrition and study on iPhone, iPad, Mac and Apple Vision Pro: Stadig Lift, Stadig Macro and Stadig Mind. They prescribe your next session, meal target and lesson from your own data. No subscriptions, no streaks, no account.",
  pronunciation: "STAH-dig",
  meaning: "Norwegian for steady.",
  publisher: "Sam Svindland",
  email: "hello@stadig.dev",
};

export type App = {
  slug: string;
  name: string;
  short: string;
  oneLiner: string;
  description: string;
  platforms: string[];
  category: string;
  accent: string;
  appStoreUrl: string | null;
  headline: string;
  intro: string[];
  features: { title: string; body: string }[];
  how: { title: string; body: string }[];
  free: string;
  keywords: string[];
};

export const apps: App[] = [
  {
    slug: "lift",
    name: "Stadig Lift",
    short: "Training",
    oneLiner: "Every session prescribed. Every set adjusted to how it went.",
    description:
      "Stadig Lift is a strength training app for iPhone, iPad, Mac, Apple Vision Pro and Apple Watch that writes your program, adjusts every set to how the last one felt, and tells you when to push, hold or deload. It learns how honest your effort ratings are, budgets fatigue across lifting and everything else you do, and moves your stats only on real tests.",
    platforms: ["iPhone", "iPad", "Mac", "Apple Vision Pro", "Apple Watch"],
    category: "HealthApplication",
    accent: "lift",
    appStoreUrl: null,
    headline: "A program that writes itself around you.",
    intro: [
      "Most training apps are notebooks. You decide what to do, they remember it. Stadig Lift decides. It builds the block, picks the exercises your equipment and joints allow, sets the weight, and after every set asks one thing: how did that go?",
      "Easy, Just right or Missed. That is the whole interface mid-session. The next set moves on the answer.",
    ],
    features: [
      {
        title: "Three-tap sets",
        body: "Rate a set Easy, Just right or Missed. Easy bumps the weight or the reps. Just right holds. Missed drops a little, because missed reps are data, not failure.",
      },
      {
        title: "It learns whether to believe you",
        body: "Everyone misjudges reps in reserve. Stadig Lift starts with a guess from your experience and rebuilds its trust in your ratings from evidence: a rep-out after a rated set reveals the truth, and a heavier later set proves more was left. Low trust means verification only on safe setups.",
      },
      {
        title: "A fatigue budget, never a score",
        body: "Every set has a systemic and local cost. Martial arts classes, runs and anything from Health spend the same budget. Sleep, HRV, resting heart rate, soreness and life stress feed it. When signals stack, the deload comes early. You never see a number.",
      },
      {
        title: "Blocks that bend around life",
        body: "Five weeks plus a deload by default, shorter in a cut, longer in a bulk. A vacation near the deload becomes it. Crunch, injury and illness modes change the plan instead of breaking the streak you don't have.",
      },
      {
        title: "Stats that only move on tests",
        body: "Strength is scored against bodyweight-relative standards, free weights only, with imbalances becoming priorities. Endurance from heart-rate benchmarks. Agility from five mobility tests. Physique from the tape. None of them move because you opened the app.",
      },
      {
        title: "On the wrist",
        body: "The Watch app logs and rates sets, times rest by heart rate with minimums for heavy lifts, and runs conditioning by zone. A Live Activity holds the rest countdown on the phone.",
      },
    ],
    how: [
      { title: "Set up once", body: "Days, time, equipment, experience, goals as outcomes. If Stadig Macro already asked, Stadig Lift doesn't." },
      { title: "A short assessment block", body: "Safe-to-fail anchors find your real numbers and calibrate your ratings. Weekly notes say what was learned. Experienced lifters finish early." },
      { title: "One plan, with a why", body: "After the assessment you get one block, not a menu. Stadig Macro's phase sets its direction if you use both." },
      { title: "Train, rate, repeat", body: "Sets autoregulate, stalls get read in context (expected in a cut, a recovery problem when beat up), and check-ins keep the stats honest." },
    ],
    free: "Logging, the exercise library, CSV export and backups are free. The one-time purchase unlocks programs after the assessment.",
    keywords: ["strength training app", "autoregulation", "RPE", "progressive overload", "workout program generator", "Apple Watch lifting app", "deload", "fatigue management"],
  },
  {
    slug: "macro",
    name: "Stadig Macro",
    short: "Nutrition",
    oneLiner: "Learns your real maintenance. Picks the phase. Adjusts weekly.",
    description:
      "Stadig Macro is a nutrition app for iPhone, iPad, Mac, Apple Vision Pro and Apple Watch that works out your actual maintenance calories from logging and weigh-ins, recommends one phase (cut, bulk or maintenance) with its reasons, and adapts your targets every week. Logging is a glance and a tap: search, barcode, live label scan, a photo or a sentence, read by Apple's on-device models. Offline food, supplement and drink catalogs.",
    platforms: ["iPhone", "iPad", "Mac", "Apple Vision Pro", "Apple Watch"],
    category: "HealthApplication",
    accent: "macro",
    appStoreUrl: null,
    headline: "Spend less time in your food app.",
    intro: [
      "Calorie counting fails for two reasons: the target is a guess, and logging is a chore. Stadig Macro fixes both. It fits your maintenance to what the scale actually did while you ate what you actually logged, then prescribes a phase and moves the targets a little each week.",
      "And it is built so a visit is seconds. Log again in one tap. Scan a label like you're filming it. Say what you ate.",
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
        body: "Keep the camera on the Nutrition Facts panel. It reads line by line as you pan, so a label too tall for one photo still gets read. Barcodes jump straight to the food. Apple's on-device model checks the numbers against what's printed.",
      },
      {
        title: "A photo or a sentence",
        body: "\"Two eggs, toast with butter and a flat white.\" Apple's on-device model names the foods and amounts. The nutrients always come from the catalog, never from a guess. Private Cloud Compute only when you allow it.",
      },
      {
        title: "Food quality, not just macros",
        body: "Ultra-processed share of calories by NOVA group with an aim under a fifth, fermented foods counted by the day, and a week of prep-friendly meals sized to your targets with the grocery list and a timed prep day.",
      },
      {
        title: "Supplements, drinks and caffeine",
        body: "Scan a bottle and its label comes from the NIH database, offline. Doses by time of day, ticked off from a notification or Siri, with upper-limit warnings that name the fix. Water, coffee and caffeine with a half-life model, if you want them.",
      },
    ],
    how: [
      { title: "Log for a couple of weeks", body: "Daily weigh-ins and whatever you eat. Complete days are what count; nothing is scored." },
      { title: "Get an assessment", body: "Maintenance, trend, and one recommended phase with its reasons. You can pick another." },
      { title: "Targets adapt each week", body: "Damped and capped, holding on jumps. In a cut, falling steps are read before calories are." },
      { title: "Never open it if you'd rather not", body: "Siri, Shortcuts, widgets with buttons, the Action Button and Controls all log without the app." },
    ],
    free: "Logging, photo and description logging, the assessment, export and backup are free. The one-time purchase unlocks the phase plan.",
    keywords: ["calorie tracking app", "macro tracker", "adaptive TDEE", "maintenance calories", "barcode scanner nutrition", "AI food logging", "offline food database", "supplement tracker"],
  },
  {
    slug: "mind",
    name: "Stadig Mind",
    short: "Study",
    oneLiner: "Training for the mind. 25 minutes a day, prescribed.",
    description:
      "Stadig Mind is a study app for iPhone, iPad, Mac and Apple Vision Pro that runs focused 25-minute sessions in Japanese, maths, writing and reading. A two-week assessment finds your level in each, subjects rotate across the week like a training split, spaced repetition brings things back just before you'd forget them, and new material comes only once the last thing has stuck.",
    platforms: ["iPhone", "iPad", "Mac", "Apple Vision Pro"],
    category: "EducationalApplication",
    accent: "mind",
    appStoreUrl: null,
    headline: "Progressive overload for your head.",
    intro: [
      "Study apps hand you a pile of cards and a streak. Stadig Mind hands you a session. Reviews first, then the day's subjects, then practice, in one 25-minute block that ends when the timer does.",
      "It finds your level in each subject, adds new material at a rate your recall can carry, and measures you only on tests. Time spent counts for nothing.",
    ],
    features: [
      {
        title: "A split, like training",
        body: "Japanese twice a week, maths with writing and reading the rest, never the same group two days running. A subject that slips gets an extra day.",
      },
      {
        title: "Spaced repetition you don't grade",
        body: "The open FSRS model at 90% recall. Right or wrong and how long it took decide the grade, so you can't be kind to yourself.",
      },
      {
        title: "Mastery before more",
        body: "A maths topic or writing skill is mastered at four of the last five right, ending on a right one. Two missed reviews put it back into learning, and what builds on it waits.",
      },
      {
        title: "Japanese from 20,000 words",
        body: "Ordered by how often real sentences use them, taught with kanji and an example at your level, asked by meaning, reading and ear with Apple's Japanese voice. 85,000 graded sentences, 3,100 kanji, all offline.",
      },
      {
        title: "Maths with endless problems",
        body: "49 topics in ten levels from order of operations to integration by parts, each with a lesson, a generator of fresh problems with exact answers, and worked steps when you miss.",
      },
      {
        title: "A reading ladder",
        body: "112 books in ten tiers of real difficulty across seven genres. Your comfort tier comes from books you've finished. The next suggestion is one step up, in the genres you like.",
      },
    ],
    how: [
      { title: "The first session is the placement", body: "A vocabulary test from common words to rare, a maths placement that walks the skill graph in a dozen problems, one writing item per skill." },
      { title: "Two weeks of assessment", body: "Weekly notes say what was learned. Then the block starts." },
      { title: "25 minutes, five days", body: "Reviews, new material, practice. Spare time goes to reviews ahead of schedule." },
      { title: "Review weeks and check-ins", body: "Every sixth week, or whenever Stadig Lift deloads: nothing new, reading for pleasure, and a check-in that moves Intelligence and Wisdom." },
    ],
    free: "Reviews, the catalogs, export and backup are free. The one-time purchase unlocks sessions after the assessment.",
    keywords: ["spaced repetition app", "FSRS", "learn Japanese app", "maths practice app", "study planner", "reading ladder", "deliberate practice"],
  },
];

export const principles = [
  {
    title: "Prescribe, don't describe",
    body: "A chart tells you what happened. Stadig apps tell you what to do next. Every insight ends in one concrete action, and the plan is written for you, with a Why if you want it.",
  },
  {
    title: "Real-world tests, not in-app activity",
    body: "Strength moves on lifts, Endurance on benchmarks, Intelligence on check-in tests, Wisdom on finished books. Opening the app, logging, or time on task moves nothing.",
  },
  {
    title: "No XP, streaks or levels",
    body: "Discipline is a rolling four-week adherence rate with an 80 to 90 percent target band. Above it earns nothing extra, and one miss barely dents it. Rest is part of the plan. A day you didn't log is unknown, not a failure.",
  },
  {
    title: "Offline first",
    body: "The exercise library, the food and supplement catalogs and the Japanese dictionary ship inside the apps. They work on a plane and in a basement gym. iCloud sync is there for your own devices.",
  },
  {
    title: "Private by construction",
    body: "No account. No analytics. Your data lives on your devices and in your iCloud. Where an app uses a language model, it's Apple's on-device model, or Private Cloud Compute only when you allow it. Progress photos are never analysed.",
  },
  {
    title: "One purchase, no subscription",
    body: "Each app is a one-time unlock. Logging, export and backups are free forever, so your data is never held hostage.",
  },
  {
    title: "No third-party code",
    body: "Swift, SwiftUI, SwiftData and Apple's frameworks. No SDKs phoning home, no trackers, nothing to break when a vendor changes terms.",
  },
];

export const stats = [
  { name: "Strength", source: "Free-weight lifts scored against bodyweight-relative standards" },
  { name: "Physique", source: "Tape measurements and ratios" },
  { name: "Endurance", source: "Heart-rate benchmarks and recovery" },
  { name: "Vitality", source: "Sleep, HRV and resting heart rate from Health" },
  { name: "Agility", source: "Five mobility tests" },
  { name: "Discipline", source: "Four-week adherence, shared by every app" },
  { name: "Intelligence", source: "Check-in tests in Japanese, maths and writing" },
  { name: "Wisdom", source: "The highest reading tier finished comfortably" },
];

export const together = [
  {
    title: "Stadig Macro sets the phase. Stadig Lift builds around it.",
    body: "A cut shortens the block and reads stalls as expected. A bulk lengthens it. Stadig Lift waits with a neutral block while Stadig Macro is still deciding.",
  },
  {
    title: "Stadig Lift's deloads are Stadig Mind's review weeks.",
    body: "One calendar. When the body rests, the mind consolidates: nothing new, reviews ahead of schedule, reading for pleasure.",
  },
  {
    title: "Steps are judged with the diet in mind.",
    body: "Stadig Lift sets a daily step aim from your usual count, never a universal 10,000. When steps fall in a cut, Stadig Macro reads that before it cuts calories.",
  },
  {
    title: "Life modes are shared.",
    body: "Say you're on vacation, ill or in crunch once. Every app reflows: the block, the targets, the study plan. None of those days count against you.",
  },
];

export const faq = [
  {
    q: "What is Stadig?",
    a: "Stadig is three apps for training, nutrition and study on iPhone, iPad, Mac and Apple Vision Pro: Stadig Lift, Stadig Macro and Stadig Mind. They share one idea: use your own data to prescribe the next thing to do, instead of charting what you did. The name is Norwegian for steady.",
  },
  {
    q: "Do I need all three apps?",
    a: "No. Each app works alone. Together they share a profile, life modes and a calendar, so Stadig Macro's phase shapes Stadig Lift's block and Stadig Lift's deloads become Stadig Mind's review weeks.",
  },
  {
    q: "Is there a subscription?",
    a: "No. Each app is a one-time purchase. Logging, export and backups are free in every app, so you can use them as a plain tracker without paying and your data is never locked up.",
  },
  {
    q: "Do the apps work offline?",
    a: "Yes. The exercise library, the food and supplement catalogs and the Japanese dictionary ship inside the apps. Sync between your own devices uses iCloud when you're online.",
  },
  {
    q: "Where does my data go?",
    a: "Your devices and your private iCloud database. There is no account and no analytics. Stadig Macro's photo and label reading uses Apple's on-device model, and Apple's Private Cloud Compute only when you turn that on.",
  },
  {
    q: "What does \"prescribe, don't describe\" mean?",
    a: "A tracker describes: here is your volume, here is your calorie average. Stadig apps prescribe: add 2.5 kg to the next set, eat 150 kcal less this week, review these 12 words then learn 15 new ones. Every screen ends in an action.",
  },
  {
    q: "Why no streaks?",
    a: "Streaks reward showing up, not improving, and they punish the rest days a good plan contains. Discipline in Stadig apps is a four-week adherence rate with a target band, where one missed day barely registers and vacations and illness don't count at all.",
  },
  {
    q: "What devices are supported?",
    a: "All three run on iPhone, iPad, Mac and Apple Vision Pro, and one purchase covers every device. Stadig Lift and Stadig Macro also have Apple Watch apps. On the iPad and the Mac each does more than on the phone: Stadig Lift lays out your program and exercise library, Stadig Macro compares foods and plans the week, and Stadig Mind runs sessions from the keyboard. Your data syncs between your devices through iCloud.",
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
  { href: "/mind", label: "Stadig Mind" },
  { href: "/principles", label: "Principles" },
  { href: "/faq", label: "FAQ" },
];
