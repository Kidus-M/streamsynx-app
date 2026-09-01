# StreamSynx (mobile)

The Flutter client for Android and iOS. Same catalogue, same account and the same
design tokens as the website and the TV app.

## What changed in 2.2

**The player is a mode, not a page.** It used to be pushed onto the active tab's
own navigator, so the bottom bar sat over the video and the source sheet was
trapped inside the space left above it — which is why the servers could not be
picked. It opens on the root navigator now (`PlayerRoute`), full screen, with the
server picker in the top bar under its own name.

**It behaves like a phone player.** Double-tap either half to skip, hold for 2x,
drag the scrub bar (buffered range and all), lock the screen against stray taps,
zoom to fill, change speed, and switch episode without leaving the video.

**It gets to a stream more often.** The resolver hooks `fetch`, `XHR` and
`<video>.src` from inside the page as well as watching its requests, which is the
only signal iOS gives at all; it follows a provider's own redirect to a host it
has moved to; and if one provider will not hand over a stream the next is tried
automatically instead of leaving a spinner.

**Sharing sends a link.** See below.

## What changed in 2.0

**There is a player.** Before this, pressing Play handed the viewer to their
browser at `streamsynx.vercel.app/watch?...`, where the embedded providers served
their own advertising with nothing filtering it. Now playback happens in the app.

**The design is rebuilt** on the tokens in `lib/theme/`, mirroring
`stream-sync/tailwind.config.js`. Inter is bundled rather than fetched at runtime.

**Buddies works.** See below.

## How playback works

TMDB provides metadata only, so the video comes from somewhere else — the same
embed providers the website uses. Those pages carry pop-unders and full-screen
interstitials, and filtering a hostile page while it is on screen is a losing
game: one interstitial that gets through owns the whole app.

So the page is never shown. `lib/player/stream_resolver.dart` loads it in a
headless WebView purely as a resolver, watches the requests it makes, picks out
the media manifest, and throws the page away. `video_player` then plays that URL
directly — ExoPlayer on Android, AVPlayer on iOS — with the Referer and user agent
the origin expects.

If resolution fails, the provider page is shown as a fallback with `AdBlock`
filtering it. The chrome says which path you are on: **Ad-free** for native
playback, **Ads filtered** for the fallback.

## The buddies bug

The previous build *read* the friend list from `friends/{uid}.friends` but *wrote*
accepted friends to `users/{uid}.friendUids`. Nothing read that field, so
accepting a request appeared to do nothing and the friend never appeared on
either device.

`lib/data/buddies_repo.dart` now owns the schema, and it is the website's:

| Document | Shape |
| --- | --- |
| `friends/{uid}` | `{ friends: [uid, ...] }` |
| `friendRequests/{fromUid}_{toUid}` | `{ fromUserId, toUserId, status, createdAt }` |
| `users/{uid}` | `{ username, avatar, email }` |

Accepting writes both friend documents and the request update in one batch, so a
half-applied friendship cannot happen. Requests are deleted rather than marked
rejected, so the sender's button returns to "Add" instead of sitting on a pending
state that can never resolve.

## Shared links

Sharing a title sends one HTTPS link:

```
https://streamsynx.vercel.app/open/<type>/<tmdbId>
```

It used to send a PNG the app rendered on the phone, with the link as a caption.
Hand a messaging app a file and it sends a file: most targets drop the caption,
so a shared title arrived as a picture with nothing to tap. A bare link unfurls
instead — `stream-sync/pages/api/og.jsx` draws a 1200×630 card per title and
`/open` carries the Open Graph tags that point at it.

The story card is still there, as an explicit choice in the share sheet, for the
one place an image is genuinely better: an Instagram or WhatsApp story, where the
link is not tappable and has to be readable instead.

With the app installed, Android hands that verified App Link straight to
`AppShell`, which opens the title. Without it, the visitor lands on the site's
`/open` page, which shows the title and offers the download. Verification uses
`stream-sync/public/.well-known/assetlinks.json`, which must carry the SHA-256 of
whatever key signs the shipped APK.

This replaced Firebase Dynamic Links, which Google shut down.

## Build

```powershell
cd streamsynx
flutter pub get
flutter build apk --release
```

The APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

`.env` supplies `TMDB_API_KEY` and is bundled as an asset.

## Releasing to the website

Copy the APK to `stream-sync/public/downloads/StreamSynx.apk` and update the
version shown on `stream-sync/pages/download/index.jsx`.

Two things decide whether existing users can update in place:

- **`applicationId` must not change.** It is still `com.example.streamsynx`,
  which is Flutter's scaffold default. It is wrong-looking but it is the app's
  identity on every device that already has it, so changing it would ship a
  second, separate app instead of an update.
- **`versionCode` must increase.** It is now driven by the `version:` line in
  `pubspec.yaml` (`2.0.0+2` → versionCode 2), so bumping that one line is enough.
- **The signing key must match.** Release currently uses the local debug
  keystore. An APK signed with a different key will refuse to install over an
  existing one, and would also break App Link verification until
  `assetlinks.json` is updated to the new fingerprint.

## Layout of the source

```
data/     TMDB client, models, Firestore repositories, deep links
theme/    Design tokens and the type scale
player/   Stream resolution, ad filtering, the player screen
screens/  One file per destination, composed from widgets/
widgets/  Poster card, rails, share poster, shared chrome
```
