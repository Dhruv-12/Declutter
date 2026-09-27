# Declutter

An iPhone app that frees up storage by finding duplicate and similar photos, screenshots, large
videos, blurry shots and duplicate contacts, and removing them safely after you review them.
Everything happens on the device. Nothing is uploaded, and nothing is deleted without your approval.

Supports iPhone, iOS 17.0 and later. Built in SwiftUI.

## Features

**Clean up**

- **Storage dashboard.** How much you can free, in large type, with a storage bar showing used
  space, space you can free, space already freed and free space. One row per category with its
  count and size.
- **Similar photos.** Groups near-identical shots and exact duplicates, marks the best photo in each
  set, and selects the rest once you've seen them. You can keep a different photo instead, and
  choose how close a match has to be.
- **Screenshots.** Every screenshot in one grid, grouped by month, with select all.
- **Large videos.** Every video, largest first, with a preview player and a size filter.
- **Duplicate contacts.** Finds contacts with the same name, phone number or email. Merge them
  (with an editable preview: choose the name, the numbers and emails to keep, and the photo), merge
  all at once, or delete.

**Tools**

- **Swipe to sort.** A card stack of your photos: swipe left to mark for deletion, right to keep,
  with undo.
- **Blurry photos.** Out-of-focus photos, blurriest first, with three sensitivity levels.
- **Compress videos.** Makes a smaller copy (High quality, Balanced or Smallest), saves it to Photos
  next to the original, then offers to delete the original.
- **Home Screen widget.** Small and medium widgets showing used and free space.
- **Private vault.** Photos encrypted on the iPhone and locked with Face ID and a PIN.

**Everywhere**

- A review screen before anything is deleted, then a "space freed" summary.
- File sizes that match the Photos app.
- Light and dark mode, VoiceOver labels, Reduce Motion support, haptics, and an animated intro.

## How the scan works

Similar photos is the heavy part: a big library has tens of thousands of photos, and comparing
every photo with every other one would take far too long. Declutter avoids that:

1. **Only nearby photos are compared.** Similar shots are almost always taken close together, so
   each photo is compared with up to 6 photos taken just before it, within 2 minutes. The work
   grows in step with the size of the library, not with its square.
2. **Vision decides what's similar.** Each candidate gets an Apple Vision feature print, computed on
   a small cached thumbnail. Two photos are similar when their prints are close (0.30, 0.45 or 0.60,
   depending on the match setting).
3. **Exact duplicates are found anywhere.** Every photo also gets a 64-bit image fingerprint (a
   difference hash). Photos with the same fingerprint and the same dimensions are compared with
   Vision, so a photo saved twice, months apart, is still caught.
4. **It runs in the background.** The work is spread across every CPU core at low priority, so the
   app stays smooth, and it starts only after the launch intro.
5. **The best photo is picked on purpose.** Favourites always win. Otherwise sharpness counts most,
   then face quality (when the set has faces), then resolution.

Blurry photos uses the same edge measurement (a Laplacian) but scores each photo by its strongest
edges, so a crisp photo that is mostly sky isn't mistaken for a blurry one.

Sizes come from the current version of each photo or video: the edited file if there is one,
otherwise the original, plus the video of a Live Photo. That's what the Photos app shows.

## Safety

- **Nothing is deleted without the review screen.** Every delete, from every screen, goes through
  one review screen that lists exactly what will go and how much space it frees. You can tap
  anything there to keep it. Merging contacts, which removes the duplicates it combines, has its
  own preview of the merged result and a confirmation instead.
- **iOS asks too.** Photo deletes also show Apple's own confirmation. Declining it deletes nothing.
- **Deleted photos can be recovered.** They go to Recently Deleted in Photos for 30 days, and the
  app says so.
- **Permanent deletes get an extra warning.** Contacts can't be recovered, so deleting or merging
  them needs one more confirmation.
- **Nothing is pre-selected that you haven't seen.** Similar photos are only pre-selected once
  their results are on screen. Contacts are never pre-selected.
- **Merges never quietly drop data.** Every field apps are allowed to read is copied, and the
  preview shows the result first. Notes can't be read by apps, and the preview says so.
- **Originals stay until you choose.** Compressing a video, or moving a photo into the vault, never
  deletes the original. You're offered a review afterwards, and only for originals that were copied
  successfully.

## Privacy

- **All scanning happens on the iPhone.** The app makes no network requests of its own. Photos
  stored only in iCloud are downloaded by iOS from your own iCloud library when needed, as the
  Photos app would.
- **Each permission is asked for with a clear reason.** "Denied" and "limited access" are handled,
  including adding more photos or contacts from inside the app.
- **The private vault stays on this iPhone.**
  - **Encryption:** each photo is encrypted with AES-GCM using a 256-bit key made on the iPhone.
  - **The key:** kept in the Keychain for this device only, so it's never synced or backed up.
  - **The files:** stored with complete file protection and left out of backups.
  - **The PIN:** stored only as a salted PBKDF2 hash, and 5 wrong tries lock the vault for 30 seconds.
  - **Locking:** the vault locks when the app goes to the background, and is hidden from the app switcher.
- **The test library is generated.** The test photos, screenshots, videos and contacts are generated
  by `Scripts/generate-test-media.swift` when the tests run. No personal photos or contacts are in
  this repository.

## What I skipped, and why

- **Payments, subscriptions and paywalls.** Out of scope for the brief, so everything is free.
- **Email cleanup, and other apps' caches and junk files.** Out of scope, and iOS doesn't allow
  clearing other apps' data, so the app doesn't promise it.
- **iPad, Mac and Watch versions.** iPhone only, as the brief asked.
- **Calendar cleanup.** I built it, but its UI tests couldn't be made to pass on the simulator
  (calendar permissions set by the simulator tools didn't reach the app). Rather than ship something
  I couldn't verify, I removed it. It's still in the git history.
- **A TestFlight build.** TestFlight needs a paid Apple Developer Program membership, which I don't
  have. The app runs on a real iPhone through Xcode with a free account.
- **Similar-photo tests on the simulator.** The iOS Simulator can't run Vision's image feature
  prints, so the tests that need them are skipped there with a note. They run on a real iPhone,
  where I tested similar photos by hand.

## How I used Claude Code

I built Declutter with Claude Code, working one feature at a time: it wrote the code, built it,
committed it, and gave me steps to test on my iPhone before moving on. Every feature was checked on
my own phone with my real library, and several real bugs were found that way:

- **File sizes.** They were exaggerated because every file behind a photo was added up.
- **Scans that silently found nothing.** A Photos query that matched nothing left the similar and
  blurry scans with no photos.
- **Vault errors.** Adding photos stored in iCloud to the vault failed, with no reason given.

Along the way it also:

- wrote the unit and UI tests, a script that generates a test photo library, and a runner that
  tests each scenario on a freshly erased simulator
- measured launch speed and cut the intro's time to its first frame
- reviewed the app against the brief and fixed unsafe spots (for example, pre-selecting photos
  I'd never looked at, and contact merges that lost details).

When something only failed on the simulator, or couldn't be tested there, it said so rather than
hiding it.

## Build and run

You need a Mac with **Xcode 27** or later and an iPhone on **iOS 17** or later. A free Apple
account is enough to run on your own iPhone.

1. Clone the repository and open `Declutter.xcodeproj`.
2. Select the **Declutter** project, then the **Declutter** target, then **Signing & Capabilities**.
   Under **Team**, select your own team.
3. Do the same for the **DeclutterWidgetExtension** target.
4. If Xcode says the bundle identifier is taken, change both identifiers to something of your own:
   the app's (`com.dhruv.Declutter`) and the widget's, which must start with the app's
   (`com.dhruv.Declutter.DeclutterWidget`).
5. Plug in your iPhone, choose it as the run destination, and press **Run** (⌘R).
6. The first time, on the iPhone, trust the developer under **Settings › General › VPN & Device
   Management**, and turn on **Developer Mode** if asked.

The simulator works too, but it comes with almost no photos, and it can't find similar photos (see
above). A real library is where the app is meant to be seen.

### Tests

```bash
Scripts/run-tests.sh
```

This needs an iOS Simulator runtime (install one with `xcodebuild -downloadPlatform iOS`). The script
creates a simulator, and for each scenario it:

- erases the simulator
- generates and loads a test library (`xcrun simctl addmedia`)
- sets permissions (`xcrun simctl privacy`)
- runs that scenario's tests.

The scenarios are: unit tests, UI flows, permissions (first launch, denied, granted), an empty
library, a library with no duplicates, and a 1,530-photo library. To run only some of them:

```bash
PHASES="unit ui" Scripts/run-tests.sh
```

Results go to `build/tests/`.
