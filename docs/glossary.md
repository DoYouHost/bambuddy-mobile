# Glossary — Polish names for printer parts

Polish UI names for printer parts come from Bambu Studio's own localisation, not
from a fresh translation: it is the vocabulary a Bambu owner already sees in the
slicer, and the bambuddy web UI has no `pl` locale to copy from. Check a part name
at the source before inventing one.

The repository holds only the compiled catalogue:

```sh
gh api repos/bambulab/BambuStudio/contents/resources/i18n/pl/BambuStudio.mo \
  --jq .download_url | xargs curl -sL -o bs_pl.mo
python3 -c "import gettext; print(gettext.GNUTranslations(open('bs_pl.mo','rb'))._catalog)"
```

The catalogue is keyed by the English source string, so look a term up by its
Bambu Studio English name.

| English (Bambu Studio) | Polish | Used in |
|---|---|---|
| Part cooling fan | Wentylator chłodzący wydruk | `ctrlFanPart` |
| Auxiliary (`AUX`) | Pomocniczy | `ctrlFanAuxLabel` |
| Left | Lewy | `ctrlFanAux2Label` |
| Chamber | Komora | `tempChamber`, `ctrlFanChamberLabel` |
| Exhaust | Wyciąg | `ctrlFanExhaustShort` |
| Exhaust fan | Wentylator wyciągowy | `ctrlFanExhaust` |

**Which fan is which.** The `cooling_fan_speed` field (`M106 P1`) is the *part*
cooling fan. The hotend's fan is `heatbreak_fan_speed`, which the app parses but
does not show — do not label the part fan "Hotend fan".

LanguageTool (`just l10n-check`, see
[dev-environment.md](dev-environment.md#copy-checks-languagetool)) checks spelling
and grammar, not whether a phrase is the right term; the glossary is the check for
terms.
