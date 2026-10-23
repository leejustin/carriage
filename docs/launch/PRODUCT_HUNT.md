# Product Hunt launch kit

Everything to paste into Product Hunt for Carriage, plus the plan for launch day.

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
1. A real-sounding typewriter for your iPhone *(recommended: says what it is to someone who's never heard of it)*
2. Half-fold your iPhone Duo into a little typewriter
3. Your iPhone, as a quiet typewriter that clacks back

**Description** (260 max, 240 used):

> Carriage turns your iPhone into a typewriter. Half-fold an iPhone Duo and the page stands up while a full
> typewriter keyboard waits below. Real recorded clacks, a bell at the margin, no delete key. Your phone goes
> quiet; the words come out.

**Topics:** Writing, Productivity, iOS, Design, Minimalism

**Links:** the App Store link above. Pricing: Free (with in-app purchase).

**Thumbnail:** `product-hunt/thumbnail.png` (the app icon, 240 x 240).

**Gallery**, in this order (2540 x 1520, Product Hunt's 1270 x 760 at twice the size):

1. `product-hunt/1-typewriter.png`: A typewriter for your iPhone.
2. `product-hunt/2-half-fold.png`: Half-fold it like a laptop.
3. `product-hunt/3-every-iphone.png`: Made for Duo. Lovely on any iPhone.
4. `product-hunt/4-real-typewriters.png`: Real typewriters, recorded.
5. `product-hunt/5-write-late.png`: Write late, in peace.

**Video:** Product Hunt only takes a YouTube link. Upload `docs/previews/iphone.mp4` to YouTube (unlisted is fine),
titled "Carriage: a typewriter for your iPhone", and paste the link. It's 26 seconds of typing with the real sounds;
put it first in the gallery if you add it.

## Maker's first comment

Post this the moment it goes live. Edit freely; it should sound like you.

> Hi Product Hunt! 👋
>
> I made Carriage because every writing app on my phone was one swipe away from everything that kills writing.
> I wanted the opposite: something that feels like sitting down at a typewriter.
>
> So Carriage is a typewriter. Every key is a real recording of a real machine, the bell rings near the margin,
> and the keys stop at the edge of the page until you send the carriage home. There's no delete, just X-OUT, like
> the real thing (backspace and line wrap are a setting away if you want them). Open it and your iPhone goes quiet.
>
> It was made for the iPhone Duo: half-fold it like a little laptop and the page stands up on top while a full
> typewriter keyboard sits on the bottom half. On any other iPhone, the page and keys share one screen.
>
> A few things I'm proud of:
> - Four real machines to choose from, recorded key by key, with haptics you feel on every stroke
> - Rain on the window or a fire in the grate, and a desk lamp that follows the time of day
> - Everything saves as you type, syncs with iCloud, and keeps a plain Markdown copy in Files
> - No account, no ads, no subscription, and nothing collected
>
> Your first 5,000 words are free. The unlock (unlimited words and every machine, forever) is $4.99 through
> launch week, then $7.99 from October 30.
>
> I'd love to hear what you'd write on it, and what would make it feel even more like the real thing.

## Replies to have ready

- **Is there an Android / iPad / Mac version?** Not yet; it's iPhone only for now, built around the Duo's fold.
  Tell me which you'd want next.
- **Do I need an iPhone Duo?** No. It works on any iPhone running iOS 27; the Duo gets the half-folded laptop
  layout.
- **Why no delete key?** It's the point: on a typewriter you keep going. X-OUT strikes through with an x, and
  copying out gives you clean text or the struck-through version, your choice. Backspace is one setting away.
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

> I made a typewriter for your iPhone. ⌨️
>
> Half-fold an iPhone Duo and the page stands up while a full typewriter sits below. Real recorded clacks, a bell
> at the margin, no delete key.
>
> It's on Product Hunt today: [link]

Attach `docs/previews/iphone.mp4` with the sound on: typing ASMR does the work.

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
