# Katalogbild-Modelle im Vergleich

Neun Generierungen, drei Kleidungsstücke, drei Modelle. Gleicher Referenz-
Ausschnitt (`normalizeSourceForProvider` + `cropGenerationReference` auf dem
Original-Upload), gleicher `laid-flat-v3`-Prompt, `high` / 816x816.
Gemessen am 11.09.2026, Gesamtkosten des Versuchs 0,94 USD.

## Zahlen

| Modell | Output-Tokens | Ø Kosten | Ø Dauer | Chroma-Key |
| --- | --- | --- | --- | --- |
| `gpt-image-2` | 6143 | 0,1964 USD | 108,4 s | 3/3 gehalten |
| `gpt-image-2.5-flare` | 1536 | **0,0582 USD** | **19,5 s** | 3/3 gehalten |
| `gpt-image-2.5-sunburst` | 1536 | 0,0582 USD | 35,7 s | 3/3 gehalten |

Die Output-Tokens sind pro Modell konstant. Der Tarif ist bei allen dreien
identisch (5 / 8 / 30 USD je Million für Text-, Bild-Eingabe und Bild-Ausgabe),
2.5 braucht für dasselbe Bild aber ein Viertel der Tokens. Daraus folgen 3,4-mal
niedrigere Kosten und 5,6-mal kürzere Laufzeit.

## Dateien

Die Bilder selbst liegen nur lokal (siehe `.gitignore`), erzeugt aus den
Original-Uploads auf stargate. Dieses README hält die Ergebnisse fest.

Pro Stück: `00-reference.jpg` ist der Ausschnitt, der ans Modell geht.
`01`–`03` sind die Ergebnisse, einmal freigestellt auf Papierfarbe `#f6f5f1`
(so wie FORM sie zeigt) und einmal als `-keyed.png` mit der rohen
Chroma-Fläche, wie das Modell sie geliefert hat.

## Beobachtungen

- **Teddyfleece:** Nur Flare bleibt nach dem Freistellen frei von grünen
  Resten; `gpt-image-2` und Sunburst lassen an beiden Saumseiten Chroma-Pixel
  stehen. `gpt-image-2` erfindet zusätzlich eine Känguru-Tasche in dem Bereich,
  den die Hände im Original verdecken – der Prompt verlangt dort Auslassen.
- **Felljacke:** `gpt-image-2` gibt das Fell flach und samtig wieder, Flare
  zeigt echte Faserstruktur. Alle drei erhalten beide North-Face-Logos und das
  Supreme-Label. Sunburst ist am detailliertesten, beschneidet das Stück aber
  am linken Rand.
- **Schwarzes Shirt:** Untauglich als Vergleich. Der Detektions-Ausschnitt
  schneidet den Halsausschnitt komplett weg, jedes Modell muss ihn erfinden.

## Zwei offene Punkte aus dem Versuch

1. Alle drei Modelle wählten Grün als Key-Farbe für die **grüne** North-Face-
   Jacke, obwohl der Prompt eine im Kleidungsstück vorkommende Key-Farbe
   ausschließt. Es ging gut, weil das Grün dunkel genug ist – verlässlich ist
   das nicht.
2. Der Ausschnitt beim schwarzen Shirt enthält den Halsausschnitt nicht. Die
   18 % Kontext-Polsterung in `cropGenerationReference` reichen nicht, wenn die
   Box knapp sitzt.
