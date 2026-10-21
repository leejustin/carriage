# Sound sources

Every sound in Carriage is a real recording, released by its recordist under [Creative Commons 0](https://creativecommons.org/publicdomain/zero/1.0/) on Freesound: free to use, change and sell, with no credit required. We credit them anyway.

| In Carriage | Recording | Recordist |
| --- | --- | --- |
| Italian Portable (the free machine): keys, space bar | [Olivetti Lettera 22](https://freesound.org/people/keithpeter/sounds/123344/) | keithpeter |
| Swiss Portable: keys, space bar | [Hermes 3000](https://freesound.org/people/supersupernator/sounds/519622/) | supersupernator |
| Office Electric: keys, space bar; every machine's paper in and out | [IBM Selectric II](https://freesound.org/people/secretmojo/sounds/224012/) | secretmojo |
| American Portable: keys, space bar, bell, carriage return | [Royal Quiet De Luxe](https://freesound.org/people/videog/sounds/240839/) | videog |
| Margin bell and carriage return (Italian and Swiss portables, carriage return on the electric) | [Typewriter bell & carriage reset](https://freesound.org/people/knufds/sounds/345955/) | knufds |
| Office Electric's bell | [Typewriter Bell](https://freesound.org/people/ramsamba/sounds/318687/) | ramsamba |
| Desk sound: rain on the window | [Rain on skylight window, interior](https://freesound.org/people/TRP/sounds/616530/) | TRP |
| Desk sound: fireplace | [(binaural) fire crackling](https://freesound.org/people/yfjesse/sounds/734248/) | yfjesse |

The files in `Carriage/Sounds` are cut from Freesound's high-quality previews by `scripts/sounds/CutSamples.swift`, which picks clean, isolated strokes, trims each to its strike and levels every machine to the same loudness (keys at -24 dBFS over the attack). To cut them again:

```bash
mkdir -p /tmp/carriage-sounds && cd /tmp/carriage-sounds
for id in 123344_1848966 519622_8147189 224012_82274 240839_2688492 345955_191884 318687_1147663 616530_97550 734248_2391840; do
  curl -sfLO "https://cdn.freesound.org/previews/${id:0:3}/$id-hq.mp3"
  afconvert -f WAVE -d LEF32@48000 -c 1 "$id-hq.mp3" "${id}.wav"
done
cd - && swiftc -O scripts/sounds/CutSamples.swift -o /tmp/cut && /tmp/cut /tmp/carriage-sounds Carriage/Sounds
```

`docs/sounds/*.m4a` are listening demos rendered from the app with `-exportSounds`.
