# Connection Guide — iOS ↔ TTBDebugPlus

A quick reference for connecting your iOS app to TTBDebugPlus on Mac. For the full step-by-step integration (SPM, sending logs, etc.), see [README.md](README.md). This page is just about **connecting**.

## TL;DR

1. Add `TTBaseUIKit` to your iOS app (SPM).
2. Add 2 keys to your iOS app's Info.plist (see below).
3. Call `TTDebugBridge.shared.start()`.
4. Open **TTBDebugPlus** on your Mac, same Wi-Fi as your iPhone. Done — it connects automatically.

## Setup (once)

**Info.plist** — required, or the SDK can never discover your Mac:
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Required for connecting to TTBDebugPlus on macOS to stream debug logs.</string>
<key>NSBonjourServices</key>
<array>
    <string>_ttbdebug._tcp</string>
</array>
```

**Code** — wrap in `#if DEBUG` so it never ships to production:
```swift
#if DEBUG
TTDebugBridge.shared.start()
#endif
```

That's it. The rest of this page covers what to do when the automatic path doesn't work.

## 4 ways to connect

| Method | When to use | How |
|---|---|---|
| **Bonjour (automatic)** | Default — same Wi-Fi network | Nothing — happens on its own after `start()` |
| **Manual Connect** | Bonjour blocked (corporate Wi-Fi, VPN) | Debug Bridge panel → **Enter IP** → type Mac's IP:port shown in TTBDebugPlus → Connection Health |
| **QR — LAN Pairing** | Quick one-time connect, both devices in the same room | TTBDebugPlus → Connection Health → scan the QR via **TTBaseDebugKit → SCAN QR CODE** (fastest) or **Debug Bridge → Scan QR** |
| **QR — Relay Config** *(new)* | Different networks (remote/WFH), or you want it to "just work" every launch without re-typing anything | TTBDebugPlus → Settings → Relay → scan once via **TTBaseDebugKit → SCAN QR CODE** or Debug Bridge → Scan QR. Saved permanently — reconnects automatically on every future launch, even after a rebuild |

Manual Connect and both QR types run **alongside** Bonjour, not instead of it — if more than one path finds a route, all of them stay connected (by design, not a bug).

**Setting the relay via code instead of QR:**
```swift
TTDebugBridge.shared.config.relayHost = "192.168.1.10"
TTDebugBridge.shared.config.relayPort = 51820
```
A relay set this way in code always takes priority over anything previously saved from a QR scan.

## How to tell which channel is active

Open TTBDebugPlus — each device in the sidebar shows a small colored icon:
- 🔵 **Bonjour** — direct local connection
- 🟣 **Relay** — connected through this Mac's own Relay Server
- 🟣 (faded) **Relay (Remote)** — you're viewing a device that's actually connected to a *different* Mac, through your Relay Client

The icon updates automatically if a device switches channels (e.g. it drops Wi-Fi and reconnects via a configured relay).

## Troubleshooting (top 3)

| Symptom | Cause | Fix |
|---|---|---|
| Console shows `NoAuth -65555` | Missing/incorrect Info.plist keys | Add the 2 keys above, delete the app from the device, run again |
| Device never appears in TTBDebugPlus | Not on the same Wi-Fi, or Server isn't running on Mac | Check both are on the same network; check TTBDebugPlus menu bar shows "Server Running" |
| Debug Bridge panel shows **"Permission Denied"** | iOS Local Network permission was denied | Tap **Open Settings** in the panel → enable Local Network → back in app, tap **Reset Connection** |

More detail: `README.md` → Troubleshooting section, or the in-app **Integration Guide** tab in TTBDebugPlus.
