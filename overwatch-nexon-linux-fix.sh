#!/usr/bin/env bash
#
# 오버워치(넥슨 한국 서비스) 리눅스 실행 오류 0xE01300B0 해결
# Fix for Overwatch (Nexon KR) failing to launch on Linux — Blizzard error 0xE01300B0
#
#   Overwatch.exe verifies gamescale64.dll's Authenticode signature and pins the
#   SHA-1 of the certificate chain's ROOT to DigiCert Assured ID Root CA.
#   Windows reaches that root through the cross-signed "DigiCert Trusted Root G4";
#   Wine stops one certificate short at the self-signed G4, so the pin fails.
#
#   This installs the (public) cross-signed certificate into the Wine prefix and
#   presents the game a trust list without the self-signed G4, so the chain has to
#   continue up to the pinned root — the same chain Windows builds.
#
#   It does NOT patch the game, disable the signature check, or touch anti-cheat.
#   The trust list swap applies only inside a mount namespace for the launched
#   process; the host trust store is never modified.
#
# 라이선스: MIT (LICENSE 참조). 내장된 DigiCert 교차서명 인증서는 적용 대상이
#           아닙니다 — NOTICE 참조.
# Copyright (c) 2026 seolcu

set -euo pipefail

# ── 상수 ──────────────────────────────────────────────────────────────────
# 자체서명 DigiCert Trusted Root G4. Wine이 체인을 여기서 끊으므로,
# 게임에 보여주는 신뢰 목록에서 이 인증서만 제외한다.
SELF_SIGNED_G4="DDFB16CD4931C973A2037D3FC83A4D7D775D05E4"
# 교차서명 DigiCert Trusted Root G4 (DigiCert Assured ID Root CA가 서명).
# 윈도우 저장소에는 있고 리눅스 CA 번들에는 없는 바로 그 인증서.
CROSS_G4="A99D5B79E9F1CDA59CDAB6373169D5353F5874C6"

STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/overwatch-nexon-fix"
CERTDIR="$STATE_DIR/certs"
SELF="$(readlink -f "${BASH_SOURCE[0]}")"

msg()  { printf '\033[1;32m▶\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# 교차서명 인증서 (공개 DigiCert 인증서, DER/base64)
read -r -d '' CROSS_G4_B64 <<'CERT_EOF' || true
MIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYDVQQG
EwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQw
IgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIwODAxMDAwMDAwWhcNMzEx
MTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQL
ExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIi
MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZ
wuEppz1Yq3aaza57G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllV
cq9ok3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxeTsiT+CFhmzTrBcZe
7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbuyntd463JT17lNecxy9qTXtyOj4Da
tpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14
Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yhTzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCi
EhtmmnTK3kse5w5jrubU75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKy
Ebe7f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJbOUO
UlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/Y+whX8QgUWtvsauGi0/C1kVf
nSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwIDAQABo4IBOjCCATYwDwYDVR0TAQH/BAUwAwEB
/zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6mK4cD08wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGL
p6chnfNtyA8wDgYDVR0PAQH/BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0
cDovL29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2Vy
dC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4oDaGNGh0dHA6
Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwEQYDVR0gBAow
CDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBwoL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyhhyzs
hV6pGrsi+IcaaVQi7aSId229GhT0E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096ww
epqLsl7Uz9FDRJtDIeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxAGTVG
amlUsLihVo7spNU96LHc/RzY9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAIDyyCwrFigDkBjxZgi
wbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwYw02fc7cBqZ9Xql4o4rmU
CERT_EOF

# ── 사전 점검 ─────────────────────────────────────────────────────────────
check_deps() {
    local missing=()
    for c in bwrap openssl python3 find; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    [ ${#missing[@]} -eq 0 ] && return
    die "필요한 명령이 없습니다 / missing commands: ${missing[*]}
   Fedora : sudo dnf install bubblewrap openssl python3
   Ubuntu : sudo apt install bubblewrap openssl python3
   Arch   : sudo pacman -S bubblewrap openssl python"
}

# ── 프리픽스 탐지 ─────────────────────────────────────────────────────────
# 사람마다 배틀넷을 설치한 방법이 다르다 (Steam 비스팀 게임, Lutris, Bottles,
# Heroic, 순정 wine …). 그래서 특정 런처의 경로를 가정하지 않고, 알려진 프리픽스
# 보관 위치들에서 gamescale64.dll 을 찾은 뒤 그 위로 올라가며 system.reg 이 있는
# 디렉토리(= Wine 프리픽스)를 찾아낸다.
prefix_of() {
    local d; d="$(dirname "$1")"
    while [ "$d" != "/" ]; do
        # 심볼릭 링크를 풀어 정규 경로로 돌려준다. ~/.steam/root 와 ~/.steam/steam
        # 은 보통 ~/.local/share/Steam 을 가리키는 링크라, 정규화하지 않으면 같은
        # 프리픽스가 여러 개로 잡힌다.
        [ -f "$d/system.reg" ] && { readlink -f "$d"; return 0; }
        d="$(dirname "$d")"
    done
    return 1
}

search_roots() {
    local r p
    {
        # Steam (네이티브 / Flatpak / 추가 라이브러리 폴더)
        for r in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root" \
                 "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"; do
            [ -d "$r/steamapps/compatdata" ] && echo "$r/steamapps/compatdata"
            if [ -f "$r/steamapps/libraryfolders.vdf" ]; then
                while IFS= read -r p; do
                    [ -d "$p/steamapps/compatdata" ] && echo "$p/steamapps/compatdata"
                done < <(grep -oE '"path"[[:space:]]+"[^"]+"' "$r/steamapps/libraryfolders.vdf" 2>/dev/null \
                         | sed 's/.*"\(.*\)"$/\1/' | sed 's/\\\\/\//g')
            fi
        done
        # Lutris / Heroic 기본 위치
        for r in "$HOME/Games" "$HOME/.local/share/lutris" \
                 "$HOME/.var/app/net.lutris.Lutris/data/lutris" \
                 "$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic/Prefixes"; do
            [ -d "$r" ] && echo "$r"
        done
        # Bottles
        for r in "$HOME/.local/share/bottles/bottles" \
                 "$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles"; do
            [ -d "$r" ] && echo "$r"
        done
        # 순정 wine
        [ -d "$HOME/.wine" ] && echo "$HOME/.wine"
        [ -n "${WINEPREFIX:-}" ] && [ -d "$WINEPREFIX" ] && echo "$WINEPREFIX"
    } | while IFS= read -r r; do readlink -f "$r"; done | sort -u
}

find_prefixes() {
    local root dll
    while IFS= read -r root; do
        while IFS= read -r dll; do
            [ -n "$dll" ] && prefix_of "$dll" || true
        done < <(find "$root" -maxdepth 10 -name gamescale64.dll -type f 2>/dev/null)
    done < <(search_roots) | sort -u
}

resolve_prefix() {
    local found n
    if [ -n "${OW_PREFIX:-}" ]; then
        [ -f "$OW_PREFIX/system.reg" ] \
            || die "OW_PREFIX 가 Wine 프리픽스가 아닙니다 (system.reg 가 없습니다).
   OW_PREFIX is not a Wine prefix (no system.reg): $OW_PREFIX"
        readlink -f "$OW_PREFIX"; return
    fi

    found="$(find_prefixes)"
    n="$(printf '%s' "$found" | grep -c . || true)"

    if [ "$n" -eq 0 ]; then
        die "오버워치 프리픽스를 찾지 못했습니다 / Overwatch prefix not found.

   gamescale64.dll 이 있는 Wine 프리픽스를 찾지 못했습니다. 다음을 확인하세요:
     · 배틀넷으로 오버워치를 끝까지 설치했는지 (한 번은 실행해 봐야 파일이 생깁니다)
     · 프리픽스가 홈 디렉토리 밖(외장 드라이브 등)에 있지는 않은지

   직접 지정하려면 OW_PREFIX 로 프리픽스 경로를 넘기세요. 예:
     OW_PREFIX=~/Games/battlenet $SELF install

   프리픽스는 system.reg 파일이 들어 있는 디렉토리입니다. 이렇게 찾을 수 있습니다:
     find ~ -name gamescale64.dll 2>/dev/null"
    fi

    if [ "$n" -gt 1 ]; then
        warn "프리픽스가 여러 개 발견됐습니다 / multiple prefixes found:"
        printf '%s\n' "$found" | sed 's/^/     /' >&2
        die "OW_PREFIX 로 하나를 지정하세요 / pick one with OW_PREFIX."
    fi
    printf '%s' "$found"
}

# ── 신뢰 목록 디렉토리 생성 ───────────────────────────────────────────────
host_bundle() {
    local p
    for p in /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem \
             /etc/ssl/certs/ca-certificates.crt \
             /etc/pki/tls/certs/ca-bundle.crt \
             /etc/ssl/ca-bundle.pem; do
        [ -r "$p" ] && { echo "$p"; return; }
    done
    die "시스템 CA 번들을 찾지 못했습니다 / no system CA bundle found"
}

build_certdir() {
    local src stamp cur
    src="$(host_bundle)"
    stamp="$CERTDIR/.built-from"
    cur="$(sha256sum "$src" | cut -d' ' -f1)"
    [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$cur" ] && return

    msg "신뢰 목록 생성 중 / building trust list (source: $src)"
    rm -rf "$CERTDIR"; mkdir -p "$CERTDIR"

    OW_SRC="$src" OW_OUT="$CERTDIR" OW_DROP="$SELF_SIGNED_G4" python3 - <<'PY'
import os, re, subprocess, tempfile
src, out, drop = os.environ["OW_SRC"], os.environ["OW_OUT"], os.environ["OW_DROP"]
blocks, cur = [], []
for line in open(src, encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if line.startswith("-----BEGIN CERTIFICATE-----"): cur = [line]
    elif line.startswith("-----END CERTIFICATE-----"):
        cur.append(line); blocks.append("\n".join(cur)); cur = []
    elif cur: cur.append(line)

def x509(pem, *a):
    with tempfile.NamedTemporaryFile("w", suffix=".pem") as f:
        f.write(pem + "\n"); f.flush()
        return subprocess.run(["openssl", "x509", "-in", f.name, "-noout", *a],
                              capture_output=True, text=True).stdout

kept, dropped = [], 0
for i, b in enumerate(blocks):
    fp = x509(b, "-fingerprint", "-sha1").strip().split("=")[-1].replace(":", "").upper()
    if fp == drop:
        dropped += 1; continue
    subj = x509(b, "-subject")
    label = subj.split("CN=")[-1] if "CN=" in subj else subj.split("O=")[-1]
    name = re.sub(r"[^A-Za-z0-9]+", "_", label.strip())[:60] or ("cert%d" % i)
    open(os.path.join(out, "%s_%d.pem" % (name, i)), "w").write(b + "\n")
    kept.append(b)

if dropped == 0:
    raise SystemExit("자체서명 DigiCert Trusted Root G4 를 시스템 CA 번들에서 찾지 "
                     "못했습니다. 배포판이 이미 제외했거나 구성이 다를 수 있습니다.\n"
                     "Self-signed DigiCert Trusted Root G4 not found in the system "
                     "CA bundle.")

bundle = "\n".join(kept) + "\n"
for n in ("ca-certificates.crt", "ca-bundle.crt"):
    open(os.path.join(out, n), "w").write(bundle)
print("  인증서 %d개 유지, 1개 제외 / kept %d, removed 1" % (len(kept), len(kept)))
PY

    # pressure-vessel 은 c_rehash 레이아웃을 요구한다
    openssl rehash "$CERTDIR" >/dev/null 2>&1 || c_rehash "$CERTDIR" >/dev/null 2>&1 \
        || die "openssl rehash 실패 / openssl rehash failed"
    echo "$cur" > "$stamp"
}

# ── 프리픽스에 교차서명 인증서 설치 ───────────────────────────────────────
cert_installed() {
    grep -q "CA\\\\\\\\Certificates\\\\\\\\$CROSS_G4" "$1/system.reg" 2>/dev/null
}

install_cert() {
    local pfx="$1" reg="$pfx/system.reg"

    if cert_installed "$pfx"; then
        msg "교차서명 인증서가 이미 설치돼 있습니다 / cross-certificate already installed"
        return
    fi
    if pgrep -x wineserver >/dev/null 2>&1; then
        die "wineserver 가 실행 중입니다 / wineserver is running.
   게임·런처·Steam 을 완전히 종료한 뒤 다시 실행하세요.
   강제 종료: pkill -x wineserver"
    fi

    cp -n "$reg" "$reg.bak-overwatch-nexon-fix" 2>/dev/null || true
    msg "교차서명 인증서 설치 / installing cross-certificate"
    echo "     백업 / backup: $reg.bak-overwatch-nexon-fix"

    mkdir -p "$STATE_DIR"
    printf '%s' "$CROSS_G4_B64" | base64 -d > "$STATE_DIR/crossg4.der"
    OW_REG="$reg" OW_DER="$STATE_DIR/crossg4.der" OW_THUMB="$CROSS_G4" python3 - <<'PY'
import os, hashlib, struct, time
reg, der_path, thumb = os.environ["OW_REG"], os.environ["OW_DER"], os.environ["OW_THUMB"]
der = open(der_path, "rb").read()
sha1 = hashlib.sha1(der).digest()
if sha1.hex().upper() != thumb:
    raise SystemExit("내장 인증서 지문 불일치 — 스크립트가 손상되었습니다 / "
                     "embedded certificate fingerprint mismatch")

# Wine 이 저장하는 직렬화 형식: (프로퍼티ID, 인코딩, 길이) + 값
blob  = struct.pack("<III", 3, 1, len(sha1)) + sha1        # CERT_SHA1_HASH_PROP_ID
blob += struct.pack("<III", 32, 1, len(der)) + der         # CERT_CERT_PROP_ID

hexs = ["%02x" % b for b in blob]
lines, cur = [], '"Blob"=hex:'
for i, h in enumerate(hexs):
    piece = h + ("," if i < len(hexs) - 1 else "")
    if len(cur) + len(piece) > 76:
        lines.append(cur + "\\"); cur = "  "
    cur += piece
lines.append(cur)

now = int(time.time())
ft = (now + 11644473600) * 10000000
key = "Software\\\\Microsoft\\\\SystemCertificates\\\\CA\\\\Certificates\\\\" + thumb
with open(reg, "a", encoding="utf-8") as f:
    f.write("\n[%s] %d\n#time=%x\n%s\n" % (key, now, ft, "\n".join(lines)))
print("     등록 완료 / installed: %s" % thumb)
PY
}

# ── 서브커맨드 ────────────────────────────────────────────────────────────
cmd_install() {
    check_deps
    mkdir -p "$STATE_DIR"
    local pfx; pfx="$(resolve_prefix)"
    msg "프리픽스 / prefix: $pfx"
    echo "$pfx" > "$STATE_DIR/prefix"
    install_cert "$pfx"
    build_certdir
    cat <<EOF

$(msg "설치 완료 / installed.")

  이제 게임을 아래 명령으로 감싸서 실행해야 합니다.
  Now the game has to be launched through this wrapper:

      $SELF run <원래 실행 명령>

  런처별 설정 방법:

   · Steam (비스팀 게임 추가)
       배틀넷 바로가기 → 속성 → 실행 옵션:
         $SELF run %command%

   · Lutris
       게임 우클릭 → Configure → System options → Command prefix:
         $SELF run

   · Heroic
       게임 Settings → Advanced → Wrapper command 에 추가:
         $SELF run

   · Bottles (래퍼 필드가 없으므로 터미널에서 실행)
         $SELF run bottles-cli run -b "보틀이름" -p "Battle.net"

   · 순정 wine / 직접 실행
         $SELF run wine "C:\\\\...\\\\Battle.net Launcher.exe"

  자세한 설명과 문제 해결은 README 를 보세요.
  See the README for details and troubleshooting.

EOF
}

cmd_status() {
    check_deps
    local pfx
    pfx="$(cat "$STATE_DIR/prefix" 2>/dev/null || true)"
    [ -n "$pfx" ] && [ -f "$pfx/system.reg" ] || pfx="$(resolve_prefix)"

    echo "프리픽스 / prefix        : $pfx"
    if cert_installed "$pfx"; then
        echo "교차서명 인증서 / cert   : 설치됨 installed ✓"
    else
        echo "교차서명 인증서 / cert   : 없음 missing ✗   →  $SELF install"
    fi
    if [ -f "$CERTDIR/ca-certificates.crt" ]; then
        if grep -rqil "$SELF_SIGNED_G4" "$CERTDIR" 2>/dev/null; then
            echo "신뢰 목록 / trust list   : 자체서명 G4 남아 있음 ✗"
        else
            echo "신뢰 목록 / trust list   : 정상 ok ✓ ($(ls "$CERTDIR" | wc -l) files)"
        fi
    else
        echo "신뢰 목록 / trust list   : 없음 missing ✗   →  $SELF install"
    fi
    echo
    echo "실행 래퍼 / launch wrapper:"
    echo "  $SELF run <command>"
}

cmd_run() {
    [ $# -gt 0 ] || die "run 뒤에 실행할 명령이 없습니다 / no command given after 'run'.
   Steam 실행 옵션이라면 '%command%' 를 함께 넣어야 합니다."
    check_deps
    build_certdir
    # 인증서 교체는 이 프로세스의 마운트 네임스페이스 안에서만 유효하다.
    # PRESSURE_VESSEL_IMPORT_CA_CERTS=1 은 Steam 런타임 컨테이너가 자기 내장
    # 인증서 대신 이걸 쓰게 만든다. Steam 을 쓰지 않는 경우엔 무해하게 무시된다.
    exec bwrap --dev-bind / / --bind "$CERTDIR" /etc/ssl/certs -- \
        env PRESSURE_VESSEL_IMPORT_CA_CERTS=1 "$@"
}

# 래퍼를 쓸 수 없는 환경(Bottles, 일부 Flatpak 구성)을 위해, 시스템 신뢰 저장소에서
# 직접 제외할 수 있도록 자체서명 G4 인증서를 PEM 으로 꺼내 준다.
# 주의: 이 방식은 시스템 전체에 영향을 주며, Steam 런타임 컨테이너에는 효과가 없다.
cmd_export_root() {
    local out="${1:-./DigiCert_Trusted_Root_G4_self_signed.pem}"
    check_deps
    OW_SRC="$(host_bundle)" OW_OUT="$out" OW_WANT="$SELF_SIGNED_G4" python3 - <<'PY'
import os, subprocess, tempfile
src, out, want = os.environ["OW_SRC"], os.environ["OW_OUT"], os.environ["OW_WANT"]
blocks, cur = [], []
for line in open(src, encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if line.startswith("-----BEGIN CERTIFICATE-----"): cur = [line]
    elif line.startswith("-----END CERTIFICATE-----"):
        cur.append(line); blocks.append("\n".join(cur)); cur = []
    elif cur: cur.append(line)
for b in blocks:
    with tempfile.NamedTemporaryFile("w", suffix=".pem") as f:
        f.write(b + "\n"); f.flush()
        fp = subprocess.run(["openssl", "x509", "-in", f.name, "-noout", "-fingerprint",
                             "-sha1"], capture_output=True, text=True).stdout
    if fp.strip().split("=")[-1].replace(":", "").upper() == want:
        open(out, "w").write(b + "\n")
        raise SystemExit(0)
raise SystemExit("시스템 CA 번들에 자체서명 DigiCert Trusted Root G4 가 없습니다.\n"
                 "Self-signed DigiCert Trusted Root G4 not present in the system bundle.")
PY
    msg "저장 완료 / written: $out"
    echo "     이 인증서를 시스템 신뢰 목록에서 제외하는 방법은 README 를 보세요."
    echo "     See the README for how to blacklist it system-wide."
}

cmd_uninstall() {
    local pfx
    pfx="$(cat "$STATE_DIR/prefix" 2>/dev/null || true)"
    [ -n "$pfx" ] && [ -f "$pfx/system.reg" ] || pfx="$(resolve_prefix)"
    if pgrep -x wineserver >/dev/null 2>&1; then
        die "wineserver 가 실행 중입니다 / wineserver is running.
   게임·런처·Steam 을 종료한 뒤 다시 실행하세요."
    fi
    if [ -f "$pfx/system.reg.bak-overwatch-nexon-fix" ]; then
        cp "$pfx/system.reg.bak-overwatch-nexon-fix" "$pfx/system.reg"
        msg "프리픽스 레지스트리 복원 / prefix registry restored"
    else
        warn "백업이 없어 레지스트리는 그대로 둡니다 (교차서명 인증서는 무해합니다)
   No backup found; leaving the registry as is (the certificate is harmless)."
    fi
    rm -rf "$STATE_DIR"
    msg "제거 완료 / removed."
    echo "     런처의 실행 옵션/래퍼 설정에서도 이 스크립트를 지워 주세요."
    echo "     Remember to remove the wrapper from your launcher's settings too."
}

case "${1:-}" in
    install)     shift; cmd_install     "$@" ;;
    status)      shift; cmd_status      "$@" ;;
    run)         shift; cmd_run         "$@" ;;
    uninstall)   shift; cmd_uninstall   "$@" ;;
    export-root) shift; cmd_export_root "$@" ;;
    *)
        b="$(basename "$SELF")"
        cat >&2 <<USAGE
오버워치(넥슨) 리눅스 오류 0xE01300B0 해결
Fix for Overwatch (Nexon KR) error 0xE01300B0 on Linux

  $b install       설치 / install (once)
  $b status        상태 확인 / show status
  $b run <cmd>     래퍼로 게임 실행 / launch through the wrapper
  $b uninstall     되돌리기 / revert
  $b export-root   자체서명 G4 인증서 추출 / export the self-signed root (see README)

프리픽스를 직접 지정하려면 / to pick the prefix manually:
  OW_PREFIX=/path/to/prefix $b install

런처 설정에 넣을 전체 경로 / full path for launcher settings:
  $SELF
USAGE
        exit 2 ;;
esac
