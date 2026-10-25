# gib-eimza-linux

Sign documents on [e-Arşiv Portal](https://earsivportal.efatura.gov.tr/), such as a *Serbest Meslek Makbuzu*, with your e-imza on Linux.

The portal signs through a small local app from GİB, *EFatura Web Socket*, which it hands you as a `.jnlp` file. On current Ubuntu that file doesn't work. `javaws` crashes on new Java versions and never finishes starting on Java 17, and GİB's signer only works on Java 8 anyway. This project skips `javaws`: it runs GİB's app directly with Java 8 and sets up the smart card stack and TÜBİTAK's AKİS driver for you.

Tested on Ubuntu 26.04 with an ACS ACR40T USB token and an AKİS card from e-imzaTR. Other AKİS cards (E-Tuğra, E-Güven, TÜRKTRUST, Kamu SM) use the same driver and should work, but haven't been tried.

Not affiliated with GİB or TÜBİTAK.

## Setup

```bash
git clone https://github.com/phantom1299/gib-eimza-linux.git
cd gib-eimza-linux
./install.sh
```

Ubuntu Desktop doesn't come with `git`. Install it first with `sudo apt install git`, or download this repository as a ZIP and unpack it.

The installer:

- refreshes the package lists and installs `openjdk-8-jre`, `pcscd`, `libccid`, `pcsc-tools`, `curl` and `unzip` if they're missing. A Java 8 from elsewhere, such as Eclipse Temurin, is used if it's already installed;
- downloads TÜBİTAK's AKİS driver package (Akia 6.8.13), checks its SHA-256 and installs it. It puts `libakisp11.so` in `/usr/lib`, where GİB's app looks for it;
- installs the `gib-eimza` command in `~/.local/bin` and a **GİB e-İmza** entry in your app menu;
- downloads GİB's app, verifies its signatures and runs `gib-eimza check`.

It asks for `sudo` only when something needs installing, so it's safe to re-run.

Keep `openjdk-8-jre` installed. Nothing else on a modern system needs it, so it's easy to remove by accident, and removing it breaks signing.

## Signing a document

1. Plug in your e-imza token. Start **GİB e-İmza** from the app menu, or run `gib-eimza` in a terminal. A small *EFatura İmza Uygulaması* window opens, and your browser opens `https://localhost:8543/` in a new tab. Keep the window open while you use the portal.
2. **First time only:** the browser warns about the certificate of `https://localhost:8543/`. Accept it (Chrome: *Advanced → Proceed to localhost*; Firefox: *Advanced → Accept the Risk and Continue*). It's GİB's self-signed certificate for the local app, and the portal can't reach the app until your browser accepts it. On later starts the tab just shows GİB's page, and you can close it.
3. On the portal, log in with e-İmza. Pick **AKİS** as the smart card processor (*akıllı kart işlemcisi*) and enter your PIN.
4. Create and sign your document as usual. If the portal offers you a `.jnlp` file, you don't need it.

Close the app's window when you're done.

## Updating

Each start checks GİB's server for a newer version of the app and installs it after verifying its signature. `gib-eimza update` does the same without starting the app. If GİB can't be reached, the cached app starts. Jars that GİB no longer lists are deleted after a successful update.

After a `git pull` of this repository, run `./install.sh` again: the `gib-eimza` command is a copy, not a link.

## Checking your setup

```bash
gib-eimza check
```

This checks Java 8, `pcscd`, the AKİS driver and your card, and lists the certificates on the card. It never logs in to the card, so it can't use up PIN attempts. `gib-eimza java` prints the Java 8 that the launcher uses, and `gib-eimza version` its version.

## Troubleshooting

Run `gib-eimza check` first. GİB's app writes its log to `/tmp/EFaturaWebSocketLog/Log_<date>.txt`, not to the terminal.

**"Kullandığınız akıllı kart donanımı için sisteminizde sürücü dosyası bulunamadı."**
The AKİS driver (`/usr/lib/libakisp11.so`) is missing, or you picked a processor other than AKİS. Re-run `./install.sh`.

**"Akıllı kartınızdaki sertifikalara erişilemedi. Lütfen şifrenizi doğru girdiğinizden emin olunuz."**
Either the PIN is wrong, or the app isn't running on Java 8. **Check the log before you try again**, because wrong PINs lock the card. If the log shows `No Constructor for sun.security.pkcs11.SunPKCS11(java.io.InputStream)`, the PIN never reached the card: GİB's app ran on a newer Java. Make sure `openjdk-8-jre` is installed and start the app with `gib-eimza`.

**The portal can't reach the signing app.**
Either the app isn't running, or your browser hasn't accepted the certificate at `https://localhost:8543/`.

**`gib-eimza check` finds no reader or no card.**
Re-plug the token. Then run `pcsc_scan` to see what the smart card service detects.

**"The JNLP from GİB could not be parsed" or "is not signed by a pinned certificate".**
On a network with a login page (hotel, airport), log in to it first; the launcher starts the cached app meanwhile. Otherwise GİB changed its app's format or its signing certificate, and this project needs an update: `git pull`, then `./install.sh` again. See *Security notes* for the certificate pin.

**The app's window is tiny on a HiDPI screen.**
Java 8 doesn't scale its user interface, so the window is small on a 4K screen. It still works.

**Other tools say your PIN is locked.**
The AKİS library reports the PIN as locked (`CKF_USER_PIN_LOCKED`) even when it works, so ignore that flag. If your PIN really is blocked, Akia (TÜBİTAK's card app, installed with the driver; run `Akia`) can unblock it with the PUK from your PIN envelope.

## How it works

`gib-eimza` fetches GİB's JNLP from `https://ebelge.gib.gov.tr/EFaturaWebSocket/` and downloads the jars it lists into `~/.local/share/gib-eimza/app`. On later starts it re-downloads only the jars GİB has changed and removes the jars GİB no longer lists. Every downloaded jar is verified against GİB's pinned signing certificate before it replaces anything; if GİB can't be reached or a download fails verification, the cached app starts. It then runs the app's main class with Java 8 and the JNLP's JVM options. The app serves a WebSocket on `127.0.0.1:8543` for the portal and signs with your card through `libakisp11.so`.

It doesn't use `javaws` because Ubuntu's IcedTea-Web 1.8.8 can't run this app:

- on Java 24 and newer it crashes (`Setting a system-wide Policy object is not supported`);
- it calls Java 9+ APIs, so it can't run on Java 8;
- on Java 17 it re-downloads every jar from GİB for each class it loads, so the app never finishes starting.

On top of that, GİB's signer needs Java 8, because it uses `SunPKCS11(InputStream)`, which Java 9 removed. `gib-eimza` also works around two desktop issues:

- **Ubuntu's Java 8 crash.** Its accessibility bridge crashes Swing apps (`AtkWrapper`), so the launcher passes `-Djavax.accessibility.assistive_technologies=`.
- **Snap terminals.** Terminals of snap apps, such as VS Code, set GTK variables that crash Java. The launcher unsets them.

## Security notes

- GİB's jars come over HTTPS from `ebelge.gib.gov.tr` and run with full permissions, as they would under `javaws`. Every jar is signed by GİB (*Gelir İdaresi Başkanlığı*, with a certificate issued by GlobalSign). `gib-eimza` verifies each downloaded jar with Java's own jar verifier and installs it only if the signer matches a SHA-256 fingerprint pinned in `GIB_SIGNERS` at the top of the script. `javaws` can't validate this chain on Ubuntu, because the system Java trust store has no code-signing roots; the pin sidesteps that.
- GİB's current certificate expires on 2027-08-28. When GİB signs with a new one, the launcher refuses the download, prints the new certificate's name and fingerprint, and starts the cached app. Check the fingerprint yourself (for example with `keytool -printcert -jarfile` on a jar downloaded from GİB) and update `GIB_SIGNERS`, or set `GIB_EIMZA_SIGNER=<fingerprint>` in your environment to accept it on your machine.
- The Akia package is pinned by SHA-256. Its install scripts run as root, as for any package.
- The signing app listens only on `127.0.0.1`, and only while it's running.

## Updating the AKİS driver

New installs get the Akia version pinned in `install.sh`. When TÜBİTAK publishes a newer one on [akiskart.bilgem.tubitak.gov.tr](https://akiskart.bilgem.tubitak.gov.tr/destek/), download it and run `sudo apt install ./Akia_linux_<version>.deb`. To make new installs use it, update `AKIA_URL` and `AKIA_SHA256` in `install.sh`. You can also install a copy you downloaded yourself with `AKIA_DEB=/path/to/Akia_linux_<version>.deb ./install.sh`.

## Other distributions

`install.sh` needs `apt` and a Java 8 that it can install or find.

**Debian** doesn't ship `openjdk-8` in its stable releases. Install Eclipse Temurin 8 from [Adoptium's apt repository](https://adoptium.net/installation/linux/) (package `temurin-8-jre`), then run `./install.sh`. The launcher finds Temurin under `/usr/lib/jvm/temurin-8-*`.

On other distributions, set up the same pieces by hand:

- Java 8;
- `pcscd` and the CCID driver;
- `libakisp11.so` from the Akia `.deb`, copied to `/usr/lib`. On Arch, the AUR package `akia` does this.

Then copy `gib-eimza` onto your `PATH`. It needs `curl`, `ss` (iproute2) and `flock` (util-linux). The launcher looks for Java 8 under `/usr/lib/jvm` (OpenJDK, Temurin, Zulu, Corretto) and in `JAVA_HOME`. If `gib-eimza java` doesn't find yours, run it as `JAVA=/path/to/java8/bin/java gib-eimza`.

## Uninstalling

```bash
./uninstall.sh
```

This removes the launcher, the menu entry and the downloaded app. It then prints the commands for removing the system packages, and for the files that GİB's signer and the AKİS driver leave in your home folder (`~/cssign.properties`, `~/certificates`, `~/crls`, `~/trustedRoots`, `~/Akisp11`).

## License

MIT, see `LICENSE`. GİB's signing app and TÜBİTAK's Akia package are proprietary. This project downloads them from their publishers at install time and doesn't redistribute them.
