# Installing the iPhone and iPad app on a device

The App Store and TestFlight need the paid Apple Developer Program. Until
then the app goes onto your own iPhone or iPad straight from a Mac, signed
with the free **Personal Team** that every Apple ID has.

## One-time setup

1. **Sign in to Xcode** with your Apple ID: Xcode > Settings > Accounts >
   +, Apple ID. Your Personal Team appears as "Your Name (Personal Team)".
   Its team ID is what the install script takes.
2. **Pair the device**: plug it into the Mac with a cable, unlock it and tap
   **Trust**. After that it also works over Wi-Fi (same network, unlocked).
3. **Developer Mode** (iOS 16+): Settings > Privacy & Security > Developer
   Mode > On. The device restarts; confirm Turn On after it does. The
   switch only appears after the device has been connected to Xcode once.

## Build and install

```sh
tools/ios_device_install.sh <TEAM_ID>              # first available iPhone/iPad
tools/ios_device_install.sh <TEAM_ID> "My iPhone"  # a particular device
```

It runs `xcodegen`, builds the `MangaReaderiOS` scheme in Release with
automatic signing (`-allowProvisioningUpdates` creates the free profile
and registers the device), installs with `xcrun devicectl device install
app` and opens the app.

The first time, iOS may refuse to open it: Settings > General > **VPN &
Device Management** > your Apple ID under Developer App > **Trust**.

## Limits of the free Personal Team

| | Free Personal Team | Paid membership |
| --- | --- | --- |
| How long an install works | **7 days**, then the app won't open until you install it again from the Mac (your data stays) | 1 year (development), 90 days (TestFlight) |
| Devices | Your own, at most 3 apps signed this way per device | Up to 100 devices per type, TestFlight for anyone |
| iCloud sync, App Groups, push | Not available, so iCloud Sync stays off (`MR_ICLOUD_CONTAINER` empty) | Available; see ICLOUD.md |

**Renewing after 7 days:** run the install script again with the device
unlocked. Nothing is lost: settings, servers, logins and progress are kept
because the app is updated in place, not removed.

## Trouble

- *"No Accounts"*: Xcode isn't signed in to an Apple ID (step 1).
- *"unavailable"* in `xcrun devicectl list devices`: unlock the device, keep
  it on the same Wi-Fi as the Mac, or plug it in.
- *"No profiles for 'com.rustedimac.MangaReader'"* with an account signed
  in: the device isn't connected yet, so no profile could be made for it.
- *"The bundle identifier is not available"*: another team owns it. Build
  with a different `PRODUCT_BUNDLE_IDENTIFIER` (for example add `.dev`).
- The app opens and closes straight away: trust the developer (above), or
  the 7-day profile has expired; reinstall.

Servers on your home network: the first time the app connects, iOS asks to
allow **Local Network** access. Allow it, or Settings > Privacy & Security
> Local Network > Manga Reader.
