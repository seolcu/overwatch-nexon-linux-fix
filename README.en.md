# Overwatch (Nexon KR) on Linux — fixing Blizzard error `0xE01300B0`

Since Overwatch's Korean service moved to **Nexon** on 2026-08-12, the game fails to
launch under **Proton/Wine on Linux** with Blizzard error **`0xE01300B0`**.
This repository contains a working fix and a full root-cause analysis.

[한국어](README.md) · **English**

## Symptoms

- Launching Overwatch from Battle.net → a black window appears briefly, then closes
- Two error dialogs follow, in this order (the underlying exception is `0xC06D007E`)
- Reinstalling, Scan and Repair, switching Proton builds, clearing shader caches —
  **all have no effect**
- The game worked in the same setup right up until the Nexon transfer

**Dialog 1** — titled `Overwatch`

```
Overwatch has encountered a critical error during startup.
Please reinstall the game and try again.
```

**Dialog 2** — titled `Overwatch`, quoted from the Korean client:

```
설치한 파일에 문제가 있습니다. 문제가 지속되면 게임을 다시 설치해 주십시오.
(0xE01300B0)

블리자드와 이 문제에 대해 논의할 때 아래의 신고 ID를 사용하십시오.
```

Translated: *"There is a problem with the installed files. Please reinstall the game
if the problem persists. (0xE01300B0) — Use the report ID below when discussing this
issue with Blizzard."* The exact English-client wording may differ; the code is what
matters.

If the code in parentheses is not `0xE01300B0`, the cause may be a different one.

If your symptoms differ (you can log in but matchmaking fails, graphics glitches,
etc.), this is not your problem.

## Requirements

```bash
sudo apt install bubblewrap openssl python3     # Ubuntu / Debian
sudo dnf install bubblewrap openssl python3     # Fedora
sudo pacman -S bubblewrap openssl python        # Arch
sudo zypper install bubblewrap openssl python3  # openSUSE
```

`bubblewrap` (`bwrap`) usually ships with Steam already.

## Step 1 — install

```bash
git clone https://github.com/seolcu/overwatch-nexon-linux-fix.git
cd overwatch-nexon-linux-fix
chmod +x overwatch-nexon-linux-fix.sh
./overwatch-nexon-linux-fix.sh install
```

`install` does two things:

1. **Locates the Overwatch Wine prefix.** It searches the usual places for Steam
   (non-Steam shortcuts), Lutris, Bottles, Heroic and plain wine, looking for the
   prefix that contains `gamescale64.dll`.
2. **Installs the cross-signed certificate into the prefix and builds a trust list.**
   The prefix registry is backed up to `system.reg.bak-overwatch-nexon-fix` first.
   The trust list is built under `~/.local/share/overwatch-nexon-fix/certs`; the
   system trust store is never touched.

On success it prints the prefix it found along with launcher-specific instructions.

### If the prefix is not found

If your prefix lives outside your home directory (an external drive, say) or in an
unusual place, point at it directly.

```bash
# find it first
find ~ / -name gamescale64.dll 2>/dev/null

# walk up from that path; the prefix is the directory containing system.reg
OW_PREFIX=/path/to/prefix ./overwatch-nexon-linux-fix.sh install
```

If several prefixes are found, the script lists them and stops so you can pick one
with `OW_PREFIX`.

## Step 2 — add the launch wrapper to your launcher

Installing the certificate is not enough on its own. **The game has to be launched
through the wrapper every time**, because the trust list swap only applies to the
launched process — which is exactly what keeps your system untouched.

The wrapper command is the same for every launcher:

```
/full/path/overwatch-nexon-linux-fix.sh run <original launch command>
```

Get the full path from the `install` output or from
`./overwatch-nexon-linux-fix.sh status`. Find your launcher below.

### Steam, as a non-Steam game ✅ verified

Right-click the Battle.net shortcut → **Properties** → **Launch Options**:

```
/full/path/overwatch-nexon-linux-fix.sh run %command%
```

Do not omit `%command%`.

### Lutris

Right-click the game → **Configure** → **System options** → **Command prefix**:

```
/full/path/overwatch-nexon-linux-fix.sh run
```

Stop after `run` — Lutris appends the actual command itself. (If you don't see
System options, enable the **Advanced** toggle at the bottom right.)

### Heroic Games Launcher

Game **Settings** → **Advanced** → **Wrapper command**:

```
/full/path/overwatch-nexon-linux-fix.sh run
```

### Bottles

Bottles has no wrapper command field, so launch from a terminal:

```bash
/full/path/overwatch-nexon-linux-fix.sh run \
  bottles-cli run -b "BottleName" -p "Battle.net"

# Flatpak build
/full/path/overwatch-nexon-linux-fix.sh run \
  flatpak run --command=bottles-cli com.usebottles.bottles run -b "BottleName" -p "Battle.net"
```

Wrap that in a `.desktop` file or a shell alias if you don't want to type it each
time. If you'd rather not use a terminal at all, see the **alternative** below.

### Plain wine

Just prefix whatever you normally run:

```bash
/full/path/overwatch-nexon-linux-fix.sh run \
  env WINEPREFIX=~/.wine wine "C:\\Program Files (x86)\\Battle.net\\Battle.net Launcher.exe"
```

### Alternative — when you can't use a wrapper

If you only use Bottles through its GUI, or a Flatpak sandbox blocks nested `bwrap`,
you can remove the self-signed certificate from the system trust store instead.

> ⚠️ **Two caveats**
> - **This affects the whole system.** It changes TLS validation for browsers and
>   everything else. Most servers send the cross-certificate along with their chain,
>   so in practice things keep working — but this is riskier than the wrapper.
> - **It does nothing for Steam.** The Steam runtime container uses certificates from
>   its own runtime image, not from the host. Steam users must use the wrapper.

```bash
# export the certificate to remove
./overwatch-nexon-linux-fix.sh export-root ./g4.pem

# Fedora / RHEL family
sudo cp ./g4.pem /etc/pki/ca-trust/source/blacklist/
sudo update-ca-trust

# Debian / Ubuntu family — prefix the line with '!'
sudo sed -i 's|^mozilla/DigiCert_Trusted_Root_G4.crt|!&|' /etc/ca-certificates.conf
sudo update-ca-certificates
```

**Step 1 is still required** either way — the cross-signed certificate has to be in
the prefix.

To undo: delete the file from the blacklist directory (Fedora) or remove the `!`
(Debian), then re-run `update-ca-trust` / `update-ca-certificates`.

## Verify

```bash
./overwatch-nexon-linux-fix.sh status
```

```
프리픽스 / prefix        : /home/user/.local/share/Steam/steamapps/compatdata/…/pfx
교차서명 인증서 / cert   : 설치됨 installed ✓
신뢰 목록 / trust list   : 정상 ok ✓ (292 files)
```

Three checkmarks plus the wrapper in your launcher means you're ready to play.

## Troubleshooting

**`install` stops with "wineserver is running"**
Close the game, Battle.net, your launcher and Steam. If something is still holding
on, run `pkill -x wineserver` and try again.

**"Self-signed DigiCert Trusted Root G4 not present in the system bundle"**
Your distribution already excludes that certificate. In that case no trust list swap
is needed — do step 1 only and try launching without the wrapper.

**Wrapper is set but `0xE01300B0` persists**
- Check that `status` shows all three checkmarks.
- On Steam, make sure `%command%` is in the launch options.
- On Flatpak Steam/Bottles/Heroic, nested `bwrap` may be blocked by the sandbox. Use
  the native package, or the **alternative** above.
- The trust list rebuilds automatically when the system CA bundle changes; to force
  it, `rm -rf ~/.local/share/overwatch-nexon-fix/certs` and run `install` again.

**Different symptoms (login fails, no matchmaking, …)**
Not this bug. This script only addresses `0xE01300B0`, where the game never starts.

## Uninstall

```bash
./overwatch-nexon-linux-fix.sh uninstall
```

Restores the prefix registry from the backup and removes the trust list.
**Remember to remove the wrapper from your launcher's settings too.**

## What the script actually does

`Overwatch.exe` verifies the Authenticode signature of `gamescale64.dll` and **pins
the SHA-1 of the certificate chain's root certificate**. Under Wine the chain ends one
certificate short, so the pin comparison fails.

```
Windows :  NEXON → G4 Code Signing CA1 → G4 (cross-signed) → DigiCert Assured ID Root CA  ✓
Wine    :  NEXON → G4 Code Signing CA1 → G4 (self-signed) ■ stops here                    ✗
```

The script makes Wine build the same chain Windows does: it adds the public
cross-signed certificate to the prefix and hides the self-signed root from the game's
trust list.

**It does not disable the signature check — it lets it pass, correctly.** The DLL is
genuinely signed by NEXON Korea Corporation and is verified as such. No game files are
patched, no anti-cheat is touched, and the host trust store is not modified.

📄 **Full root-cause analysis in [`docs/ANALYSIS.md`](docs/ANALYSIS.md)** — including
the disassembly of the delay-load helper, the certificate chain comparison, every dead
end that was tried, and the upstream Wine issues.

## Verified environment

| | |
|---|---|
| Distro | Fedora 44, kernel 7.1.8, KDE Plasma (Wayland) |
| GPU | AMD Radeon RX 7700 XT, Mesa 26.1.6 (RADV) |
| Proton | GE-Proton11-5 / Proton Experimental 11.0, Steam Linux Runtime (steamrt4) |
| Setup | Battle.net launcher added to Steam as a non-Steam game |
| Result | launches → logs in → **playable through matchmaking** |

The Lutris, Heroic, Bottles and plain-wine instructions are **untested**. The
mechanism is identical so they should work, but the exact name of each launcher's
setting varies by version. Reports either way are welcome — open an issue and I'll
fold them into the docs.

## Upstream

This is a workaround. The real fix belongs in Wine's `crypt32`:

- `CertGetCertificateChain` does not consider alternative chains through
  cross-certificates; it terminates at the first trusted self-signed root it finds,
  whereas Windows builds every candidate chain and scores them.
- `CertCreateCertificateChainEngine` does not implement `hExclusiveRoot` or
  `hRestrictedRoot` (both return `E_INVALIDARG`).

Once that is fixed upstream, this script becomes unnecessary.

## License

[MIT](LICENSE).

The DigiCert cross-signed certificate embedded in the script is a public CA
certificate distributed by DigiCert and is not covered by the MIT license.
See [NOTICE](NOTICE).

<sub>
Keywords: Overwatch Linux fix, Overwatch Nexon Korea Proton, Overwatch 0xE01300B0,
0xC06D007E, Overwatch won't launch Proton, Battle.net Proton, Steam Deck Overwatch,
gamescale64.dll, Wine certificate chain, DigiCert Trusted Root G4.
Error text: "Overwatch has encountered a critical error during startup. Please
reinstall the game and try again.",
"설치한 파일에 문제가 있습니다. 문제가 지속되면 게임을 다시 설치해 주십시오.",
"블리자드와 이 문제에 대해 논의할 때 아래의 신고 ID를 사용하십시오."
</sub>
