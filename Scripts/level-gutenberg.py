#!/usr/bin/env python3
"""Levels public-domain classics from their Project Gutenberg text, for Stadig Mind's reading ladder.

    python3 -I Scripts/level-gutenberg.py            # download what's missing, measure, fit, write
    python3 -I Scripts/level-gutenberg.py --offline  # measure and fit what's already downloaded

Each book is found in Gutenberg's own catalogue (pg_catalog.csv) by title and author, and its plain
text downloaded once from a Gutenberg mirror into Scripts/.gutenberg/ (which ignores itself, so
nothing downloaded reaches git), a second apart. Then, from the middle of each text:

- readability: words a sentence and syllables a word (the parts of Flesch-Kincaid),
- vocabulary rarity: the share of words that fewer than a third of these books use at all,
  proper names left out,
- sentence complexity: commas, semicolons, colons and dashes a sentence,
- vocabulary range: distinct words in each run of 500 (a moving type-token ratio),

plus whether the book argues (philosophy, science, essays) or tells a story, and its age. A ridge
regression fits those to the hand tiers of the books that are also on the ladder (the
anchors). Each anchor's own tier is predicted with it left out, so the written file shows honestly
how close the fit comes; every other book gets the full fit's tier. Only the derived levels are
written: Packages/MindEngine/Sources/MindEngine/Resources/gutenberg-levels.json.
"""

import csv
import json
import math
import re
import sys
import time
import unicodedata
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "Scripts" / ".gutenberg"
LADDER = ROOT / "Packages/MindEngine/Sources/MindEngine/Resources/ladder.json"
OUT = ROOT / "Packages/MindEngine/Sources/MindEngine/Resources/gutenberg-levels.json"
MIRRORS = ["https://gutenberg.pglaf.org/cache/epub/{id}/pg{id}.txt", "https://www.gutenberg.org/cache/epub/{id}/pg{id}.txt"]
AGENT = "MindTrack reading-ladder levelling (one-off, rate limited)"

# Books on the hand ladder that are in the public domain: the fit's anchors. (ladder id, catalogue
# title to search for, author surname, Gutenberg number when the catalogue has several).
ANCHORS = [
    ("the-murder-of-roger-ackroyd", "The Murder of Roger Ackroyd", "Christie", None),
    ("the-count-of-monte-cristo", "The Count of Monte Cristo", "Dumas", 1184),
    ("meditations", "Meditations", "Marcus Aurelius", 2680),
    ("the-great-gatsby", "The Great Gatsby", "Fitzgerald", 64317),
    ("dracula", "Dracula", "Stoker", 345),
    ("the-problems-of-philosophy", "The Problems of Philosophy", "Russell", 5827),
    ("frankenstein", "Frankenstein", "Shelley", 84),
    ("pride-and-prejudice", "Pride and Prejudice", "Austen", 1342),
    ("jane-eyre", "Jane Eyre", "Bront", 1260),
    ("anna-karenina", "Anna Karenina", "Tolstoy", 1399),
    ("the-trial", "The Trial", "Kafka", 7849),
    ("crime-and-punishment", "Crime and Punishment", "Dostoyevsky", 2554),
    ("wuthering-heights", "Wuthering Heights", "Bront", 768),
    ("the-republic", "The Republic", "Plato", 1497),
    ("walden", "Walden", "Thoreau", 205),
    ("the-brothers-karamazov", "The Brothers Karamazov", "Dostoyevsky", 28054),
    ("middlemarch", "Middlemarch", "Eliot", 145),
    ("mrs-dalloway", "Mrs. Dalloway", "Woolf", 71865),
    ("beyond-good-and-evil", "Beyond Good and Evil", "Nietzsche", 4363),
    ("an-enquiry-concerning-human-understanding", "An Enquiry Concerning Human Understanding", "Hume", 9662),
    ("on-the-origin-of-species", "On the Origin of Species", "Darwin", 1228),
    ("moby-dick", "Moby Dick", "Melville", 2701),
    ("thus-spoke-zarathustra", "Thus Spake Zarathustra", "Nietzsche", 1998),
    ("leviathan", "Leviathan", "Hobbes", 3207),
    ("the-worm-ouroboros", "The Worm Ouroboros", "Eddison", None),
    ("swanns-way", "Swann's Way", "Proust", 7178),
    ("prolegomena-to-any-future-metaphysics", "Prolegomena to Any Future Metaphysics", "Kant", 52821),
    ("the-sound-and-the-fury", "The Sound and the Fury", "Faulkner", None),
    ("ulysses", "Ulysses", "Joyce", 4300),
    ("critique-of-pure-reason", "The Critique of Pure Reason", "Kant", 4280),
    ("the-prophet", "The Prophet", "Gibran", None),
    ("siddhartha", "Siddhartha", "Hesse", 2500),
    ("the-art-of-war", "The Art of War", "Sunzi", 132),
    ("we", "We", "Zamiatin", 61963),
    ("a-passage-to-india", "A Passage to India", "Forster", None),
    ("the-age-of-innocence", "The Age of Innocence", "Wharton", 541),
    ("lud-in-the-mist", "Lud-in-the-Mist", "Mirrlees", None),
    ("the-king-of-elflands-daughter", "The King of Elfland's Daughter", "Dunsany", None),
    ("notes-from-underground", "Notes from the Underground", "Dostoyevsky", 600),
    ("candide", "Candide", "Voltaire", 19942),
    ("nicomachean-ethics", "The Nicomachean ethics of Aristotle", "Aristotle", 8438),
    ("the-maltese-falcon", "The Maltese Falcon", "Hammett", None),
    ("the-world-as-will-and-representation", "The World as Will and Idea", "Schopenhauer", 38427),
    ("ethics-spinoza", "Ethics", "Spinoza", 3800),
    ("last-and-first-men", "Last and First Men", "Stapledon", None),
]

# Classics levelled only from their text: (id, title to search for, author as shown, surname, year,
# genres, Gutenberg number when the catalogue has several).
CLASSICS = [
    ("emma", "Emma", "Jane Austen", "Austen", 1815, ["classics"], 158),
    ("sense-and-sensibility", "Sense and Sensibility", "Jane Austen", "Austen", 1811, ["classics"], 161),
    ("persuasion", "Persuasion", "Jane Austen", "Austen", 1817, ["classics"], 105),
    ("northanger-abbey", "Northanger Abbey", "Jane Austen", "Austen", 1817, ["classics"], 121),
    ("mansfield-park", "Mansfield Park", "Jane Austen", "Austen", 1814, ["classics"], 141),
    ("great-expectations", "Great Expectations", "Charles Dickens", "Dickens", 1861, ["classics"], 1400),
    ("a-tale-of-two-cities", "A Tale of Two Cities", "Charles Dickens", "Dickens", 1859, ["classics"], 98),
    ("bleak-house", "Bleak House", "Charles Dickens", "Dickens", 1853, ["classics", "crime"], 1023),
    ("oliver-twist", "Oliver Twist", "Charles Dickens", "Dickens", 1838, ["classics"], 730),
    ("david-copperfield", "David Copperfield", "Charles Dickens", "Dickens", 1850, ["classics"], 766),
    ("a-christmas-carol", "A Christmas Carol", "Charles Dickens", "Dickens", 1843, ["classics", "fantasy"], 46),
    ("hard-times", "Hard Times", "Charles Dickens", "Dickens", 1854, ["classics"], 786),
    ("villette", "Villette", "Charlotte Brontë", "Bront", 1853, ["classics"], 9182),
    ("agnes-grey", "Agnes Grey", "Anne Brontë", "Bront", 1847, ["classics"], 767),
    ("the-tenant-of-wildfell-hall", "The Tenant of Wildfell Hall", "Anne Brontë", "Bront", 1848, ["classics"], 969),
    ("silas-marner", "Silas Marner", "George Eliot", "Eliot", 1861, ["classics"], 550),
    ("the-mill-on-the-floss", "The Mill on the Floss", "George Eliot", "Eliot", 1860, ["classics"], 6688),
    ("tess-of-the-durbervilles", "Tess of the d'Urbervilles", "Thomas Hardy", "Hardy", 1891, ["classics"], 110),
    ("far-from-the-madding-crowd", "Far from the Madding Crowd", "Thomas Hardy", "Hardy", 1874, ["classics"], 107),
    ("jude-the-obscure", "Jude the Obscure", "Thomas Hardy", "Hardy", 1895, ["classics"], 153),
    ("the-mayor-of-casterbridge", "The Mayor of Casterbridge", "Thomas Hardy", "Hardy", 1886, ["classics"], 143),
    ("adventures-of-huckleberry-finn", "Adventures of Huckleberry Finn", "Mark Twain", "Twain", 1884, ["classics"], 76),
    ("the-adventures-of-tom-sawyer", "The Adventures of Tom Sawyer", "Mark Twain", "Twain", 1876, ["classics"], 74),
    ("treasure-island", "Treasure Island", "Robert Louis Stevenson", "Stevenson", 1883, ["classics"], 120),
    ("strange-case-of-dr-jekyll-and-mr-hyde", "Jekyll and Mr. Hyde", "Robert Louis Stevenson", "Stevenson", 1886, ["classics", "crime"], 43),
    ("kidnapped", "Kidnapped", "Robert Louis Stevenson", "Stevenson", 1886, ["classics"], 421),
    ("the-time-machine", "The Time Machine", "H. G. Wells", "Wells", 1895, ["sciFi", "classics"], 35),
    ("the-war-of-the-worlds", "The War of the Worlds", "H. G. Wells", "Wells", 1898, ["sciFi", "classics"], 36),
    ("the-invisible-man", "The Invisible Man", "H. G. Wells", "Wells", 1897, ["sciFi", "classics"], 5230),
    ("the-island-of-doctor-moreau", "The Island of Doctor Moreau", "H. G. Wells", "Wells", 1896, ["sciFi", "classics"], 159),
    ("twenty-thousand-leagues-under-the-sea", "Twenty Thousand Leagues under the Sea", "Jules Verne", "Verne", 1870, ["sciFi", "classics"], 164),
    ("around-the-world-in-eighty-days", "Around the World in Eighty Days", "Jules Verne", "Verne", 1872, ["classics"], 103),
    ("journey-to-the-centre-of-the-earth", "Journey to the Centre of the Earth", "Jules Verne", "Verne", 1864, ["sciFi", "classics"], 18857),
    ("the-hound-of-the-baskervilles", "The Hound of the Baskervilles", "Arthur Conan Doyle", "Doyle", 1902, ["crime", "classics"], 2852),
    ("a-study-in-scarlet", "A Study in Scarlet", "Arthur Conan Doyle", "Doyle", 1887, ["crime", "classics"], 244),
    ("the-adventures-of-sherlock-holmes", "The Adventures of Sherlock Holmes", "Arthur Conan Doyle", "Doyle", 1892, ["crime", "classics"], 1661),
    ("the-lost-world", "The Lost World", "Arthur Conan Doyle", "Doyle", 1912, ["sciFi"], 139),
    ("the-picture-of-dorian-gray", "The Picture of Dorian Gray", "Oscar Wilde", "Wilde", 1890, ["classics", "fantasy"], 174),
    ("heart-of-darkness", "Heart of Darkness", "Joseph Conrad", "Conrad", 1899, ["classics"], 219),
    ("lord-jim", "Lord Jim", "Joseph Conrad", "Conrad", 1900, ["classics"], 5658),
    ("the-secret-agent", "The Secret Agent", "Joseph Conrad", "Conrad", 1907, ["classics", "crime"], 974),
    ("nostromo", "Nostromo", "Joseph Conrad", "Conrad", 1904, ["classics"], 2021),
    ("the-turn-of-the-screw", "The Turn of the Screw", "Henry James", "James", 1898, ["classics", "fantasy"], 209),
    ("the-portrait-of-a-lady", "The Portrait of a Lady", "Henry James", "James", 1881, ["classics"], None),
    ("the-ambassadors", "The Ambassadors", "Henry James", "James", 1903, ["classics"], 432),
    ("washington-square", "Washington Square", "Henry James", "James", 1880, ["classics"], 2870),
    ("the-golden-bowl", "The Golden Bowl", "Henry James", "James", 1904, ["classics"], None),
    ("the-house-of-mirth", "The House of Mirth", "Edith Wharton", "Wharton", 1905, ["classics"], 284),
    ("ethan-frome", "Ethan Frome", "Edith Wharton", "Wharton", 1911, ["classics"], 4517),
    ("billy-budd", "Billy Budd", "Herman Melville", "Melville", 1924, ["classics"], None),
    ("the-scarlet-letter", "The Scarlet Letter", "Nathaniel Hawthorne", "Hawthorne", 1850, ["classics"], 25344),
    ("the-house-of-the-seven-gables", "The House of the Seven Gables", "Nathaniel Hawthorne", "Hawthorne", 1851, ["classics"], 77),
    ("war-and-peace", "War and Peace", "Leo Tolstoy", "Tolstoy", 1869, ["classics"], 2600),
    ("the-idiot", "The Idiot", "Fyodor Dostoevsky", "Dostoyevsky", 1869, ["classics"], 2638),
    ("fathers-and-sons", "Fathers and Sons", "Ivan Turgenev", "Turgenev", 1862, ["classics"], None),
    ("dead-souls", "Dead Souls", "Nikolai Gogol", "Gogol", 1842, ["classics"], 1081),
    ("madame-bovary", "Madame Bovary", "Gustave Flaubert", "Flaubert", 1857, ["classics"], 2413),
    ("les-miserables", "Les Misérables", "Victor Hugo", "Hugo", 1862, ["classics"], 135),
    ("don-quixote", "Don Quixote", "Miguel de Cervantes", "Cervantes", 1605, ["classics"], 996),
    ("gullivers-travels", "Gulliver's Travels", "Jonathan Swift", "Swift", 1726, ["classics", "fantasy"], 829),
    ("robinson-crusoe", "Robinson Crusoe", "Daniel Defoe", "Defoe", 1719, ["classics"], 521),
    ("tom-jones", "Tom Jones", "Henry Fielding", "Fielding", 1749, ["classics"], 6593),
    ("tristram-shandy", "Tristram Shandy", "Laurence Sterne", "Sterne", 1759, ["classics", "literary"], 1079),
    ("vanity-fair", "Vanity Fair", "William Makepeace Thackeray", "Thackeray", 1848, ["classics"], 599),
    ("north-and-south", "North and South", "Elizabeth Gaskell", "Gaskell", 1855, ["classics"], 4276),
    ("jacobs-room", "Jacob's Room", "Virginia Woolf", "Woolf", 1922, ["classics", "literary"], 5670),
    ("dubliners", "Dubliners", "James Joyce", "Joyce", 1914, ["classics", "literary"], 2814),
    ("a-portrait-of-the-artist-as-a-young-man", "A Portrait of the Artist as a Young Man", "James Joyce", "Joyce", 1916, ["classics", "literary"], 4217),
    ("sons-and-lovers", "Sons and Lovers", "D. H. Lawrence", "Lawrence", 1913, ["classics"], 217),
    ("women-in-love", "Women in Love", "D. H. Lawrence", "Lawrence", 1920, ["classics"], 4240),
    ("a-room-with-a-view", "A Room with a View", "E. M. Forster", "Forster", 1908, ["classics"], 2641),
    ("howards-end", "Howards End", "E. M. Forster", "Forster", 1910, ["classics"], 2946),
    ("the-metamorphosis", "Metamorphosis", "Franz Kafka", "Kafka", 1915, ["classics", "fantasy"], 5200),
    ("this-side-of-paradise", "This Side of Paradise", "F. Scott Fitzgerald", "Fitzgerald", 1920, ["classics"], 805),
    ("the-sun-also-rises", "The Sun Also Rises", "Ernest Hemingway", "Hemingway", 1926, ["classics"], None),
    ("main-street", "Main Street", "Sinclair Lewis", "Lewis", 1920, ["classics"], 543),
    ("babbitt", "Babbitt", "Sinclair Lewis", "Lewis", 1922, ["classics"], 1156),
    ("the-awakening", "The Awakening", "Kate Chopin", "Chopin", 1899, ["classics"], 160),
    ("the-call-of-the-wild", "The Call of the Wild", "Jack London", "London", 1903, ["classics"], 215),
    ("white-fang", "White Fang", "Jack London", "London", 1906, ["classics"], 910),
    ("martin-eden", "Martin Eden", "Jack London", "London", 1909, ["classics"], 1056),
    ("a-princess-of-mars", "A Princess of Mars", "Edgar Rice Burroughs", "Burroughs", 1912, ["sciFi", "fantasy"], 62),
    ("tarzan-of-the-apes", "Tarzan of the Apes", "Edgar Rice Burroughs", "Burroughs", 1912, ["classics"], 78),
    ("the-wonderful-wizard-of-oz", "The Wonderful Wizard of Oz", "L. Frank Baum", "Baum", 1900, ["fantasy", "classics"], 55),
    ("alices-adventures-in-wonderland", "Alice's Adventures in Wonderland", "Lewis Carroll", "Carroll", 1865, ["fantasy", "classics"], 11),
    ("kim", "Kim", "Rudyard Kipling", "Kipling", 1901, ["classics"], 2226),
    ("the-thirty-nine-steps", "The Thirty-Nine Steps", "John Buchan", "Buchan", 1915, ["crime"], 558),
    ("the-mysterious-affair-at-styles", "The Mysterious Affair at Styles", "Agatha Christie", "Christie", 1920, ["crime"], 863),
    ("the-secret-adversary", "The Secret Adversary", "Agatha Christie", "Christie", 1922, ["crime"], 1155),
    ("the-man-who-was-thursday", "The Man Who Was Thursday", "G. K. Chesterton", "Chesterton", 1908, ["crime", "philosophy"], 1695),
    ("the-innocence-of-father-brown", "The Innocence of Father Brown", "G. K. Chesterton", "Chesterton", 1911, ["crime"], 204),
    ("the-moonstone", "The Moonstone", "Wilkie Collins", "Collins", 1868, ["crime", "classics"], 155),
    ("the-woman-in-white", "The Woman in White", "Wilkie Collins", "Collins", 1859, ["crime", "classics"], 583),
    ("carmilla", "Carmilla", "J. Sheridan Le Fanu", "Le Fanu", 1872, ["fantasy", "classics"], 10007),
    ("the-phantom-of-the-opera", "The Phantom of the Opera", "Gaston Leroux", "Leroux", 1910, ["classics", "crime"], 175),
    ("the-prisoner-of-zenda", "The Prisoner of Zenda", "Anthony Hope", "Hope", 1894, ["classics"], 95),
    ("the-scarlet-pimpernel", "The Scarlet Pimpernel", "Baroness Orczy", "Orczy", 1905, ["classics"], 60),
    ("herland", "Herland", "Charlotte Perkins Gilman", "Gilman", 1915, ["sciFi"], 32),
    ("flatland", "Flatland", "Edwin A. Abbott", "Abbott", 1884, ["sciFi", "philosophy"], 201),
    ("erewhon", "Erewhon", "Samuel Butler", "Butler", 1872, ["sciFi"], 1906),
    ("looking-backward", "Looking Backward", "Edward Bellamy", "Bellamy", 1888, ["sciFi"], 624),
    ("uncle-toms-cabin", "Uncle Tom's Cabin", "Harriet Beecher Stowe", "Stowe", 1852, ["classics"], 203),
    ("little-women", "Little Women", "Louisa May Alcott", "Alcott", 1868, ["classics"], 514),
    ("anne-of-green-gables", "Anne of Green Gables", "L. M. Montgomery", "Montgomery", 1908, ["classics"], 45),
    ("the-sorrows-of-young-werther", "The Sorrows of Young Werther", "Johann Wolfgang von Goethe", "Goethe", 1774, ["classics"], 2527),
    ("the-prince", "The Prince", "Niccolò Machiavelli", "Machiavelli", 1532, ["philosophy", "classics"], 1232),
    ("on-liberty", "On Liberty", "John Stuart Mill", "Mill", 1859, ["philosophy"], 34901),
    ("utilitarianism", "Utilitarianism", "John Stuart Mill", "Mill", 1863, ["philosophy"], 11224),
    ("second-treatise-of-government", "Second Treatise of Government", "John Locke", "Locke", 1689, ["philosophy"], 7370),
    ("the-social-contract", "The Social Contract", "Jean-Jacques Rousseau", "Rousseau", 1762, ["philosophy"], 46333),
    ("discourse-on-the-method", "Discourse on the Method", "René Descartes", "Descartes", 1637, ["philosophy"], 59),
    ("pensees", "Pascal's Pensées", "Blaise Pascal", "Pascal", 1670, ["philosophy"], 18269),
    ("groundwork-of-the-metaphysics-of-morals", "Fundamental Principles of the Metaphysic of Morals", "Immanuel Kant", "Kant", 1785, ["philosophy"], 5682),
    ("on-the-genealogy-of-morals", "The Genealogy of Morals", "Friedrich Nietzsche", "Nietzsche", 1887, ["philosophy"], 52319),
    ("pragmatism", "Pragmatism", "William James", "James", 1907, ["philosophy"], 5116),
    ("the-varieties-of-religious-experience", "The Varieties of Religious Experience", "William James", "James", 1902, ["philosophy", "nonfiction"], 621),
    ("essays-first-series", "Essays — First Series", "Ralph Waldo Emerson", "Emerson", 1841, ["philosophy"], 2944),
    ("essays-of-montaigne", "Essays of Michel de Montaigne", "Michel de Montaigne", "Montaigne", 1580, ["philosophy", "classics"], 3600),
    ("essays-of-francis-bacon", "The Essays or Counsels, Civil and Moral", "Francis Bacon", "Bacon", 1625, ["philosophy"], 575),
    ("the-enchiridion", "The Enchiridion", "Epictetus", "Epictetus", 125, ["philosophy"], 45109),
    ("apology", "Apology", "Plato", "Plato", -399, ["philosophy", "classics"], 1656),
    ("symposium", "Symposium", "Plato", "Plato", -385, ["philosophy", "classics"], 1600),
    ("the-consolation-of-philosophy", "The Consolation of Philosophy", "Boethius", "Boethius", 524, ["philosophy", "classics"], 14328),
    ("utopia", "Utopia", "Thomas More", "More", 1516, ["philosophy", "classics"], 2130),
    ("an-essay-concerning-human-understanding", "An Essay Concerning Humane Understanding", "John Locke", "Locke", 1689, ["philosophy"], 10615),
    ("a-treatise-of-human-nature", "A Treatise of Human Nature", "David Hume", "Hume", 1739, ["philosophy"], 4705),
    ("the-wealth-of-nations", "Wealth of Nations", "Adam Smith", "Smith", 1776, ["nonfiction"], 3300),
    ("the-decline-and-fall-of-the-roman-empire", "History of the Decline and Fall of the Roman Empire", "Edward Gibbon", "Gibbon", 1776, ["nonfiction"], 731),
    ("rights-of-man", "Rights of Man", "Thomas Paine", "Paine", 1791, ["philosophy"], 3742),
    ("a-vindication-of-the-rights-of-woman", "A Vindication of the Rights of Woman", "Mary Wollstonecraft", "Wollstonecraft", 1792, ["philosophy"], 3420),
    ("the-voyage-of-the-beagle", "The Voyage of the Beagle", "Charles Darwin", "Darwin", 1839, ["nonfiction"], 944),
    ("the-descent-of-man", "The Descent of Man", "Charles Darwin", "Darwin", 1871, ["nonfiction"], 2300),
    ("the-autobiography-of-benjamin-franklin", "Autobiography of Benjamin Franklin", "Benjamin Franklin", "Franklin", 1791, ["nonfiction"], 20203),
    ("narrative-of-the-life-of-frederick-douglass", "Narrative of the Life of Frederick Douglass", "Frederick Douglass", "Douglass", 1845, ["nonfiction"], 23),
    ("the-souls-of-black-folk", "The Souls of Black Folk", "W. E. B. Du Bois", "Du Bois", 1903, ["nonfiction"], 408),
    ("up-from-slavery", "Up from Slavery", "Booker T. Washington", "Washington", 1901, ["nonfiction"], 2376),
    ("life-on-the-mississippi", "Life on the Mississippi", "Mark Twain", "Twain", 1883, ["nonfiction"], 245),
    ("the-interpretation-of-dreams", "Dream Psychology", "Sigmund Freud", "Freud", 1899, ["nonfiction"], None),
    ("the-theory-of-the-leisure-class", "The Theory of the Leisure Class", "Thorstein Veblen", "Veblen", 1899, ["nonfiction"], 833),
    ("the-education-of-henry-adams", "The Education of Henry Adams", "Henry Adams", "Adams", 1907, ["nonfiction"], 2044),
    ("eminent-victorians", "Eminent Victorians", "Lytton Strachey", "Strachey", 1918, ["nonfiction"], 2447),
    ("orthodoxy", "Orthodoxy", "G. K. Chesterton", "Chesterton", 1908, ["philosophy"], 130),
    ("relativity", "Relativity: The Special and General Theory", "Albert Einstein", "Einstein", 1916, ["nonfiction"], 30155),
    ("the-chemical-history-of-a-candle", "The Chemical History of a Candle", "Michael Faraday", "Faraday", 1861, ["nonfiction"], 14474),
    ("democracy-in-america", "Democracy in America", "Alexis de Tocqueville", "Tocqueville", 1835, ["nonfiction"], 815),
    ("the-analysis-of-mind", "The Analysis of Mind", "Bertrand Russell", "Russell", 1921, ["philosophy"], 2529),
    ("principia-ethica", "Principia Ethica", "G. E. Moore", "Moore", 1903, ["philosophy"], 53430),
    ("democracy-and-education", "Democracy and Education", "John Dewey", "Dewey", 1916, ["philosophy"], 852),
    ("the-communist-manifesto", "The Communist Manifesto", "Karl Marx", "Marx", 1848, ["philosophy"], 61),
]

# The fitted features, in order.
FEATURES = ["log sentence words", "syllables a word", "rare words", "log clauses", "word range", "expository", "log age"]


def download(number):
    path = CACHE / f"{number}.txt"
    if path.exists():
        return path
    for mirror in MIRRORS:
        url = mirror.format(id=number)
        try:
            request = urllib.request.Request(url, headers={"User-Agent": AGENT})
            with urllib.request.urlopen(request, timeout=60) as response:
                data = response.read()
            path.write_bytes(data)
            time.sleep(1)
            return path
        except Exception as error:  # Try the next mirror.
            print(f"  {url}: {error}", file=sys.stderr)
            time.sleep(1)
    return None


def fold(text):
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", text).strip()


def catalogue():
    rows = []
    with open(CACHE / "pg_catalog.csv", newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            if row["Type"] == "Text" and "en" in row["Language"].split("; "):
                rows.append((int(row["Text#"]), row["Title"], row["Authors"]))
    return rows


def find(rows, title, surname, number):
    """The Gutenberg number: the given one, or the lowest-numbered English text whose title starts
    with the search and whose authors include the surname."""
    wanted, who = fold(title), fold(surname)
    if number:
        row = next((row for row in rows if row[0] == number), None)
        if row and wanted in fold(row[1]) and who in fold(row[2]):
            return row
        print(f"! #{number} is {row[1].splitlines()[0] if row else 'missing'}, not {title}; searching instead", file=sys.stderr)
    def main(row):
        return fold(re.split(r"[:;\n]", row[1])[0])
    matches = [row for row in rows if main(row) == wanted and who in fold(row[2])]
    return min(matches) if matches else None


def body(raw):
    """The book without Gutenberg's header and licence, and without its first and last tenth
    (prefaces, contents, notes and indexes)."""
    text = raw.decode("utf-8", errors="replace").replace("\r\n", "\n")
    start = re.search(r"\*\*\* ?START OF (THE|THIS) PROJECT GUTENBERG EBOOK.*?\*\*\*", text, re.I)
    end = re.search(r"\*\*\* ?END OF (THE|THIS) PROJECT GUTENBERG EBOOK", text, re.I)
    text = text[start.end() if start else 0:end.start() if end else len(text)]
    total = len(text.split())
    paragraphs = [" ".join(p.split()) for p in re.split(r"\n\s*\n", text)]
    # Prose only: headings, contents lines and verse fragments are short or shouting.
    paragraphs = [p for p in paragraphs if len(p.split()) >= 12 and not p.isupper() and not re.match(r"^(CHAPTER|BOOK|PART)\b", p)]
    cut = len(paragraphs) // 10
    return (paragraphs[cut:len(paragraphs) - cut] if len(paragraphs) > 20 else paragraphs), total


ABBREVIATIONS = re.compile(r"\b(Mr|Mrs|Ms|Dr|St|Mt|Jr|Sr|Prof|Rev|Gen|Col|Capt|Lt|Sgt|vol|ch|viz|cf|etc|i\.e|e\.g|vs|No)\.", re.I)
SENTENCE_END = re.compile(r"(?<=[.!?])[\"'’”)\]]*\s+(?=[\"'“‘(\[]?[A-Z0-9])")
WORD = re.compile(r"[A-Za-z]+(?:['’][A-Za-z]+)*")


def syllables(word):
    word = word.lower().replace("’", "'")
    if len(word) <= 3:
        return 1
    word = re.sub(r"(?:es|ed|e)$", "", word) or word
    groups = re.findall(r"[aeiouy]+", word)
    return max(1, len(groups))


def measure(paragraphs):
    sentences, tokens, clause_marks, capitals = [], [], 0, {}
    for paragraph in paragraphs:
        protected = ABBREVIATIONS.sub(lambda m: m.group(0).replace(".", "§"), paragraph)
        for sentence in SENTENCE_END.split(protected):
            words = WORD.findall(sentence)
            if not words:
                continue
            sentences.append(min(len(words), 250))
            clause_marks += len(re.findall(r"[,;:]|—|--| - ", sentence))
            for index, word in enumerate(words):
                lower = word.lower()
                tokens.append(lower)
                if index > 0:
                    upper, total = capitals.get(lower, (0, 0))
                    capitals[lower] = (upper + (word[0].isupper()), total + 1)
        if len(tokens) > 250_000:
            break
    proper = {w for w, (upper, total) in capitals.items() if total >= 2 and upper / total > 0.7}
    window = 500
    ranges = [len(set(tokens[i:i + window])) / window for i in range(0, max(1, len(tokens) - window), window)]
    return {
        "sentences": sentences,
        "tokens": tokens,
        "proper": proper,
        "sentence_words": sum(sentences) / max(1, len(sentences)),
        "syllables": sum(syllables(t) for t in tokens) / max(1, len(tokens)),
        "clauses": clause_marks / max(1, len(sentences)),
        "range": sum(ranges) / max(1, len(ranges)),
    }


def solve(matrix, vector):
    """Gaussian elimination for the small normal equations."""
    n = len(vector)
    a = [row[:] + [vector[i]] for i, row in enumerate(matrix)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(a[r][col]))
        a[col], a[pivot] = a[pivot], a[col]
        for row in range(n):
            if row != col and a[col][col]:
                factor = a[row][col] / a[col][col]
                a[row] = [x - factor * y for x, y in zip(a[row], a[col])]
    return [a[i][n] / a[i][i] for i in range(n)]


def ridge(xs, ys, penalty):
    n = len(xs[0])
    xtx = [[sum(x[i] * x[j] for x in xs) + (penalty if i == j and i > 0 else 0) for j in range(n)] for i in range(n)]
    xty = [sum(x[i] * y for x, y in zip(xs, ys)) for i in range(n)]
    return solve(xtx, xty)


def main():
    offline = "--offline" in sys.argv
    CACHE.mkdir(parents=True, exist_ok=True)
    (CACHE / ".gitignore").write_text("*\n")
    if not (CACHE / "pg_catalog.csv").exists():
        if offline:
            sys.exit("No catalogue downloaded yet.")
        url = "https://gutenberg.pglaf.org/cache/epub/feeds/pg_catalog.csv"
        request = urllib.request.Request(url, headers={"User-Agent": AGENT})
        with urllib.request.urlopen(request, timeout=120) as response:
            (CACHE / "pg_catalog.csv").write_bytes(response.read())
    rows = catalogue()
    ladder = {b["id"]: b for b in json.loads(LADDER.read_text())["books"]}

    books = []
    for ladder_id, title, surname, number in ANCHORS:
        book = ladder.get(ladder_id)
        if not book:
            print(f"! {ladder_id} isn't on the ladder", file=sys.stderr)
            continue
        books.append({"id": ladder_id, "search": title, "surname": surname, "number": number, "title": book["title"],
                      "author": book["author"], "year": book["year"], "pages": book["pages"], "genres": book["genres"],
                      "handTier": book["tier"]})
    for slug, title, author, surname, year, genres, number in CLASSICS:
        if slug in ladder:
            print(f"! {slug} is on the hand ladder; list it as an anchor", file=sys.stderr)
            continue
        books.append({"id": slug, "search": title, "surname": surname, "number": number, "title": title.replace("—", "-"),
                      "author": author, "year": year, "pages": None, "genres": genres, "handTier": None})

    measured = []
    for book in books:
        row = find(rows, book["search"], book["surname"], book["number"])
        if not row:
            print(f"- not in the catalogue: {book['title']} ({book['surname']})", file=sys.stderr)
            continue
        path = CACHE / f"{row[0]}.txt" if offline else download(row[0])
        if not path or not path.exists():
            print(f"- not downloaded: {book['title']} #{row[0]}", file=sys.stderr)
            continue
        paragraphs, book["totalWords"] = body(path.read_bytes())
        if sum(len(p.split()) for p in paragraphs) < 8000:
            print(f"- too little prose: {book['title']} #{row[0]}", file=sys.stderr)
            continue
        book["gutenberg"] = row[0]
        book["catalogueTitle"] = row[1].split("\n")[0]
        book["metrics"] = measure(paragraphs)
        measured.append(book)
        print(f"  #{row[0]:>6} {book['title'][:44]:<44} {book['catalogueTitle'][:40]}")

    # Rarity against these books themselves: a word fewer than a third of them use is rare.
    document_frequency = {}
    for book in measured:
        for word in set(book["metrics"]["tokens"]):
            document_frequency[word] = document_frequency.get(word, 0) + 1
    common = len(measured) / 3
    for book in measured:
        m = book["metrics"]
        words = [t for t in m["tokens"] if t not in m["proper"] and "'" not in t and "’" not in t]
        m["rare"] = sum(1 for t in words if document_frequency.get(t, 0) < common) / max(1, len(words))
        m["words"] = len(m["tokens"])
        # What the text measures can't see: argument asks more than story at the same prose, and
        # older English more than newer. The fit learns how much from the anchors.
        expository = 1.0 if {"philosophy", "nonfiction"} & set(book["genres"]) and "classics" not in book["genres"][:1] else 0.0
        book["features"] = [math.log(m["sentence_words"]), m["syllables"], m["rare"], math.log1p(m["clauses"]), m["range"],
                            expository, math.log(2030 - book["year"])]

    columns = list(zip(*[b["features"] for b in measured]))
    means = [sum(c) / len(c) for c in columns]
    spreads = [math.sqrt(sum((v - mu) ** 2 for v in c) / len(c)) or 1 for c, mu in zip(columns, means)]
    for book in measured:
        book["x"] = [1.0] + [(v - mu) / sd for v, mu, sd in zip(book["features"], means, spreads)]

    anchors = [b for b in measured if b["handTier"] is not None]
    if len(anchors) < 12:
        sys.exit(f"Only {len(anchors)} anchors measured; not enough to fit.")

    def leave_one_out(penalty):
        predictions = {}
        for held in anchors:
            rest = [b for b in anchors if b is not held]
            weights = ridge([b["x"] for b in rest], [b["handTier"] for b in rest], penalty)
            predictions[held["id"]] = sum(w * x for w, x in zip(weights, held["x"]))
        error = sum(abs(predictions[b["id"]] - b["handTier"]) for b in anchors) / len(anchors)
        return error, predictions

    penalty, (error, held_out) = min(((p, leave_one_out(p)) for p in [0.1, 0.3, 1, 3, 10, 30]), key=lambda item: item[1][0])
    weights = ridge([b["x"] for b in anchors], [b["handTier"] for b in anchors], penalty)

    # Ridge regression shrinks towards the middle tier; stretch its scale back to the hand tiers'
    # spread so the easiest classics can land low and the hardest high. The same stretch, worked out
    # from the left-out predictions, applies to every book.
    hands = [b["handTier"] for b in anchors]
    predictions = [held_out[b["id"]] for b in anchors]
    def spread(values):
        mean = sum(values) / len(values)
        return mean, math.sqrt(sum((v - mean) ** 2 for v in values) / len(values))
    (hand_mean, hand_sd), (pred_mean, pred_sd) = spread(hands), spread(predictions)
    def stretch(value):
        return hand_mean + (value - pred_mean) * hand_sd / (pred_sd or 1)
    for key in held_out:
        held_out[key] = stretch(held_out[key])
    error = sum(abs(held_out[b["id"]] - b["handTier"]) for b in anchors) / len(anchors)

    def ranks(values):
        order = sorted(range(len(values)), key=lambda i: values[i])
        out = [0.0] * len(values)
        i = 0
        while i < len(order):
            j = i
            while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
                j += 1
            for k in range(i, j + 1):
                out[order[k]] = (i + j) / 2
            i = j + 1
        return out
    ra, rb = ranks(hands), ranks([held_out[b["id"]] for b in anchors])
    ma, mb = sum(ra) / len(ra), sum(rb) / len(rb)
    rank_correlation = sum((x - ma) * (y - mb) for x, y in zip(ra, rb)) / math.sqrt(
        sum((x - ma) ** 2 for x in ra) * sum((y - mb) ** 2 for y in rb))
    print(f"\n{len(anchors)} anchors, {len(measured) - len(anchors)} classics; ridge {penalty}; "
          f"left-out mean error {error:.2f} tiers, rank correlation {rank_correlation:.2f}; weights {[round(w, 2) for w in weights]}")

    out = []
    for book in measured:
        m = book["metrics"]
        anchor = book["handTier"] is not None
        tier = held_out[book["id"]] if anchor else stretch(sum(w * x for w, x in zip(weights, book["x"])))
        tier = max(1.0, min(10.0, tier))
        if anchor:
            print(f"  anchor {book['title'][:40]:<40} hand {book['handTier']:>2}  text {tier:4.1f}")
        out.append({
            "gutenberg": book["gutenberg"], "id": book["id"], "title": book["title"], "author": book["author"], "year": book["year"],
            "pages": book["pages"] or max(40, int(round(book["totalWords"] / 290, -1))),
            "genres": book["genres"], "words": m["words"], "sentenceWords": round(m["sentence_words"], 1),
            "syllables": round(m["syllables"], 3), "rareWords": round(m["rare"], 4), "clauses": round(m["clauses"], 2),
            "tier": round(tier, 1), **({"handTier": book["handTier"]} if anchor else {}),
        })
    out.sort(key=lambda b: (b["tier"], b["id"]))
    model = {"features": FEATURES, "means": [round(v, 4) for v in means], "spreads": [round(v, 4) for v in spreads],
             "weights": [round(w, 4) for w in weights], "ridge": penalty, "stretch": [round(pred_mean, 4), round(hand_sd / (pred_sd or 1), 4), round(hand_mean, 4)],
             "anchors": len(anchors), "meanAbsoluteError": round(error, 2), "rankCorrelation": round(rank_correlation, 2),
             "source": "Project Gutenberg texts (public domain in the US), measured by Scripts/level-gutenberg.py"}
    OUT.write_text(json.dumps({"model": model, "books": out}, indent=1, ensure_ascii=False) + "\n")
    print(f"Wrote {len(out)} books to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
