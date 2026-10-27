# Product Hunt launch kit

Everything to paste into Product Hunt for Carriage, plus the plan for launch day.

Website: https://carriage.pages.dev (the video with sound, then the App Store button)
App Store: https://apps.apple.com/us/app/carriage-typewriter/id6825005564

## When

**Tuesday, October 27, 2026, 12:01 a.m. Pacific.** Product Hunt's day runs midnight to midnight Pacific, so going
live at 12:01 gives the full 24 hours. Tuesday to Thursday are the strongest days. It also lands three days before
the unlock goes from $4.99 to $7.99 on October 30, which gives people a real reason to buy that week.

Schedule it a few days ahead (Product Hunt › Submit › schedule for a date), so the page exists and you can share
the "coming soon" link.

## The listing

**Name:** Carriage

**Tagline** (60 max), pick one:
1. A typewriter for your iPhone Duo *(recommended: says what it is to someone who's never heard of it)*
2. Half-fold your iPhone Duo into a little typewriter
3. Your iPhone, as a quiet typewriter that clacks back

**Description** (260 max, 237 used):

> Carriage turns your iPhone Duo into a typewriter. Half-fold it and the page stands up while a full keyboard waits below. Real recorded keys, a bell at the margin, and a carriage you push home yourself. A quiet place to write with intent.

**Topics:** Writing, Productivity, iOS, Design, Minimalism

**Links:** the website as the main link, plus the App Store link. Pricing: Free (with in-app purchase).

**Thumbnail:** `product-hunt/thumbnail.png` (the app icon, 240 x 240).

**Gallery**, in this order (2540 x 1520, Product Hunt's 1270 x 760 at twice the size):

1. `product-hunt/1-typewriter.png`: A typewriter for your iPhone.
2. `product-hunt/2-half-fold.png`: Half-fold it like a laptop.
3. `product-hunt/3-every-iphone.png`: Made for Duo. Lovely on any iPhone.
4. `product-hunt/4-real-typewriters.png`: Real typewriters, recorded.
5. `product-hunt/5-write-late.png`: Write late, in peace.

**Video:** Product Hunt only takes a YouTube link. Upload `docs/previews/launch-film.mp4` to YouTube (unlisted is
fine), titled "Carriage: a typewriter for your iPhone Duo", and paste the link; put it first in the gallery. It's 30
seconds and works muted: captions over the Duo show the real keys, X-OUT, the bell and the carriage pushed home,
then "We scroll more than we read. / Back to one page." `docs/previews/duo-film.mp4` is the plain demo, for social
posts.

## Maker's first comment

Post this the moment it goes live. Edit freely; it should sound like you.

> Hi Product Hunt! 👋
>
> Carriage is a writing app made for the iPhone Duo. Half-fold it like a little laptop, and the page stands on the
> top screen while a full typewriter keyboard sits on the bottom.
>
> Almost everything on my phone is built to keep me scrolling. I wanted one thing on it that asks for less: just a
> page and the keys, nothing else until I'm done. Making it act like a real typewriter turned out to be the best
> way to get there. Each key takes a real press, the bell rings near the margin, and you push the carriage home
> yourself. Typos stay on the page, struck through, so you end up choosing your words before you type them.
>
> What's in it:
> - Four real typewriters, recorded key by key, with a tap you feel on every stroke
> - X-OUT for typos (backspace is in Settings if you'd rather)
> - Rain on the window or a fire in the grate, and a desk lamp that follows the hour
> - Pages saved as you type, synced with iCloud, with a Markdown copy in Files
> - No account, no ads, no subscription, and nothing collected
>
> Your first 5,000 words are free. The unlock is $4.99 through launch week (unlimited words and every machine,
> forever), then $7.99 from October 30.
>
> It runs on any iPhone, but it's at its best half-folded on a Duo. I'd love to hear what you'd write on it, and
> which typewriter I should record next.

## Replies to have ready

- **Is there an Android / iPad / Mac version?** Not yet; it's iPhone only for now, built around the Duo's fold.
  Tell me which you'd want next.
- **Do I need an iPhone Duo?** It's made for the Duo, half-folded like a laptop. It also runs on any iPhone with
  iOS 27, with the page and keys sharing one screen.
- **Is there backspace?** Yes, in Settings. By default Carriage works like a typewriter: X-OUT strikes a typo
  through with x's. When you copy your writing out, you choose the clean text or the struck-through version.
- **Can I get my writing out?** Yes: every page is a Markdown file in Files, plus PDF, Markdown and plain-text
  export, sharing as an image, and sending to Notes.
- **Is it a subscription?** No. One purchase, yours forever.
- **What about privacy?** Nothing is collected. Your writing stays on your phone and in your own iCloud.

## Launch-day checklist

- [ ] Product Hunt page scheduled for Tue Oct 27, 12:01 a.m. PT, with the gallery, thumbnail and video
- [ ] First comment posted the minute it's live
- [ ] Tell friends, colleagues and anyone who's tried it, with the link: "I launched today, I'd love you to
      check it out." Product Hunt penalises asking for upvotes, so don't
- [ ] Reply to every comment through the day
- [ ] Post in the communities below, spaced through the day, not all at once
- [ ] That evening, check the App Store ratings and thank anyone who left one

## Posts for other communities

Read each community's self-promotion rules first; many only allow it in a weekly thread.

**X / Threads / Bluesky**

> I made a typewriter for the iPhone Duo. ⌨️ Half-fold it and the page stands up while the keys wait below. Real
> recorded keys, a bell at the margin, and a carriage you push home yourself.
>
> It's on Product Hunt today: [link]
> (or, after launch day: https://carriage.pages.dev)

Attach `docs/previews/duo-film.mp4` with the sound on: typing ASMR does the work.

**Reddit (Duo and foldables communities):** Title: *I made a typewriter app that uses the Duo's half-fold like a
laptop*. Body: two lines on what it does, the video, the App Store link, and an honest "it's my app, happy to
answer anything." Lead with the fold, since every reader there owns one.

**Reddit (writing communities):** Usually weekly self-promotion threads only. Lead with the focus angle: no
delete, phone goes quiet, keep going.

**Typewriter enthusiasts:** Collectors care about sound and authenticity. Lead with "real recordings of four real
machines" and ask which machine they'd want recorded next. Expect purists; be warm about it.

## Redrawing the images

`swift scripts/StoreScreenshots.swift` from the repo root redraws the gallery and thumbnail along with the store
screenshots.
