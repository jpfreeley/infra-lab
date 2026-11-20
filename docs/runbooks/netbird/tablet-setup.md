# New Tablet Setup

Goal: an Android tablet that runs the kiosk app, is reachable over NetBird
with ADB and `scrcpy`, recovers on its own after a reboot, and is checked by
the tablet monitor.

Proven on a Lenovo Tab M9 (TB310FU, Android 13, not rooted) on 2026-11-20.
Other Android 11+ tablets should work the same way; Wireless debugging needs
Android 11 or later.

Time: about 30 minutes for the first one, 15 after that. Steps marked
**Mac** run on your computer; everything else is on the tablet.

## What you need

- The tablet, on the site's Wi-Fi, plugged in.
- The site's Google account (email, password, and access to its 2-step
  code).
- The site's printer and its setup instructions. Each site prints
  differently (Android printing plugin, Bluetooth or USB).
- A Mac already on the NetBird network, in the `admin-macs` group
  ([adding-people.md](adding-people.md)), with the tools below.
- Admin access to the NetBird dashboard (to name the tablet and put it in
  its group).
- The Automate flow file (`.flo`), exported from a working tablet, if you
  have one. If not, build the flow by hand (step 6).

### Mac tools (once per Mac)

```bash
brew install android-platform-tools scrcpy
git clone https://github.com/jpfreeley/infra-lab.git
cd infra-lab/scripts/netbird
```

`adb version` should print 1.0.41 or later.

## 1. Bring the NetBird server up

**Mac**:

```bash
./netbird.sh up 2h
```

Wait for `READY`. If you do not have GitHub access to start it, ask an
operator, or do the setup inside a check-in window (05:20 to 06:15, 11:20
to 12:15, 17:20 to 18:15, 23:20 to 00:15 New York time).

## 2. Tablet basics

1. Finish the Android first-run screens. Connect to the site's Wi-Fi.
2. Install three apps from the Play Store:
   - **NetBird** (publisher NetBird, package `io.netbird.client`)
   - **Automate** (publisher LlamaLab, package `com.llamalab.automate`)
   - **The kiosk app** (Plate Rate, package `com.plateraterestaurantsv2`)
3. Settings > Security > Screen lock: **None**. A PIN or pattern blocks
   unattended restarts and stops the setup script from turning the lock
   screen off.
4. Settings > About tablet: tap **Build number** seven times. This unlocks
   Developer options.
5. Settings > Passwords & accounts > Add account > Google: sign in to the
   site's Google account. This needs the password and the 2-step code, so it
   cannot be done remotely.
6. Connect the site's printer the way that site does it, then print a test
   page from the kiosk app.
7. Open the kiosk app once and log in to the venue, so it shows the order
   screen with the **Live** label.

## 3. NetBird on the tablet

1. Open NetBird. Before connecting, change the server (management URL) to
   `https://netbird.lintwiselabs.com`, then log in with an admin account.
   Use an account with no auto-assigned groups (dashboard > Users > the
   account). With user group propagation on, a peer gets its owner's
   auto-assigned groups, and a tablet must never land in `admin-macs`.
2. In the NetBird app settings: **Force relay** off. With it on, every
   connection goes through the relay in AWS and is slower.
3. Android Settings > Network & internet > VPN > NetBird (gear icon):
   **Always-on VPN** on.
4. **Mac**, NetBird dashboard > Peers > the new tablet:
   - Rename it. Use a short name without spaces, for example
     `siteb-counter`. This also becomes its DNS name
     (`siteb-counter.netbird.selfhosted`).
   - Turn **Login expiration** off. Otherwise the tablet drops off the
     network when its login expires, and nobody is there to log in again.
   - Groups: add **admin-tablets**. Remove any other group (`All` cannot be
     removed and is harmless once the default policy is gone).
5. Write down the tablet's NetBird IP (`100.x.y.z`) from the Peers list.

## 4. First ADB connection (pairing)

1. Settings > System > Developer options > **Wireless debugging**: on.
   If asked "Allow wireless debugging on this network?", tick **Always allow
   on this network** and allow.
2. Tap **Wireless debugging** (the text, not the switch) > **Pair device with
   pairing code**. A code and an `IP address & Port` appear.
3. **Mac**: pair over NetBird, using the tablet's NetBird IP with the pairing
   port shown on screen:

   ```bash
   adb pair <netbird-ip>:<pairing-port> <six-digit-code>
   ```

   On the same Wi-Fi you can use the LAN IP shown on screen instead.
4. **Mac**: connect to the port shown under **IP address & Port** on the
   Wireless debugging screen (a different port from the pairing one):

   ```bash
   adb connect <netbird-ip>:<port>
   adb devices
   ```

   The tablet should be listed as `device`. If the tablet asks to allow this
   computer, tick **Always allow** and allow.

## 5. Run the setup script

**Mac**:

```bash
ADB_SERIAL=<netbird-ip>:<port> ./tablet-setup.sh apply
```

It sets, and then checks:

- Automate permissions: write secure settings (keeps Wireless debugging on),
  notifications, display over other apps (to start the kiosk app from the
  background), all-files access (event log) and usage access (which app is
  in front).
- Battery optimization off for Automate, the kiosk app and NetBird.
- Stay awake while charging.
- Lock screen off.
- Auto-rotate on.
- Wireless debugging on, then ADB on TCP port 5555.

Fix anything marked `[MISSING]`, then run it again. It is safe to repeat.
After it switches to 5555, use `<netbird-ip>:5555` from then on:

```bash
ADB_SERIAL=<netbird-ip>:5555 ./tablet-setup.sh check
```

The `[info]` lines list print plugins, paired Bluetooth devices and USB
devices. You need them for the printer rule in step 8.

## 6. Automate flow

### If you have the `.flo` file

1. Copy it to the tablet (Drive, email to the site account, or
   `adb push flow.flo /sdcard/Download/`).
2. Automate > menu > **Import**, pick the file. Or open the file from the
   Files app with Automate.
3. Open the flow and tap **Start**. The kiosk app opens once. That is
   expected.
4. Automate > menu > Settings: **Run on system startup** on.
5. If Automate asks for any permission, allow it.

Keep the `.flo` file private. Do not upload it to the Automate community.

### If you build it by hand

Automate resumes a flow where it stopped when the tablet restarts. It does
not start again from the top. So the flow never ends: it is three loops
that run side by side, and the first loop detects a new boot by comparing
the boot counter with the value it saw last.

Every "log" step below is a **File write** block:

- File: `/sdcard/Documents/tablet-events.log`
- Append: on
- Content (fx expression), for example:
  `dateFormat(Now, "yyyy-MM-dd HH:mm:ss") ++ "|power|unplugged\n"`

The format is `date time|kind|detail`, one event per line. The monitor shows
the last 24 hours of it on the tablet's card.

**Start:** Flow beginning, then two **Fork** blocks, so that loops B and C
start next to loop A.

**Loop A (every 60 seconds: boot, self-repair, Wireless debugging):**

1. **Delay** 60 seconds.
2. **System setting get**: category Global, name `boot_count`, output
   variable `bootNow`.
3. **Expression true?** `bootNow != lastBoot`. If yes:
   - **App start**: package `com.plateraterestaurantsv2`, activity
     `com.plateraterestaurantsv2.MainActivity`.
   - Log `|boot|` ++ `bootNow`.
   - **Variable set** `lastBoot = bootNow`.
4. Foreground check (the block that tests which app is in front; search the
   block list for "foreground"), package `com.plateraterestaurantsv2`,
   proceed immediately.
   - In front: **Variable set** `away = 0`.
   - Not in front: `away = away + 1`. Then **Expression true?**
     `away >= 5`: start the kiosk app (as in step 3), log
     `|app|restored after 5 min`, set `away = 0`.
5. **System setting set**: Global, `adb_wifi_enabled` = `1`.
6. Connect back to step 1.

Five minutes lets staff use another screen (settings, a print dialog)
before the kiosk app comes back on its own.

**Loop B (power):** **Power source plugged?** with "proceed when changed".
Plugged: log `|power|plugged`. Unplugged: log `|power|unplugged`. Connect
both back to the same block.

**Loop C (Wi-Fi):** **Wi-Fi connected?** with "proceed when changed".
Connected: log `|wifi|back`. Not connected: log `|wifi|lost`. Connect both
back to the same block.

Then do steps 3 to 5 of "If you have the `.flo` file", and export the flow
(open the flow > menu > Share) so the next tablet can import it.

## 7. Add the tablet to the monitor's inventory

The inventory is a JSON document in Secrets Manager (it holds site names, so
it is not in the repo). Someone with AWS access to the NetBird account does
this:

```bash
# Read the current inventory into a local file (never commit it)
aws secretsmanager get-secret-value \
  --secret-id infra-lab-netbird/tablet-monitor/inventory \
  --query SecretString --output text > inventory.json
```

Add an entry to `tablets`:

```json
{
  "name": "siteb-counter",
  "site": "Site B",
  "host": "100.x.y.z",
  "printer": "bluetooth:<part of the printer's Bluetooth name>"
}
```

- `name` and `host` are required. `host` is the NetBird IP.
- `printer` is one of `none`, `bluetooth:<name part>`, `usb:<product part>`
  or `plugin:<print service package>`. Take the value from the `[info]`
  lines of `tablet-setup.sh check`. Wi-Fi printers added through Android
  printing cannot be seen over ADB: use `plugin:<package>` or `none`.
- Optional: `package` (default the Plate Rate package), `live_label`
  (default `Live`), `orders_pattern` (default `(\d+) orders?`),
  `event_log` (default `/sdcard/Documents/tablet-events.log`).

Write it back and restart the monitor (or let the next check-in pick it up,
since the monitor reads the inventory at every start):

```bash
aws secretsmanager put-secret-value \
  --secret-id infra-lab-netbird/tablet-monitor/inventory \
  --secret-string file://inventory.json
rm inventory.json
```

To restart at once while it is running:

```bash
aws ssm send-command --instance-ids <monitor-instance-id> \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["systemctl restart tablet-monitor"]'
```

## 8. Let the monitor's ADB key in

The monitor connects with its own ADB key. A tablet trusts a key only after
someone taps **Allow** on the tablet, so do this while you are with the
tablet.

1. **Mac**: start a check-in so the monitor connects:

   ```bash
   ./netbird.sh checkin
   ```

   Or press **Check now** on the status page ([monitoring.md](monitoring.md)).
   The tablet must be in the inventory first (step 7).
2. On the tablet, an "Allow USB debugging?" dialog appears with an RSA key
   fingerprint. Tick **Always allow from this computer** and tap **Allow**.

If the dialog never appears, the monitor's key may already be trusted (for
example, the tablet was paired from the Mac whose key the monitor uses).

The same dialog appears the first time any other Mac connects to the tablet
on port 5555. An operator who already has `scrcpy` open on the tablet can
tap **Allow** remotely.

## 9. Verify

**Mac**:

```bash
TABLET_HOST=<netbird-ip> ./tablet-adb.sh
ADB_SERIAL=<netbird-ip>:5555 ./tablet-setup.sh check
adb -s <netbird-ip>:5555 reboot
```

Wait about 3 minutes, then:

```bash
TABLET_HOST=<netbird-ip> ./tablet-adb.sh
adb -s <netbird-ip>:5555 shell dumpsys activity activities | grep topResumedActivity
```

Pass: ADB connects without anyone touching the tablet, and the top activity
is `com.plateraterestaurantsv2/.MainActivity`. The reboot test took about 2
minutes 40 seconds end to end.

Then run `./netbird.sh checkin` and confirm the tablet is green.

Daily use:

```bash
TABLET_HOST=<netbird-ip> ./tablet-adb.sh scrcpy
```

## What the scripts cannot check

`tablet-setup.sh check` cannot see these over ADB. Check them by eye:

- The Automate flow is imported and running, and "Run on system startup" is
  on.
- NetBird Always-on VPN is on, and Force relay is off.
- Wireless debugging "Always allow on this network" was accepted.
- A Wi-Fi printer actually prints.
- The Google account is signed in and healthy (the script sees only that an
  account exists, not whether it needs a new password).
