# Launch film

`docs/previews/launch-film.mp4`: 30 seconds, 1920 x 1080, made for Product Hunt's muted autoplay and YouTube.

1. The half-folded Duo, easing in as it types: "A typewriter for your iPhone Duo."
2. Close on the keys: "Real recorded keys."
3. A typo struck through: "X-OUT, like the real thing."
4. The bell near the margin, then the carriage pushed home by hand.
5. "We scroll more than we read." / "Back to one page." over Dreamina shots of an old typewriter, faded back behind
   the words (`clips/`).
6. "Carriage" typed in close-up, then the end card.

Shots 1–4 come from one Duo recording: `docs/previews/duo-film.mp4` (the half-folded Duo) and `duo-raw.mp4` (the
same take's raw screen, for close-ups; `duo-raw-offset.txt` lines the two up). Every letter lands on the frame its
recorded key sounds. Under it all, Satie's Gymnopédie No. 1.

The cut is `scripts/film/timeline.txt`. Make it again with:

    TAGLINE="Write with intent." scripts/film/make.sh docs/film/clips docs/film/music/gymnopedie-1-alciatore.ogg

## Music

Both recordings are public domain, from Wikimedia Commons; no credit is required.

- `music/gymnopedie-1-alciatore.ogg`: Erik Satie, Gymnopédie No. 1, piano, Robin Alciatore.
  https://commons.wikimedia.org/wiki/File:Erik_Satie_-_gymnopedies_-_la_1_ere._lent_et_douloureux.ogg
- `music/gymnopedie-1-laucke.flac`: the same piece performed by Michael Laucke.
  https://commons.wikimedia.org/wiki/File:Satie_Gymnopedie_No_1_performed_by_Michael_Laucke.flac
