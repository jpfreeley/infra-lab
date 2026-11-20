# Adding a Person to the NetBird Network

Gives a person's Mac access to the tablets (ADB, `scrcpy`) and to the
monitor's status page. The NetBird server uses its embedded identity
provider, so people get local NetBird accounts. No Google or Microsoft login
is involved.

Checked against the NetBird docs (local users, user roles, groups) on
2026-11-20, for NetBird v0.83.

## What access means here

| Access | Gives | How |
| --- | --- | --- |
| NetBird account, Mac in `admin-macs` | reach tablets and the status page while the server is up | this page |
| ADB trust on each tablet | `adb` and `scrcpy` to that tablet | one tap of "Allow" per tablet, per Mac |
| GitHub write on the repo (optional) | start the server any time (`netbird.sh up`), run `checkin` | [github-setup.md](github-setup.md) |
| AWS access to the NetBird account (optional) | edit the tablet inventory, read logs | AWS IAM Identity Center |

Without GitHub access a person can still use everything during the four
daily check-in windows (05:20 to 06:15, 11:20 to 12:15, 17:20 to 18:15,
23:20 to 00:15 New York time), or after an operator runs `netbird.sh up`.

## Part A: the admin invites the person

The server must be up (`netbird.sh up 1h`), both for you and for the person
accepting the invite.

1. Check the group setting once: NetBird dashboard > **Settings** >
   **Groups** > **Enable user group propagation** is on. With it on, a
   user's auto-assigned groups are applied to every peer the user adds, so
   their Mac lands in `admin-macs` with no further work. (If it is off, do
   step 6 by hand for each new peer.)
2. Dashboard > **Users** > **Add User** > **Invite User**.
3. Fill in:
   - **Name** and **Email**. The email is the login name. NetBird does not
     send email here; you send the link yourself.
   - **Role**: **User** for people who only connect to tablets. A User sees
     only their own peers and the peers they are allowed to reach. Pick
     **Admin** only for people who will add tablets, rename peers or manage
     policies.
   - **Expires in**: the default 3 days is fine.
   - **Auto-assigned groups**: `admin-macs`.
4. **Create Invite Link**, then **Copy & Close**.
5. Send the link to the person privately (a direct message, not a shared
   channel). Anyone with the link can claim the account until it expires.
   Lost or expired links: Users > **Show Invites** > **Regenerate** (the old
   link stops working).
6. After the person connects (Part B), check dashboard > **Peers**: their Mac
   is listed with the group `admin-macs`. Rename it if the name is unclear.
   Leave login expiration on for people's computers.

The alternative, **Create User**, generates a password that is shown once.
Use it only when you cannot send a link; you then have to pass the password
on securely.

## Part B: the person sets up their Mac

1. Accept the invite: open the link, set a password (a long one; a password
   manager is best), and log in once.
2. Install the NetBird app for macOS. Follow docs.netbird.io > Get started >
   Install > macOS. NetBird runs in the menu bar.
3. On first launch, choose **Self-hosted** and enter the management URL
   `https://netbird.lintwiselabs.com`. Connect. A browser window opens; log
   in with the invite account.

   From the command line instead:

   ```bash
   netbird up --management-url https://netbird.lintwiselabs.com:443
   ```

4. Check:

   ```bash
   netbird status
   ```

   `Management: Connected` and `Signal: Connected`. Tablets are listed as
   peers. They show `Idle` until you send them traffic; that is normal
   (NetBird opens tunnels on demand).
5. Install the tools:

   ```bash
   brew install android-platform-tools scrcpy
   git clone https://github.com/jpfreeley/infra-lab.git
   ```

6. Connect to a tablet. The NetBird IPs are in the dashboard (Peers) and on
   the status page.

   ```bash
   cd infra-lab/scripts/netbird
   TABLET_HOST=<tablet-netbird-ip> ./tablet-adb.sh scrcpy
   ```

7. The first time, the tablet shows "Allow USB debugging?" with your Mac's
   key fingerprint, and `adb` reports the device as `unauthorized`.
   Someone has to tick **Always allow from this computer** and tap
   **Allow** on the tablet: either a person at the site, or an operator who
   already has `scrcpy` open on that tablet. Then run the command again.
   Repeat once per tablet.

## Removing a person

1. Dashboard > **Users**: delete the user (or change the role to remove
   admin rights).
2. Dashboard > **Peers**: delete every peer that person owned. The NetBird
   docs do not say whether deleting a user removes their peers, so do it
   explicitly and confirm the list.
3. GitHub: remove them as a collaborator, if they were one.
4. ADB trust stays on the tablets, but it is only usable from inside the
   NetBird network, which they no longer have. To remove it anyway: on the
   tablet, Developer options > **Revoke USB debugging authorizations**.
   This removes every key, including the monitor's and the other
   operators'. Afterwards, let each one back in (each needs one tap of
   "Allow", see [tablet-setup.md](tablet-setup.md) step 8).

## Troubleshooting

| Symptom | Cause, fix |
| --- | --- |
| Invite link page does not load | Server is down. `netbird.sh status`, then `netbird.sh up 1h`. |
| Mac connected, but no tablets listed | The Mac is not in `admin-macs`. Dashboard > Peers > the Mac > Groups. |
| `adb` says `unauthorized` | Tap Allow on the tablet (Part B step 7). |
| `netbird status` shows Management disconnected after the server was down | The client backs off while the server is away. Wait a few minutes, or run `netbird down && netbird up`. |
| Name lookups fail on the Mac right after the server comes back | macOS cached "no such name" while the server was down: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`. |
| Session expired | NetBird asks you to log in again after the login expiration period. Log in from the menu bar app. |
