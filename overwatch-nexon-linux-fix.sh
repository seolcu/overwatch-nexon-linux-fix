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
# 게임이 하드코딩해 둔 핀 값 — 체인의 끝이 반드시 이 인증서여야 한다.
# 신뢰 목록에 이게 없으면 앵커 자체가 없어서 체인이 한 칸 더 올라갈 수 없다.
PINNED_ROOT="0563B8630D62D75ABBC8AB1E4BDFB5A899B24D43"

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

# 핀 대상 루트 DigiCert Assured ID Root CA (공개 DigiCert 인증서, DER/base64).
# 배포판이 신뢰 목록에서 이 루트를 빼 버린 경우에만 폴백으로 사용한다.
read -r -d '' ASSURED_ID_ROOT_B64 <<'CERT_EOF' || true
MIIDtzCCAp+gAwIBAgIQDOfg5RfYRv6P5WD8G/AwOTANBgkqhkiG9w0BAQUFADBlMQswCQYDVQQG
EwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQw
IgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMDYxMTEwMDAwMDAwWhcNMzEx
MTEwMDAwMDAwWjBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQL
ExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0Ew
ggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCtDhXO5EOAXLGH87dg+XESpa7cJpSIqvTO
9SA5KFhgDPiA2qkVlTJhPLWxKISKityfCgyDF3qPkKyK53lTXDGEKvYPmDI2dsze3Tyoou9q+yHy
UmHfnyDXH+Kx2f4YZNISW1/5WBg1vEfNoTb5a3/UsDg+wRvDjDPZ2C8Y/igPs6eD1sNuRMBhNZYW
/lmci3Zt1/GiSw0r/wty2p5g0I6QNcZ4VYcgoc/lbQrISXwxmDNsIumH0DJaoroTghHtORedmTpy
oeb6pNnVFzF1roV9Iq4/AUaG9ih5yLHa5FcXxH4cDrC0kqZWs72yl+2qp/C3xag/lRbQ/6GW6whf
GHdPAgMBAAGjYzBhMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBRF
66Kv9JLLgjEtUYunpyGd823IDzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzANBgkq
hkiG9w0BAQUFAAOCAQEAog683+Lt8ONyc3pklL/3cmbYMuRCdWKuh+vy1dneVrOfzM4UKLkNl2Bc
EkxY5NM9g0lFWJc1aRqoR+pWxnmrEthngYTffwk8lOa4JiwgvT2zKIn3X/8i4peEH+ll74fg38Fn
SbNd67IJKusm7Xi+fT8r87cmNW1fiQG2SVufAQWbqz0lwcy2f8Lxb4bG+mRo64EtlOtCt/qMHt1i
8b5QZ7dsvfPxH2sMNgcWfzd8qVttevESRmCD1ycEvkvOl77DZypoEd+A5wwzZr8TDRRu838fYxAe
+o0bJW1sj6W3YQGx0qMmoRBxna3iw/nDmVG3KwcIzi7mULKn+gpFL6Lw8g==
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

    OW_SRC="$src" OW_OUT="$CERTDIR" OW_DROP="$SELF_SIGNED_G4" OW_PIN="$PINNED_ROOT" \
    OW_PIN_B64="$ASSURED_ID_ROOT_B64" python3 - <<'PY'
import base64, hashlib, os, re, subprocess, tempfile, textwrap
src, out  = os.environ["OW_SRC"], os.environ["OW_OUT"]
drop, pin = os.environ["OW_DROP"], os.environ["OW_PIN"]
blocks, cur = [], []
for line in open(src, encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if line.startswith("-----BEGIN CERTIFICATE-----"): cur = [line]
    elif line.startswith("-----END CERTIFICATE-----"):
        cur.append(line); blocks.append("\n".join(cur)); cur = []
    elif cur: cur.append(line)

def fingerprint(pem):
    body = "".join(l for l in pem.splitlines() if not l.startswith("-----"))
    return hashlib.sha1(base64.b64decode(body)).hexdigest().upper()

def subject(pem):
    with tempfile.NamedTemporaryFile("w", suffix=".pem") as f:
        f.write(pem + "\n"); f.flush()
        return subprocess.run(["openssl", "x509", "-in", f.name, "-noout", "-subject"],
                              capture_output=True, text=True).stdout

def emit(pem, i):
    subj = subject(pem)
    label = subj.split("CN=")[-1] if "CN=" in subj else subj.split("O=")[-1]
    name = re.sub(r"[^A-Za-z0-9]+", "_", label.strip())[:60] or ("cert%d" % i)
    open(os.path.join(out, "%s_%d.pem" % (name, i)), "w").write(pem + "\n")

kept, dropped, pinned_seen = [], 0, False
for i, b in enumerate(blocks):
    fp = fingerprint(b)
    if fp == drop:
        dropped += 1; continue
    if fp == pin:
        pinned_seen = True
    emit(b, i); kept.append(b)

if dropped == 0:
    raise SystemExit("자체서명 DigiCert Trusted Root G4 를 시스템 CA 번들에서 찾지 "
                     "못했습니다. 배포판이 이미 제외했거나 구성이 다를 수 있습니다.\n"
                     "Self-signed DigiCert Trusted Root G4 not found in the system "
                     "CA bundle.")

# 게임이 핀해 둔 루트가 배포판 번들에서 빠져 있으면 체인이 올라갈 곳이 없다.
# 이 경우에만 내장 사본을 신뢰 목록에 되돌려 넣는다 (래퍼 네임스페이스 안에서만 유효).
if not pinned_seen:
    b64 = "".join(os.environ["OW_PIN_B64"].split())
    der = base64.b64decode(b64)
    if hashlib.sha1(der).hexdigest().upper() != pin:
        raise SystemExit("내장 핀 루트 지문 불일치 — 스크립트가 손상되었습니다 / "
                         "embedded pinned root fingerprint mismatch")
    pem = ("-----BEGIN CERTIFICATE-----\n"
           + "\n".join(textwrap.wrap(b64, 64))
           + "\n-----END CERTIFICATE-----")
    emit(pem, len(blocks)); kept.append(pem)
    print("  ! 배포판 번들에 DigiCert Assured ID Root CA 가 없어 내장 사본을 추가했습니다")
    print("    added the embedded DigiCert Assured ID Root CA (missing from this distro)")

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
# system.reg 의 인증서 저장소 항목에서 Blob 을 꺼내 실제 인증서의 SHA-1 을 출력한다.
# 키 이름만 grep 하면 Blob 이 깨져 있어도 "설치됨"으로 보이기 때문에 값까지 확인한다.
#   $1 프리픽스   $2 저장소 (CA | Root | Disallowed)   $3 지문
reg_cert_sha1() {
    OW_REG="$1/system.reg" OW_STORE="$2" OW_THUMB="$3" python3 - <<'PY' 2>/dev/null || true
import hashlib, os, struct
reg = os.environ["OW_REG"]
head = "[Software\\\\Microsoft\\\\SystemCertificates\\\\%s\\\\Certificates\\\\%s]" % (
       os.environ["OW_STORE"], os.environ["OW_THUMB"])

hexs, inside, collecting = [], False, False
for line in open(reg, encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if line.startswith("["):
        if inside: break
        inside = line.startswith(head)
        continue
    if not inside:
        continue
    if line.startswith('"Blob"=hex:'):
        collecting = True; line = line[len('"Blob"=hex:'):]
    elif not collecting:
        continue
    more = line.endswith("\\")
    hexs.append(line[:-1] if more else line)
    collecting = more
    if not more: break

blob = bytes.fromhex("".join(hexs).replace(",", "").strip())
off = 0
while off + 12 <= len(blob):
    prop, _enc, length = struct.unpack_from("<III", blob, off)
    val = blob[off + 12:off + 12 + length]
    if prop == 32:                                  # CERT_CERT_PROP_ID = DER 본문
        print(hashlib.sha1(val).hexdigest().upper()); break
    off += 12 + length
PY
}

cert_installed() {
    [ "$(reg_cert_sha1 "$1" CA "$CROSS_G4")" = "$CROSS_G4" ]
}

# 자체서명 G4 가 프리픽스의 Root 저장소에 남아 있으면, 신뢰 목록을 아무리 바꿔도
# 체인이 거기서 끝난다. Wine 은 자기가 임포트한 것으로 표시된 인증서만 정리하므로
# (rootstore.c: "key is not imported, not deleting") 직접 지운다.
self_signed_root_present() {
    [ "$(reg_cert_sha1 "$1" Root "$SELF_SIGNED_G4")" = "$SELF_SIGNED_G4" ]
}

purge_self_signed_root() {
    local pfx="$1"
    self_signed_root_present "$pfx" || return 0
    msg "프리픽스 Root 에서 자체서명 G4 제거 / removing self-signed G4 from the prefix Root store"
    OW_REG="$pfx/system.reg" OW_THUMB="$SELF_SIGNED_G4" python3 - <<'PY'
import os
reg  = os.environ["OW_REG"]
head = "[Software\\\\Microsoft\\\\SystemCertificates\\\\Root\\\\Certificates\\\\%s]" % (
       os.environ["OW_THUMB"])
out, skipping = [], False
for line in open(reg, encoding="utf-8", errors="replace"):
    if line.startswith("["):
        skipping = line.startswith(head)
    if not skipping:
        out.append(line)
tmp = reg + ".tmp-overwatch-nexon-fix"
with open(tmp, "w", encoding="utf-8") as f:
    f.writelines(out)
os.replace(tmp, reg)
PY
}

# 프리픽스에 필요한 두 가지를 한꺼번에 맞춘다: 교차서명 인증서 설치 + 자체서명 G4 제거.
prepare_prefix() {
    local pfx="$1" reg="$pfx/system.reg" need_cert=0 need_purge=0
    if ! cert_installed "$pfx"; then need_cert=1; fi
    if self_signed_root_present "$pfx"; then need_purge=1; fi

    if [ "$need_cert" -eq 0 ] && [ "$need_purge" -eq 0 ]; then
        msg "프리픽스는 이미 준비돼 있습니다 / prefix already prepared"
        return
    fi
    if pgrep -x wineserver >/dev/null 2>&1; then
        die "wineserver 가 실행 중입니다 / wineserver is running.
   게임·런처·Steam 을 완전히 종료한 뒤 다시 실행하세요.
   강제 종료: pkill -x wineserver"
    fi

    cp -n "$reg" "$reg.bak-overwatch-nexon-fix" 2>/dev/null || true
    echo "     백업 / backup: $reg.bak-overwatch-nexon-fix"
    if [ "$need_cert" -eq 1 ]; then install_cert "$pfx"; fi
    purge_self_signed_root "$pfx"
}

install_cert() {
    local pfx="$1" reg="$pfx/system.reg"
    msg "교차서명 인증서 설치 / installing cross-certificate"

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
    prepare_prefix "$pfx"
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
        if bundle_has "$CERTDIR/ca-certificates.crt" "$SELF_SIGNED_G4"; then
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
    echo
    echo "자세한 진단 / full diagnostics:"
    echo "  $SELF doctor"
}

# Wine 이 호스트 인증서를 찾는 경로들 (dlls/crypt32/unixlib.c: CRYPT_knownLocations).
# 앞에서부터 훑다가 인증서가 나온 첫 위치에서 멈추므로 /etc/ssl/certs 를 덮으면 보통
# 충분하다. 다만 /etc/ssl/certs 가 없는 배포판에서는 뒤쪽 경로가 쓰이므로 함께 덮는다.
EXTRA_BUNDLE_PATHS=(
    /etc/pki/tls/certs/ca-bundle.crt
    /usr/share/ca-certificates/ca-bundle.crt
    /etc/ssl/cert.pem
)

# 위 목록 중 실제로 바인드할 것만 골라 전역 배열 BINDS 에 넣는다.
# 심볼릭 링크에는 바인드하지 않는다 — bwrap 이 마운트 지점을 만들지 못하고 실패한다
# (예: Fedora 의 /etc/ssl/cert.pem → /etc/pki/ca-trust/.../tls-ca-bundle.pem).
# 어차피 링크 대상이 대부분 같은 번들이라 잃는 것도 없다.
build_binds() {
    BINDS=(--bind "$CERTDIR" /etc/ssl/certs)
    local p
    for p in "${EXTRA_BUNDLE_PATHS[@]}"; do
        if [ -f "$p" ] && [ ! -L "$p" ]; then
            BINDS+=(--bind "$CERTDIR/ca-certificates.crt" "$p")
        fi
    done
}

# 래퍼 밖에서 이미 떠 있는 세션에는 신뢰 목록 교체가 적용되지 않는다. 런처의 "실행"이
# 기존 배틀넷 인스턴스로 넘어가면 게임도 네임스페이스 밖에서 뜨는데, 런처 로그에는
# 래퍼가 정상적으로 보이기 때문에 이 상태를 알아채기가 어렵다.
live_sessions() {
    local found=""
    if pgrep -x wineserver    >/dev/null 2>&1; then found="$found wineserver"; fi
    if pgrep -f 'Battle\.net' >/dev/null 2>&1; then found="$found Battle.net"; fi
    if pgrep -f 'Agent\.exe'  >/dev/null 2>&1; then found="$found Agent.exe"; fi
    printf '%s' "${found# }"
}

warn_live_sessions() {
    local found; found="$(live_sessions)"
    [ -n "$found" ] || return 0
    warn "이미 실행 중인 프로세스가 있습니다 / already running: $found
   래퍼 밖에서 시작된 세션에는 이 픽스가 적용되지 않습니다. 런처가 실행을 기존
   배틀넷 인스턴스로 넘기면 게임도 그쪽에서 뜹니다. 전부 종료한 뒤 다시 시도하세요:
   Sessions started outside the wrapper do not get the fix. Close everything first:
     pkill -f Battle.net; pkill -x wineserver"
}

# ── 진단 ──────────────────────────────────────────────────────────────────
DOCTOR_FAIL=0
d_ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
d_bad()  { printf '  \033[1;31m✗\033[0m %s\n' "$*"; DOCTOR_FAIL=$((DOCTOR_FAIL + 1)); }
d_warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }
d_info() { printf '      %s\n' "$*"; }
d_head() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# PEM 번들 안에 해당 지문의 인증서가 있는지
bundle_has() {
    OW_SRC="$1" OW_FP="$2" python3 - <<'PY'
import base64, hashlib, os, re, sys
data = open(os.environ["OW_SRC"], encoding="utf-8", errors="replace").read()
want = os.environ["OW_FP"]
for b in re.findall(r"-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----", data, re.S):
    if hashlib.sha1(base64.b64decode("".join(b.split()))).hexdigest().upper() == want:
        sys.exit(0)
sys.exit(1)
PY
}

write_cross_pem() {
    { echo "-----BEGIN CERTIFICATE-----"
      printf '%s\n' "$CROSS_G4_B64"
      echo "-----END CERTIFICATE-----"
    } > "$1"
}

# 래퍼 안에서 재실행되는 부분 — 신뢰 목록 교체가 실제로 합성됐는지 확인한다.
doctor_inside() {
    local b=/etc/ssl/certs/ca-certificates.crt
    if [ ! -r "$b" ]; then
        d_bad "네임스페이스 안에 $b 가 없습니다 / missing inside the namespace"; return
    fi
    if bundle_has "$b" "$SELF_SIGNED_G4"; then
        d_bad "네임스페이스 안 신뢰 목록에 자체서명 G4 가 남아 있습니다 / self-signed G4 still visible"
        d_info "신뢰 목록 자체가 잘못됐거나(위 1번 확인), bwrap 바인드가 합성되지"
        d_info "않았습니다(Flatpak 샌드박스 등)."
    else
        d_ok "네임스페이스 안 신뢰 목록에서 자체서명 G4 제외됨 / self-signed G4 hidden inside"
    fi
    if bundle_has "$b" "$PINNED_ROOT"; then
        d_ok "네임스페이스 안에 핀 대상 루트 있음 / pinned root visible inside"
    else
        d_bad "네임스페이스 안에 핀 대상 루트가 없습니다 / pinned root missing inside"
    fi
}

cmd_doctor() {
    if [ "${1:-}" = "--inside" ]; then doctor_inside; exit "$DOCTOR_FAIL"; fi
    check_deps

    d_head "1. 호스트 신뢰 목록 / host trust list"
    local src; src="$(host_bundle)"
    d_ok "시스템 CA 번들 / system bundle: $src"
    if [ ! -f "$CERTDIR/ca-certificates.crt" ]; then
        d_bad "신뢰 목록이 없습니다 / trust list not built  →  $SELF install"
    else
        local stamp cur
        stamp="$(cat "$CERTDIR/.built-from" 2>/dev/null || true)"
        cur="$(sha256sum "$src" | cut -d' ' -f1)"
        if [ "$stamp" = "$cur" ]; then
            d_ok "신뢰 목록 최신 / trust list up to date ($(find "$CERTDIR" -maxdepth 1 -type f | wc -l) files)"
        else
            d_warn "시스템 번들이 바뀌었습니다 — 다음 실행 때 자동 재생성됩니다 / stale, will rebuild"
        fi
        if [ -f "$CERTDIR/ca-bundle.crt" ]; then
            d_ok "ca-certificates.crt + ca-bundle.crt 존재 / both bundle names present"
        else
            d_bad "ca-bundle.crt 가 없습니다 / missing (pressure-vessel 이 요구합니다)"
        fi
        if [ "$(find "$CERTDIR" -maxdepth 1 -name '*.0' | wc -l)" -gt 0 ]; then
            d_ok "c_rehash 레이아웃 존재 / rehash symlinks present"
        else
            d_bad "c_rehash 심볼릭 링크가 없습니다 / rehash layout missing  →  $SELF install"
        fi
        if bundle_has "$CERTDIR/ca-certificates.crt" "$SELF_SIGNED_G4"; then
            d_bad "신뢰 목록에 자체서명 G4 가 남아 있습니다 / self-signed G4 still in the trust list"
        else
            d_ok "자체서명 G4 제외됨 / self-signed G4 excluded"
        fi
        if bundle_has "$CERTDIR/ca-certificates.crt" "$PINNED_ROOT"; then
            d_ok "핀 대상 루트 DigiCert Assured ID Root CA 있음 / pinned root present"
        else
            d_bad "핀 대상 루트가 없습니다 / pinned root missing  →  $SELF install"
            d_info "이게 없으면 체인이 올라갈 앵커가 없어 픽스가 동작할 수 없습니다"
        fi
        # 교차인증서가 실제로 핀 루트까지 검증되는지 — 이 픽스의 핵심을 그대로 확인한다.
        local tmp; tmp="$(mktemp)"; write_cross_pem "$tmp"
        if openssl verify -CAfile "$CERTDIR/ca-certificates.crt" "$tmp" >/dev/null 2>&1; then
            d_ok "교차인증서 → 핀 루트 검증 성공 / cross-certificate verifies up to the pinned root"
        else
            d_bad "교차인증서가 핀 루트까지 검증되지 않습니다 / cross-certificate does not verify"
            d_info "$(openssl verify -CAfile "$CERTDIR/ca-certificates.crt" "$tmp" 2>&1 | tail -2)"
        fi
        rm -f "$tmp"

        d_head "2. 래퍼 네임스페이스 / inside the wrapper"
        build_binds
        if ! bwrap --dev-bind / / "${BINDS[@]}" -- "$SELF" doctor --inside; then
            DOCTOR_FAIL=$((DOCTOR_FAIL + 1))
        fi
    fi

    d_head "3. Wine 프리픽스 / Wine prefix"
    local pfx
    pfx="$(cat "$STATE_DIR/prefix" 2>/dev/null || true)"
    [ -n "$pfx" ] && [ -f "$pfx/system.reg" ] || pfx="$(resolve_prefix 2>/dev/null || true)"
    if [ -z "$pfx" ]; then
        d_bad "프리픽스를 찾지 못했습니다 / prefix not found  →  OW_PREFIX=... $SELF install"
    else
        d_ok "프리픽스 / prefix: $pfx"
        if cert_installed "$pfx"; then
            d_ok "교차서명 인증서가 CA 저장소에 정상 등록됨 / cross-certificate stored and valid"
        elif [ -n "$(reg_cert_sha1 "$pfx" CA "$CROSS_G4")" ]; then
            d_bad "CA 저장소의 Blob 이 교차서명 인증서가 아닙니다 / stored blob is not the expected cert"
        else
            d_bad "교차서명 인증서가 없습니다 / cross-certificate missing  →  $SELF install"
        fi
        if self_signed_root_present "$pfx"; then
            d_bad "프리픽스 Root 에 자체서명 G4 가 남아 있습니다 / self-signed G4 still in the prefix Root store"
            d_info "체인이 여기서 끝나 픽스가 무효화됩니다  →  $SELF install"
        else
            d_ok "프리픽스 Root 에 자체서명 G4 없음 / self-signed G4 absent from the prefix Root store"
        fi
        d_info "참고: system.reg 를 grep 하면 Software\\\\Wine\\\\HostImportedCertificates 에"
        d_info "      지문이 남아 있을 수 있습니다. Wine 내부 장부일 뿐 신뢰 저장소가 아닙니다."
        local dll
        dll="$(find "$pfx" -maxdepth 8 -name gamescale64.dll -type f 2>/dev/null | head -1)"
        if [ -n "$dll" ]; then d_ok "gamescale64.dll: $dll"
        else d_bad "프리픽스 안에서 gamescale64.dll 을 찾지 못했습니다 / not found in this prefix"; fi
    fi

    d_head "4. 실행 중인 세션 / running sessions"
    local live; live="$(live_sessions)"
    if [ -z "$live" ]; then
        d_ok "래퍼 밖에서 실행 중인 프로세스 없음 / nothing running outside the wrapper"
    else
        d_bad "실행 중 / running: $live"
        d_info "래퍼 밖 세션에는 픽스가 적용되지 않습니다: pkill -f Battle.net; pkill -x wineserver"
    fi

    d_head "5. 환경 / environment (이슈에 붙여 주세요)"
    d_info "$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
    d_info "kernel : $(uname -r)"
    d_info "bwrap  : $(bwrap --version 2>/dev/null || echo unknown)"
    d_info "openssl: $(openssl version 2>/dev/null || echo unknown)"
    d_info "script : $SELF"

    echo
    if [ "$DOCTOR_FAIL" -eq 0 ]; then
        msg "이상 없음 / no problems found."
        echo "     그래도 실패한다면 내부 예외가 0xC06D007E 가 맞는지 확인하세요:"
        echo "     If it still fails, confirm the inner exception really is 0xC06D007E:"
        echo "       PROTON_LOG=\"+timestamp,+pid,+tid,+seh,+chain,+crypt,+wintrust\" %command%"
        echo "       grep -n 'c06d007e' \$HOME/steam-*.log"
    else
        warn "$DOCTOR_FAIL 개 항목이 실패했습니다 / $DOCTOR_FAIL check(s) failed."
    fi
    return 0
}

cmd_run() {
    [ $# -gt 0 ] || die "run 뒤에 실행할 명령이 없습니다 / no command given after 'run'.
   Steam 실행 옵션이라면 '%command%' 를 함께 넣어야 합니다."
    check_deps
    build_certdir
    warn_live_sessions

    build_binds
    # 인증서 교체는 이 프로세스의 마운트 네임스페이스 안에서만 유효하다.
    # PRESSURE_VESSEL_IMPORT_CA_CERTS=1 은 Steam 런타임 컨테이너가 자기 내장
    # 인증서 대신 이걸 쓰게 만든다. Steam 을 쓰지 않는 경우엔 무해하게 무시된다.
    exec bwrap --dev-bind / / "${BINDS[@]}" -- \
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
    doctor)      shift; cmd_doctor      "$@" ;;
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
  $b doctor        정밀 진단 / full diagnostics (문제가 생기면 이것부터)
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
