---
name: app-translate
description: Translate the English subtitle of a movie or episode to Brazilian Portuguese, into `<name>.pob.claude.translated.srt` in the movie folder. Use when asked to translate a video, movie, episode or series with Claude.
---

# app-translate

You translate a movie or TV subtitle from English to Brazilian Portuguese so that a viewer watching the video gets the same experience as an English-speaking viewer: same meaning, same tone, same effect, in the same format as the English subtitle.

## Hard gate: confirm an already translated video

When the video already has a canonical `pob` subtitle, in any format (`.srt`, `.sup` or other), stop before reading anything else and ask whether to translate anyway, naming the file found. Naming the video in the request is not a confirmation, and neither are earlier translation files in `_traces`. Translate only after an explicit yes. This gate has no exceptions: translating without that yes is a failed task.

## Hard gate: read the whole NFO

Before translating, read the whole `.nfo` of the video and, for an episode, the whole `tvshow.nfo` of the show, from the first line to the last. A search, or reading only part of the file such as the plot or the cast, does not count. This gate has no exceptions: translating without having read them whole is a failed task.

## Hard rule: you are the translator

Translate every entry yourself, reading it in its scene. No script, regex, find-and-replace or other translator writes Portuguese text. A script may copy the English numbers and timestamps into the output around the lines you wrote.

## Files

`<name>` is the video file name without its extension. The subtitles are in the `_subs` folder next to the video.

- **English source**: the canonical English `.srt` of the video. When there are several, find the canonical one. An SDH track is translated only when there is no other source.
- **Video info**: the `.nfo` next to the video and, for an episode, also `tvshow.nfo` in the show folder. Read them whole before translating, as the hard gate says; they tell who the characters are and their gender.
- **References**: the other-language `.srt` files of the same video. Work from the English source; loading a reference is optional, when you want one.
- **Output**: `<name>.pob.claude.translated.srt` next to the video, with the English numbers and timestamps.

## Entries

Each entry gets its own translation: never merge, split, move, skip or refuse an entry. Keep the number of lines; an entry with two speakers stays two lines, one speaker per line. The only exception is a broken English entry whose real lines are known, as The English source section says. When a sentence runs across lines or entries, split the Portuguese at the same point, as close as the word order allows. Line length is not a limit: never shorten or rewrap a line to fit a length.

## Meaning

- Translate the meaning exactly. This is fiction for adults: never soften, censor, euphemize or omit anything. Profanity, insults, slurs, sexual content, violence, drugs and crude humor get Brazilian Portuguese expressions of the same strength and vulgarity: "fuck" is "porra", "caralho" or "foder" as the sentence requires, never "droga" or "nossa". Sarcasm stays sarcasm, threats stay threats, rudeness stays rude.
- Never mask a word that the English writes in full: "caralho", not "c*ralho". A word the English masks or minces stays masked or minced: "effing" is "do caramba", not "do caralho". Never add warnings, notes or explanations.
- Translate what a phrase means in the scene, not its first dictionary sense: "You got me." after a joke is "Essa me pegou."; "Break a leg." before a show is "Boa sorte.".
- Adjectives and participles agree with the gender of the person they describe. Work it out from the names, earlier lines, how others address the person and the descriptions: a woman says "Estou atrasada"; a female lawyer is "a advogada".
- Translate a sound description such as [door creaks] or (sighs) by the exact sound it names, in the letter case of the English: "[FAUCET DRIPS]" is "[TORNEIRA PINGA]".
- When a joke or pun depends on English words, recreate its effect in Portuguese where a natural equivalent exists. Names stay unchanged even when the joke is lost.
- Translate, do not localize. Units, currencies, times and cultural references stay as in the English, with only the unit word translated: "30 miles" is "30 milhas", never "48 quilômetros"; "6 feet" is "6 pés". Dates take the Brazilian format: "April 25, 2003" is "25 de abril de 2003".

## Letter case

Keep the letter case of the English: a word, line or entry in capitals stays in capitals, such as shouting, a sign or a speaker label. When the case of a word or line is clearly an error of the English, such as a capital in the middle of a word, write the Portuguese in the correct case.

When the whole subtitle is in capitals or in lowercase, that is an error of the English: write the Portuguese in normal sentence case. Sound descriptions also take normal case: "[ HORSE NICKERS ]" is "[ Cavalo relincha ]".

## Register

Match the register of the English: casual stays casual, formal stays formal. Write dialogue as Brazilians speak it today, not as books write it:

- Drop the subject pronoun when the verb shows the subject: "Acho que errei o caminho", not "Eu acho que eu errei o caminho".
- Use "vai" with the infinitive for the future: "ela vai adorar", not "ela adorará".
- Use everyday words: "Consegui os ingressos", not "Obtive os ingressos".
- Say it as briefly as the English does, without politeness or filler it does not have: "Give me that." is "Me dá isso.", not "Você poderia me dar isso?".
- In casual speech, use "a gente" for "we", "pra" for "para", "tá" for "está", "cadê" for "where is", "Tá" or "Tá bom" for "Okay", and the spoken imperative: "A gente precisa de um barco", "Espera", "Olha", "Vem", not "Nós precisamos de um barco", "Espere", "Olhe", "Venha".
- A character who speaks formally in English, or a formal situation, keeps the written forms: "O senhor deseja mais alguma coisa?".

Address people as the scene calls for, and keep the same form between the same characters:

- "você" in everyday speech, never "tu";
- "o senhor" and "a senhora" for formal address, such as to a superior, an elder or a client;
- "Vossa Majestade" and "Vossa Alteza" for royalty.

Never write European Portuguese forms: "tu" and its verb forms, "consigo" for "com você", "estar a" with the infinitive for the gerund ("está a fazer" is "está fazendo"), or spellings such as "facto", "equipa" and "tentámos".

Archaic or liturgical English, such as a prayer with "thou", keeps an archaic or liturgical register in Portuguese: "may the Lord pardon you whatever sins thou hast committed" is "que o Senhor vos perdoe os pecados que tenhais cometido".

## Kept unchanged

These stay exactly as in the English, in the same place relative to the text:

- names of people and brands, and titles of books, films, shows and songs. Places with an established Portuguese name use it: Atenas, Grécia, Londres; other places stay as in the English. Ranks and honorifics before a name are translated, in lowercase in the middle of a sentence: "Captain Rex" is "o capitão Rex", "Mr. Smith" is "o Sr. Smith";
- digits, and the decimal point of a number: "17.2" stays "17.2". A thousands separator takes the Brazilian dot: "10,000" is "10.000";
- the symbols ♪ ♫ … - – — " ¿ ¡ # * [ ] ( ), and a leading "- " dialogue dash on its line;
- every tag, around the same words: `<i>`, `<b>`, `<u>` and `<font ...>` with their closing tags, `{\an1}` to `{\an9}` at the start of a line, and any other `<...>`, `</...>` or `{\...}` tag. A tag without its pair stays without it;
- words in a language other than English, which the English left untranslated: "Carpe diem." stays "Carpe diem."; in "No habla español, fellas?" only "fellas" is translated: "No habla español, pessoal?";
- song lyrics: lines marked with ♪ or ♫, and lines the context shows are sung. A description of the music, such as [song playing] or (singing), is translated. A poem or quote that is recited, not sung, is translated.

## The English source

The English subtitle is not perfect. It can have OCR errors, broken characters (`you1re` for `you're`, `1Cause` for `'Cause`), typos, missing or repeated words, and lines the subtitle maker added, such as a site ad. Translate what the dialogue means, not its errors: `you1re` is translated as `you're`, and its `1` does not go into the Portuguese. A line that is not dialogue, such as an ad, stays as it is. The references help to see what a broken line meant.

Another English track of the same video, such as the SDH one, is the best way to repair a broken line: it shows the same dialogue word for word. When it shows that a garbled entry is really two speakers on two lines, translate it as two lines, and log it in Source problems.

## References

People translated the references from the same dialogue, so they show what the English means in a scene: the sense of an idiom or of a word with several meanings, whether "you" is one person or several, the gender of who speaks or is spoken about, and tense. Use them to understand the English, and translate the English:

- When a reference leaves something out, adds something or says something else, follow the English. Few matched entries or OCR errors make a reference less reliable.
- Never copy the words, spellings, idioms or sentence structure of a reference.
- Address people as the Register section says, not as a reference does: European Portuguese, Spanish, French and Italian use formal address far more often than Brazilian Portuguese.
- What the Kept unchanged section keeps, such as song lyrics, stays as in the English even when a reference translates it.

## Consistency

The translation is consistent across the whole subtitle, and across the episodes of a series: a character keeps their gender, two characters keep the same form of address between them, a term keeps its translation. A line repeated later, such as in a flashback, a replayed message or an echo, gets the same translation as the first time.

For a TV show, keep these decisions in `translation-decisions.md` in the show folder: each recurring term with its translation, each character's gender, and the form of address between characters. Always read it before translating an episode, and add the new decisions after.

For a movie in a collection (the `<set>` of the nfo), read the reports of the other movies of the collection that were already translated, and keep their names, terms, genders and forms of address.

## Hard gate: review

After writing the file, review the whole translation before reporting. Reviewing only part of the entries, or a sample, does not count. Review from the written file, read next to the English; reviewing from memory of what you wrote does not count. This gate has no exceptions: reporting without having reviewed every entry is a failed task.

Read each entry next to its English, in its scene, and fix every line you would not sign off on:

- the meaning drifted, or a line says less or more than the English;
- the line is literal where the English is idiomatic;
- the wording is bookish, technical or stiff where the English is casual;
- a joke, build-up or repetition in the English is lost;
- an expression sounds invented rather than something a Brazilian says.

## Report

After the review, write `<name>.pob.claude.report.md` next to the video, every time. It has these sections:

- **Source**: the English file used and why it is the canonical one, and the references loaded, if any.
- **Concerns**: what you could not settle without watching the video, such as who a line is addressed to, one entry per concern: the entry number and timestamp, the English line, your translation, the alternative, and what to check in the scene. Never log lines you could have fixed. With no concern, write "None".
- **Decisions**: the choices a later reader could question or would need to repeat: the gender of characters when it was not obvious, the form of address between characters, the translation of recurring terms, and register choices. For an episode, list only what the episode added to `translation-decisions.md`.
- **Source problems**: OCR errors, broken lines, ads and other errors of the English, and what the translation did with each. Leave the section out when there are none.

In the message to the user, give the report path, the number of concerns, and any decision that departs from this skill.
