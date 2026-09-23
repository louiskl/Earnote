# Earnote ausprobieren (Beta)

Danke fürs Mittesten! Earnote nimmt Vorlesungen, Meetings und Calls auf, schreibt sie **auf deinem Mac**
mit und macht daraus Notizen. Nichts davon geht in die Cloud.

## Installieren

Mit Homebrew geht es in einer Zeile:

```bash
brew tap louiskl/earnote && brew trust louiskl/earnote && brew install --cask earnote
```

Von Hand:

1. Neueste `Earnote.dmg` unter [Releases](https://github.com/louiskl/Earnote/releases) laden.
2. DMG öffnen, Earnote in den Ordner **Programme** ziehen, von dort starten.
3. Beim ersten Start fragt macOS nach **Mikrofon**, **Systemton** und **Mitteilungen** – alle drei erlauben,
   sonst nimmt die App nichts auf.

Die App ist signiert und notarisiert; die Warnung „Programm aus dem Internet“ sollte nicht kommen.

## Womit du rechnen solltest

- **Einmalig beim ersten Start:** Whisper lädt (ca. 1,6 GB) und wird für deinen Mac vorbereitet. Das dauert
  ein paar Minuten und passiert nur einmal. Dazu kommt die lokale KI (Qwen3 4B, 2,3 GB). In den
  Einstellungen unter „KI“ lässt sich jederzeit ein anderes Modell wählen.
- **Apple Silicon** (M1 oder neuer) und mindestens 8 GB RAM. Auf Intel-Macs läuft die lokale KI nicht.
- **Platz:** Eine Stunde Aufnahme braucht rund 1 GB, solange du die Audiodateien behältst.

## Das wäre hilfreich zu testen

1. **Eine ganze Vorlesung** (60–90 Minuten) aufnehmen. Deckel offen lassen – klappt der Mac zu, schläft er,
   und die Verarbeitung pausiert.
2. Nach dem Stopp die Zeit stoppen: Wie lange dauert es, bis die Notiz da ist?
3. **Notiz lesen:** Stimmt das Wesentliche? Fehlt etwas Wichtiges? Steht etwas drin, das nie gesagt wurde?
4. **Transkript prüfen** (⌘2): Werden Namen und Fachbegriffe richtig geschrieben? Falsche Begriffe über
   „Namen & Begriffe korrigieren …“ ersetzen und ins Wörterbuch aufnehmen – schreibt die App sie beim
   nächsten Mal richtig?
5. **Lernzettel** als PDF sichern (Knopf „PDF sichern“ unter der Notiz) – taugt das Layout zum Lernen?
6. **Nachhören:** Im Transkript auf eine Zeitmarke klicken – springt der Ton an die richtige Stelle?
   Mit ⌘3 stehen Notiz und Transkript nebeneinander und das Transkript scrollt beim Abspielen mit.
7. **Karteikarten** (Knopf „Karteikarten erzeugen“ unter der Notiz) – taugen die Fragen zum Lernen?
   Daneben liegt der Anki-Export.
8. **Übersicht über ein Fach:** Bereich in der Seitenleiste wählen › Knopf „Übersicht“ oben (⇧⌘U),
   sobald du dort mehrere Vorlesungen hast. Stimmt der rote Faden? Sind die Prüfungshinweise wirklich welche?
9. **Vereinfachen** (unter der Notiz) – ist die einfache Fassung verständlich, und fehlt nichts Wichtiges?
10. **Aufgaben weiterreichen:** In den Einstellungen unter „Ziele“ Apple Erinnerungen, Things oder Todoist
   einschalten – landen die offenen Aufgaben dort, wo du sie erwartest?
11. **Bei Meetings:** „Kurzprotokoll kopieren“ – ist das der Text, den du verschicken würdest?
12. Alles, was sich **komisch anfühlt**: unklare Texte, Knöpfe, die du nicht findest, Wartezeiten ohne Erklärung.

## Was seit Beginn der Beta neu ist (0.9.13–0.9.19)

Die Notiz erscheint, während die KI sie schreibt · kürzere Notizen in Stichpunkten · weniger Erfundenes
(Aufgaben, Fristen, Namen und Fragen, die nie gesagt wurden, fallen weg) · 4–8 Karteikarten mit Zähler ·
Übersicht im Hintergrund, Knopf in der Symbolleiste · „Vereinfachen“ · schönere PDFs · Hinweis, wenn der
Stromsparmodus bremst · weniger Arbeitsspeicher · Absturz beim Verbinden oder Trennen von Kopfhörern behoben.

## Bitte noch auslassen

Unter *Einstellungen › Allgemein* steht ein Schalter **„Bibliothek über iCloud synchronisieren"**.
Er funktioniert, ist aber noch nicht lange genug erprobt. Lass ihn bitte aus, bis ich Entwarnung gebe –
bei einem Fehler im Abgleich stünden Notizen auf dem Spiel.

## Fehler melden

In der App: **Einstellungen › Über › „Fehler melden …“**. Das öffnet ein vorausgefülltes Issue auf GitHub –
mit Version, macOS-Version, Mac-Modell und den letzten Protokollzeilen. Ohne GitHub-Konto: „Diagnose kopieren“
und den Text einfach an Louis schicken.

Bitte **keine Screenshots mit fremden Inhalten** (Namen von Dozierenden, Gesprächsinhalte) ins öffentliche
Issue stellen – eine kurze Beschreibung reicht.

## Zwei Dinge, die du wissen solltest

- **Einverständnis:** Wer andere aufnimmt, braucht ihr Einverständnis (§ 201 StGB). Bei Vorlesungen vorher
  kurz mit der dozierenden Person klären.
- **Deine Daten bleiben lokal:** Aufnahmen, Transkripte und Notizen liegen in
  `~/Library/Application Support/Earnote`. Earnote schickt nichts an einen Server – außer du wählst in den
  Einstellungen ausdrücklich eine Cloud-KI.

Kein GitHub-Konto? Dann schreib einfach an **hallo@earnote.dev** – Version, Mac und
ein, zwei Sätze genügen.
