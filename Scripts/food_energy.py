"""Whether a food's calories agree with its macros, and which disagreements can be repaired.

Used by food_catalog.py, which repairs Open Food Facts rows and flags any source's as it reads them,
and by food_validation.py, which reports on a built catalog. Python standard library only.

Macros can't overrule calories on their own. When the two disagree either may be the mistake: a soy
sauce at 77 kcal with 3.2 g of carbs has the calories right and the carbs wrong, so recomputing
from the macros would break a good number. A row is repaired only when the mistake itself can be
named and the repaired value then agrees with the macros. Everything else is flagged and left alone.
"""
import re
import unicodedata

KJ_PER_KCAL = 4.184
# How far outside the macros' range calories may sit, as a share of it.
TOLERANCE = 0.10
# Labels round each macro, which swamps a percentage on foods of a few calories.
SLACK_KCAL = 5

OK, EXPLAINED, REPAIRED, SUSPECT = "ok", "explained", "repaired", "suspect"

# Energy that protein, carbs and fat don't count. Alcohol and sweetener words match Plausibility.swift.
ALCOHOL = set("""beer biere bier wine vin wein vodka whisky whiskey gin rum rhum tequila liqueur likor cider cidre
    sake brandy cognac champagne prosecco cava lager ale stout porter mead sherry vermouth schnapps bourbon scotch
    aperitif spritz cocktail mojito sangria alcohol alcool armagnac calvados grappa ouzo pastis absinthe martini
    baileys amaretto limoncello extract alcoholic""".split())
# Sugar alcohols and sweeteners count as carbs but bring few calories.
SWEETENER = set("""stevia erythritol xylitol sweetener sweeteners edulcorant sucralose aspartame polyol polyols
    maltitol sorbitol isomalt sukrin monkfruit truvia splenda canderel eritritol""".split())
# Organic acids have energy and aren't always counted as carbs.
ACID = set("vinegar vinaigre vinagre aceto essig balsamic balsamique citron lemon lime limon".split())


def macro_range(protein, carbs, fat, fiber):
    """
    The least and most calories the macros can make at 4, 4 and 9 kcal per gram. US labels count
    fibre within carbs and EU labels beside them at 2 kcal per gram, and a row doesn't say which.
    """
    protein, carbs, fat, fiber = (max(0, value or 0) for value in (protein, carbs, fat, fiber))
    return 4 * protein + 4 * max(0, carbs - fiber) + 9 * fat, 4 * protein + 4 * carbs + 9 * fat + 2 * fiber


def agrees(kcal, least, most, tolerance=TOLERANCE):
    return least * (1 - tolerance) - SLACK_KCAL <= kcal <= most * (1 + tolerance) + SLACK_KCAL


def explanation(name):
    """Why a food's calories needn't match its macros, from words in its name."""
    plain = unicodedata.normalize("NFKD", (name or "").lower())
    words = set(re.findall(r"[^\W\d_]+", "".join(c for c in plain if not unicodedata.combining(c))))
    if words & ALCOHOL:
        return "alcohol"
    if words & SWEETENER:
        return "sweetener"
    if words & ACID:
        return "acid"
    return None


def assess(kcal, protein, carbs, fat, fiber=None, name="", kj=None, serving=None, tolerance=TOLERANCE):
    """
    What to make of a row's calories, per 100 g or ml, as (verdict, kcal, reason). `kj` is the energy
    in kilojoules as entered from the label, never one worked out from the macros, which would only
    be the macros again; `serving` is the grams or ml in a serving, where known.
    """
    least, most = macro_range(protein, carbs, fat, fiber)
    if agrees(kcal, least, most, tolerance):
        return OK, kcal, None
    reason = explanation(name)
    if reason:
        return EXPLAINED, kcal, reason
    # The label's other energy figure agrees, so this one was mistyped or misread.
    if kj is not None and kj > 0 and agrees(kj / KJ_PER_KCAL, least, most, tolerance):
        return REPAIRED, kj / KJ_PER_KCAL, "labelKj"
    # Below a few calories every food looks like these two; the macros have to make a real amount.
    if most >= 20:
        if kcal > 0 and agrees(kcal / KJ_PER_KCAL, least, most, tolerance):
            return REPAIRED, kcal / KJ_PER_KCAL, "kjAsKcal"
        # Only servings well under 100: near it a mix-up can't be told from a loose label, and over
        # it the rows that fit are mostly canned beers and cocktails with no alcohol word in the name.
        if serving and serving <= 80 and agrees(kcal * 100 / serving, least, most, tolerance):
            return REPAIRED, kcal * 100 / serving, "perServing"
    return SUSPECT, kcal, "zero" if kcal <= 0 else "tooLow" if kcal < least else "tooHigh"
