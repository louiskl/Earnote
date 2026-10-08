"""Ratgeber-Seiten für earnote.dev (Suchmaschinen): python3 scripts/seo_pages.py → docs/<slug>.html + sitemap.xml"""
import html, json, pathlib, datetime

DOCS = pathlib.Path(__file__).resolve().parent.parent / "docs"
STORE = "https://apps.apple.com/de/app/id6815681807"
TODAY = datetime.date.today().isoformat()

PAGES = [
    {
        "slug": "vorlesung-aufnehmen",
        "title": "Vorlesung aufnehmen und mitschreiben lassen – App für iPhone, iPad und Mac",
        "desc": "Vorlesung mit dem iPhone aufnehmen und danach eine fertige Notiz mit Karteikarten und Lernzettel bekommen. Kostenlos, ohne Konto, die Spracherkennung läuft auf dem Gerät.",
        "h1": "Vorlesung aufnehmen.<br><span class=\"dim\">Notiz lesen statt mittippen.</span>",
        "lead": "Wer in der Vorlesung alles mitschreibt, hört nicht mehr richtig zu. Mit Earnote legst du das iPhone auf den Tisch, nimmst auf und bekommst danach eine geordnete Notiz – mit Karteikarten und einem Lernzettel als PDF.",
        "sections": [
            ("So nimmst du eine Vorlesung mit dem iPhone auf", """
<ol class="steps">
<li><span class="num">1</span><div><h3>Frag, ob du aufnehmen darfst</h3><p>Viele Dozierende erlauben es, manche Hochschulen verbieten es. Frag vorher – das ist nicht nur höflich, sondern auch rechtlich wichtig (siehe unten).</p></div></li>
<li><span class="num">2</span><div><h3>Handy hinlegen, Aufnahme starten</h3><p>Leg das iPhone mit dem Mikrofon Richtung Tafel. Du kannst den Bildschirm sperren: Earnote nimmt weiter auf und zeigt die Laufzeit als Live-Aktivität auf dem Sperrbildschirm.</p></div></li>
<li><span class="num">3</span><div><h3>Nach der Vorlesung: Notiz lesen</h3><p>Earnote transkribiert die Aufnahme und schreibt daraus eine Notiz: Zusammenfassung, wichtige Begriffe, Aufgaben und Termine, Karteikarten zum Abfragen.</p></div></li>
</ol>"""),
            ("Was am Ende in der Notiz steht", """
<p>Keine Abschrift Wort für Wort, sondern das, was du selbst notiert hättest, wenn du schnell genug gewesen wärst:</p>
<ul>
<li><strong>Zusammenfassung</strong> mit Überschriften, Rechenwegen und Definitionen</li>
<li><strong>Wichtig für die Klausur:</strong> Stellen, die die dozierende Person betont hat</li>
<li><strong>Aufgaben und Termine</strong> („Übungsblatt bis Freitag“), zum Abhaken</li>
<li><strong>Karteikarten</strong> zum Abfragen direkt in der App, auch als Anki-Datei</li>
<li><strong>Lernzettel als PDF</strong> zum Ausdrucken oder Teilen mit der Lerngruppe</li>
<li>Das <strong>Transkript</strong> mit Zeitmarken – tippe auf eine Stelle und hör sie dir noch einmal an</li>
</ul>"""),
            ("Bleibt die Aufnahme privat?", """
<p>Ja. Die Spracherkennung (Whisper) läuft auf deinem iPhone, iPad oder Mac. Die Notiz schreibt ab dem iPhone 15 Pro das Handy selbst – auch im Flugmodus. Auf älteren Geräten übernimmt das dein Mac oder, wenn du willst, ein kostenloser Google- oder OpenRouter-Schlüssel. Es gibt kein Konto und keinen Earnote-Server, auf dem deine Aufnahmen landen.</p>"""),
            ("Darf ich eine Vorlesung überhaupt aufnehmen?", """
<p>In Deutschland schützt <strong>§ 201 StGB</strong> das nichtöffentlich gesprochene Wort. Eine Vorlesung ist meist nicht öffentlich – nimm sie deshalb nur auf, wenn die dozierende Person einverstanden ist, und gib die Aufnahme nicht weiter. Manche Hochschulen regeln das in ihrer Hausordnung ausdrücklich. Wenn Aufnehmen nicht erlaubt ist, funktioniert Earnote trotzdem: Sprich nach der Vorlesung in zwei Minuten ein, was du verstanden hast – daraus werden genauso Notiz und Karteikarten.</p>
<p class="fine">Das ist keine Rechtsberatung, sondern ein Hinweis, worauf du achten solltest.</p>"""),
            ("Tipps für gute Aufnahmen", """
<ul>
<li>Setz dich in die vorderen Reihen – die Tonqualität entscheidet über das Transkript.</li>
<li>Leg das Handy auf eine Jacke oder ein Etui, dann überträgt der Tisch weniger Klappern.</li>
<li>Trag Namen von Dozierenden und Fachbegriffe ins Wörterbuch der App ein, dann schreibt Earnote sie richtig.</li>
<li>Markiere wichtige Stellen mit „Wichtig“ – auch vom Sperrbildschirm aus (Earnote Pro, dreimal gratis).</li>
</ul>"""),
        ],
        "faq": [
            ("Wie lange kann ich eine Vorlesung aufnehmen?", "So lange, wie Speicher und Akku reichen – 90 Minuten sind kein Problem. Der Bildschirm kann dabei aus sein."),
            ("Kostet die App etwas?", "Nein. Aufnehmen, Transkript, Notiz, Karteikarten und Lernzettel sind kostenlos, ohne Konto und ohne Abo. Wer mehr will, kann einmalig Earnote Pro für 9,99 € kaufen."),
            ("Funktioniert das auch mit englischen Vorlesungen?", "Ja. Earnote erkennt viele Sprachen. Die Sprache der Notiz wählst du getrennt – eine englische Vorlesung kann also eine deutsche Notiz ergeben."),
            ("Gibt es die App für Android oder Windows?", "Nein. Earnote gibt es für iPhone, iPad und Mac."),
        ],
    },
    {
        "slug": "interview-transkribieren",
        "title": "Interviews transkribieren für Bachelor- und Masterarbeit – kostenlos und ohne Upload",
        "desc": "Experteninterviews für die Abschlussarbeit kostenlos transkribieren: Earnote macht das auf iPhone, iPad oder Mac, ohne die Aufnahmen hochzuladen. Mit Zeitmarken und Sprechererkennung.",
        "h1": "Interviews transkribieren.<br><span class=\"dim\">Ohne Upload, ohne Abo.</span>",
        "lead": "Eine Stunde Interview abzutippen dauert schnell vier bis fünf Stunden. Earnote macht daraus in Minuten ein Transkript mit Zeitmarken – direkt auf deinem Gerät, sodass die Aufnahmen deiner Interviewpartner nirgends hochgeladen werden.",
        "sections": [
            ("Warum lokal transkribieren?", """
<p>Für qualitative Interviews in der Bachelor- oder Masterarbeit unterschreiben deine Interviewpartner meist eine Einwilligung. Darin steht oft, dass die Aufnahmen nicht an Dritte gehen. Viele Online-Transkriptionsdienste laden die Datei aber auf ihre Server. Earnote erkennt die Sprache mit Whisper <strong>auf deinem iPhone, iPad oder Mac</strong> – die Aufnahme verlässt das Gerät nicht. Das kannst du auch so in deine Datenschutzerklärung fürs Interview schreiben.</p>"""),
            ("So geht's", """
<ol class="steps">
<li><span class="num">1</span><div><h3>Aufnehmen oder importieren</h3><p>Nimm das Interview direkt in Earnote auf – oder schick eine vorhandene Aufnahme aus Sprachmemos, Dateien oder einer anderen App über „Teilen“ an Earnote.</p></div></li>
<li><span class="num">2</span><div><h3>Transkript prüfen</h3><p>Du bekommst das Transkript mit Zeitmarken. Tippe auf eine Stelle, um sie anzuhören, und korrigiere Namen über das Wörterbuch einmal für alle Interviews.</p></div></li>
<li><span class="num">3</span><div><h3>Sprecher zuordnen</h3><p>Die Sprechererkennung trennt Interviewer und Befragte („Sprecher 1, Sprecher 2“), du gibst ihnen Namen oder Kürzel. Am Mac ist sie kostenlos, auf iPhone und iPad Teil von Earnote Pro (dreimal gratis).</p></div></li>
<li><span class="num">4</span><div><h3>Exportieren</h3><p>Übernimm das Transkript als Text in Word, MAXQDA oder dein Schreibprogramm und codiere wie gewohnt.</p></div></li>
</ol>"""),
            ("Wie genau ist das Transkript?", """
<p>Whisper gehört zu den genauesten Spracherkennungen, die es gibt, auch bei Dialekt und Fachbegriffen. Fehlerfrei ist kein automatisches Transkript: Plane ein, jedes Interview einmal gegenzuhören – das geht mit den Zeitmarken schnell. Für eine Transkription nach festen Regeln (etwa nach Dresing und Pehl) passt du Satzzeichen und Pausen danach an.</p>"""),
            ("Was kostet das?", """
<p>Transkription und Notiz sind kostenlos, ohne Konto und ohne Abo – auch für viele Stunden Material. Das ist kein Probeangebot: Earnote hat keine Server, die pro Minute bezahlt werden müssten.</p>"""),
        ],
        "faq": [
            ("Kann ich Interviews aus Zoom oder Teams transkribieren?", "Ja. Am Mac nimmt Earnote den Ton des Calls zusammen mit deinem Mikrofon auf. Vorhandene Aufnahmen kannst du auf allen Geräten importieren."),
            ("Wie lange dauert die Transkription?", "Auf einem MacBook Air M1 ist eine Stunde Aufnahme in etwa fünf bis sechs Minuten transkribiert. Auf dem iPhone dauert es etwas länger."),
            ("Welche Sprachen gehen?", "Deutsch, Englisch und viele weitere Sprachen. Mehrsprachige Interviews funktionieren ebenfalls."),
            ("Werden die Interviews irgendwo gespeichert?", "Nur auf deinem Gerät. Es gibt kein Earnote-Konto und keinen Earnote-Server."),
        ],
    },
    {
        "slug": "karteikarten-erstellen",
        "title": "Karteikarten automatisch erstellen – aus Vorlesung, Lerngruppe oder eigener Erklärung",
        "desc": "Karteikarten automatisch erstellen lassen: Sprich den Stoff ein oder nimm die Vorlesung auf, Earnote macht daraus Karteikarten zum Abfragen und als Anki-Datei. Kostenlos für iPhone, iPad und Mac.",
        "h1": "Karteikarten erstellen lassen.<br><span class=\"dim\">Nicht abschreiben.</span>",
        "lead": "Karteikarten schreiben ist der langweiligste Teil vom Lernen – und kostet am meisten Zeit. Earnote macht sie aus jeder Aufnahme: aus der Vorlesung, der Lerngruppe oder aus deiner eigenen Erklärung.",
        "sections": [
            ("Drei Wege zu Karteikarten", """
<div class="ways">
<div class="tile"><h3>🎙️ Stoff selbst erklären</h3><p>Erklär das Thema laut, als würdest du es jemandem beibringen (Feynman-Methode). Wo du hängen bleibst, fehlt dir etwas – und aus deiner Erklärung werden Karteikarten.</p></div>
<div class="tile"><h3>🏫 Vorlesung aufnehmen</h3><p>Wenn die dozierende Person einverstanden ist: aufnehmen, und nach der Vorlesung liegen Notiz und Karteikarten bereit.</p></div>
<div class="tile"><h3>👥 Lerngruppe</h3><p>Nehmt eure Lerngruppe auf. Danach hat jede:r die Fragen, die ihr besprochen habt, als Karten.</p></div>
</div>"""),
            ("Abfragen nach Active Recall", """
<p>Die Karten fragst du direkt in Earnote ab: Frage lesen, antworten, umdrehen, „Wusste ich“ oder „Nochmal“. Was du nicht wusstest, kommt wieder dran. Das ist Active Recall – eine der Lernmethoden, die in Studien am besten abschneiden, weil du Wissen aktiv abrufst statt es nur noch einmal zu lesen.</p>"""),
            ("Mit Anki weiterlernen", """
<p>Du lernst lieber mit Anki? Earnote gibt die Karten als Anki-Datei weiter. So bekommst du die Wiederholung nach Zeitplan, ohne eine einzige Karte selbst zu tippen.</p>"""),
            ("Und dazu ein Lernzettel", """
<p>Aus derselben Aufnahme macht Earnote auch einen Lernzettel als PDF – die Zusammenfassung zum Ausdrucken oder zum Teilen mit der Lerngruppe. Am Mac gibt es zusätzlich eine Übersicht je Fach über das ganze Semester.</p>"""),
        ],
        "faq": [
            ("Kostet das etwas?", "Nein. Karteikarten, Lernzettel und Notizen sind kostenlos, ohne Konto und ohne Abo."),
            ("Funktioniert das auch fürs Abi?", "Ja. Sprich den Stoff ein, wie du ihn im Mündlichen erklären würdest – Earnote macht daraus Karten zum Abfragen."),
            ("Wie viele Karten entstehen pro Aufnahme?", "Das hängt vom Inhalt ab: Earnote macht Karten zu den Begriffen, Definitionen und Zusammenhängen, die wirklich vorkommen, statt Füllfragen zu erfinden."),
        ],
    },
    {
        "slug": "meeting-protokoll",
        "title": "Meeting-Protokoll automatisch schreiben – ohne Bot im Call",
        "desc": "Meeting-Protokoll automatisch erstellen: Earnote nimmt Meetings und Calls auf (Zoom, Teams, Meet) und schreibt Notiz und To-dos – ohne Bot im Call und ohne Cloud. Für Werkstudierende, Duales Studium und Vereine.",
        "h1": "Meeting vorbei.<br><span class=\"dim\">Protokoll fertig.</span>",
        "lead": "Werkstudi, Duales Studium, Fachschaft oder Verein: Irgendwer muss immer das Protokoll schreiben. Earnote hört mit und schreibt Zusammenfassung, Entscheidungen und To-dos – ohne dass ein Bot dem Call beitritt.",
        "sections": [
            ("Kein Bot im Meeting", """
<p>Viele Meeting-Tools schicken einen „Notetaker“ als eigenen Teilnehmer in den Call. Earnote nimmt stattdessen den Ton auf deinem Mac auf – Mikrofon und Systemton zusammen, damit alle im Transkript landen. Es erkennt Zoom, Teams und Google Meet und bietet dir an, mitzuschreiben. Im Raum legst du einfach das iPhone auf den Tisch.</p>"""),
            ("Was im Protokoll steht", """
<ul>
<li>Zusammenfassung mit den besprochenen Punkten</li>
<li>Entscheidungen und offene Fragen</li>
<li>To-dos mit Namen und Fristen – Aufgaben, die niemand gesagt hat, erfindet Earnote nicht</li>
<li>Sprechererkennung: wer hat was gesagt (am Mac kostenlos, auf iPhone und iPad mit Earnote Pro)</li>
<li>Export nach Markdown, Obsidian, Notion, Apple Notizen, Things, Todoist und mehr (Mac)</li>
</ul>"""),
            ("Datenschutz bei der Arbeit", """
<p>Meetings enthalten oft Interna. Earnote transkribiert auf deinem Gerät und lädt nichts auf einen Earnote-Server – es gibt keinen. Sag trotzdem vorher Bescheid, dass du aufnimmst: Das gehört sich, und in Deutschland schützt § 201 StGB das nichtöffentlich gesprochene Wort. Klär außerdem mit deinem Arbeitgeber, ob Aufnahmen erlaubt sind.</p>"""),
        ],
        "faq": [
            ("Brauche ich dafür ein Konto oder ein Abo?", "Nein. Earnote ist kostenlos, ohne Konto und ohne Abo, auf Mac, iPhone und iPad."),
            ("Funktioniert das mit Microsoft Teams?", "Ja. Am Mac nimmt Earnote den Ton von Teams, Zoom und Google Meet zusammen mit deinem Mikrofon auf."),
            ("Geht das auch für Vereinssitzungen?", "Ja – Handy auf den Tisch, aufnehmen, und danach steht das Protokoll mit Beschlüssen und Aufgaben da."),
        ],
    },
]

NAV = """<nav class="nav">
    <a class="brand" href="./de.html"><img src="assets/icon.png" alt="">Earnote</a>
    <div class="links">
        <a href="de.html" class="hide-s">Startseite</a>
        <a class="pill" data-goatcounter-click="appstore-ratgeber-menue" href="{store}">App Store</a>
    </div>
</nav>"""

FOOT = """<footer>
    <div class="wrap">
        <div class="links">
            {guides}
            <a href="de.html">Startseite</a>
            <a href="https://github.com/louiskl/Earnote">GitHub</a>
            <a href="datenschutz.html">Datenschutz (Website)</a>
            <a href="impressum.html">Impressum</a>
            <a href="mailto:hallo@earnote.dev">Kontakt</a>
        </div>
        <p>Earnote ist quelloffen unter der MIT-Lizenz. Gebaut von einem Studenten, der keine Lust mehr hatte mitzutippen.</p>
    </div>
</footer>"""


def page(p):
    url = f"https://earnote.dev/{p['slug']}.html"
    faq_ld = {"@context": "https://schema.org", "@type": "FAQPage", "mainEntity": [
        {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in p["faq"]]}
    app_ld = {"@context": "https://schema.org", "@type": "SoftwareApplication", "name": "Earnote",
              "applicationCategory": "EducationalApplication", "operatingSystem": "iOS, iPadOS, macOS",
              "url": "https://earnote.dev/de.html", "installUrl": STORE, "isAccessibleForFree": True,
              "offers": {"@type": "Offer", "price": "0", "priceCurrency": "EUR"}}
    guides = "\n            ".join(f'<a href="{o["slug"]}.html">{html.escape(o["title"].split(" – ")[0])}</a>'
                                   for o in PAGES if o is not p)
    body = "\n".join(f'<section><div class="wrap narrow"><h2>{h}</h2>{c}</div></section>' for h, c in p["sections"])
    faq = "\n".join(f"<dt>{html.escape(q)}</dt><dd>{html.escape(a)}</dd>" for q, a in p["faq"])
    return f"""<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(p['title'])}</title>
<meta name="description" content="{html.escape(p['desc'])}">
<link rel="canonical" href="{url}">
<meta property="og:title" content="{html.escape(p['title'])}">
<meta property="og:description" content="{html.escape(p['desc'])}">
<meta property="og:image" content="https://earnote.dev/assets/iphone-note-de.jpg">
<meta property="og:url" content="{url}">
<meta property="og:type" content="article">
<meta property="og:locale" content="de_DE">
<meta name="twitter:card" content="summary_large_image">
<meta name="theme-color" content="#E8453B">
<meta name="apple-itunes-app" content="app-id=6815681807">
<link rel="icon" href="assets/icon.png">
<link rel="apple-touch-icon" href="assets/icon.png">
<link rel="stylesheet" href="assets/style.css">
<style>.narrow {{ max-width: 760px; }} .narrow ul {{ padding-left: 1.2em; line-height: 1.7; }} .narrow p {{ line-height: 1.7; }}</style>
<script type="application/ld+json">{json.dumps(faq_ld, ensure_ascii=False)}</script>
<script type="application/ld+json">{json.dumps(app_ld, ensure_ascii=False)}</script>
<!-- Besucherzählung ohne Cookies (siehe datenschutz.html) -->
<script data-goatcounter="https://louiskl.goatcounter.com/count" async src="//gc.zgo.at/count.js"></script>
</head>
<body>
<div class="glow"><span class="a"></span><span class="b"></span><span class="c"></span></div>
{NAV.format(store=STORE)}
<header class="hero">
    <div class="wrap narrow">
        <span class="badge"><i></i>Ratgeber · Earnote für iPhone, iPad und Mac</span>
        <h1>{p['h1']}</h1>
        <p class="claim">{p['lead']}</p>
        <div class="cta">
            <a class="btn" data-goatcounter-click="appstore-{p['slug']}" href="{STORE}">Kostenlos im App Store</a>
            <a class="btn ghost" href="de.html">Mac-App &amp; mehr</a>
        </div>
        <p class="fine">Kostenlos · ohne Konto · ohne Abo · quelloffen</p>
    </div>
</header>
{body}
<section><div class="wrap narrow">
    <h2>Häufige Fragen</h2>
    <dl class="faq">{faq}</dl>
</div></section>
<section style="padding-top:0"><div class="wrap" style="text-align:center">
    <h2>Probier es mit deiner nächsten Aufnahme.</h2>
    <div class="cta"><a class="btn" data-goatcounter-click="appstore-{p['slug']}-unten" href="{STORE}">Earnote laden</a></div>
</div></section>
{FOOT.format(guides=guides)}
</body>
</html>
"""


for p in PAGES:
    (DOCS / f"{p['slug']}.html").write_text(page(p))

# Sitemap: Start- und Ratgeber-Seiten
urls = [("https://earnote.dev/", True), ("https://earnote.dev/de.html", True)] + \
       [(f"https://earnote.dev/{p['slug']}.html", False) for p in PAGES]
alt = """
    <xhtml:link rel="alternate" hreflang="en" href="https://earnote.dev/"/>
    <xhtml:link rel="alternate" hreflang="de" href="https://earnote.dev/de.html"/>"""
entries = "".join(f"""
  <url>
    <loc>{u}</loc>
    <lastmod>{TODAY}</lastmod>{alt if a else ''}
  </url>""" for u, a in urls)
(DOCS / "sitemap.xml").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
        xmlns:xhtml="http://www.w3.org/1999/xhtml">{entries}
</urlset>
""")
print("\n".join(p["slug"] for p in PAGES))
