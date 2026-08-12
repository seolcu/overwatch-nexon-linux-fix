#!/usr/bin/env bash
#
# 오버워치(넥슨 한국 서비스) 리눅스 실행 오류 0xE01300B0 해결 스크립트
#
#   증상: 배틀넷에서 오버워치 실행 → 잠깐 뜨다가 오류창 0xE01300B0 뜨고 종료
#   원인: Wine의 인증서 체인 구성이 윈도우와 달라, 게임의 무결성 검사가 실패
#   범위: 안티치트와 무관. 게임 파일을 수정하지 않음. 호스트 시스템을 바꾸지 않음.
#
# 자세한 원리는 같은 폴더의 README.md 참조.
#
# 사용법
#   ./overwatch-nexon-linux-fix.sh install     # 1회 설치
#   ./overwatch-nexon-linux-fix.sh status      # 상태 확인
#   ./overwatch-nexon-linux-fix.sh uninstall   # 되돌리기
#
#   그리고 Steam에서 배틀넷 바로가기 → 속성 → 실행 옵션에 아래를 입력:
#       /전체/경로/overwatch-nexon-linux-fix.sh run %command%
#
# 필요 패키지: bubblewrap, openssl, python3
#   Fedora  : sudo dnf install bubblewrap openssl python3
#   Ubuntu  : sudo apt install bubblewrap openssl python3
#   Arch    : sudo pacman -S bubblewrap openssl python
#
# 라이선스: MIT (LICENSE 참조). 내장된 DigiCert 교차서명 인증서는 적용 대상이
#           아닙니다 — NOTICE 참조.
# Copyright (c) 2026 seolcu

set -euo pipefail

# ── 상수 ──────────────────────────────────────────────────────────────────
# 자체서명 DigiCert Trusted Root G4. Wine이 체인을 여기서 끊어버리므로,
# 게임에 보여주는 신뢰 목록에서 이 인증서만 제외한다.
SELF_SIGNED_G4="DDFB16CD4931C973A2037D3FC83A4D7D775D05E4"
# 교차서명 DigiCert Trusted Root G4 (DigiCert Assured ID Root CA가 서명).
# 윈도우 인증서 저장소에는 있고 리눅스 CA 번들에는 없는 바로 그 인증서.
CROSS_G4="A99D5B79E9F1CDA59CDAB6373169D5353F5874C6"

STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/overwatch-nexon-fix"
CERTDIR="$STATE_DIR/certs"

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
    for c in bwrap openssl python3; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        die "다음 명령이 없습니다: ${missing[*]}
   Fedora : sudo dnf install bubblewrap openssl python3
   Ubuntu : sudo apt install bubblewrap openssl python3
   Arch   : sudo pacman -S bubblewrap openssl python"
    fi
}

# ── 프리픽스 자동 탐지 ────────────────────────────────────────────────────
# 배틀넷을 비스팀 게임으로 등록하면 compatdata 폴더 이름이 사람마다 다르므로
# gamescale64.dll 이 실제로 있는 프리픽스를 찾아낸다.
find_prefix() {
    if [ -n "${OW_PREFIX:-}" ]; then
        [ -d "$OW_PREFIX" ] || die "OW_PREFIX 경로가 없습니다: $OW_PREFIX"
        echo "$OW_PREFIX"; return
    fi

    local roots=() r hit
    for r in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root" \
             "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"; do
        [ -d "$r/steamapps/compatdata" ] && roots+=("$r")
    done
    # 추가 라이브러리 폴더도 훑는다
    for r in "${roots[@]}"; do
        if [ -f "$r/steamapps/libraryfolders.vdf" ]; then
            while IFS= read -r p; do
                [ -d "$p/steamapps/compatdata" ] && roots+=("$p")
            done < <(grep -oP '"path"\s*"\K[^"]+' "$r/steamapps/libraryfolders.vdf" 2>/dev/null || true)
        fi
    done

    for r in "${roots[@]}"; do
        while IFS= read -r hit; do
            [ -n "$hit" ] && { dirname "$(dirname "$(dirname "$(dirname "$(dirname "$hit")")")")"; return; }
        done < <(find "$r/steamapps/compatdata" -maxdepth 8 \
                    -path '*/pfx/drive_c/Program Files (x86)/Overwatch/_retail_/gamescale64.dll' \
                    2>/dev/null | head -1)
    done

    die "오버워치 프리픽스를 찾지 못했습니다.
   배틀넷을 Steam에 비스팀 게임으로 등록하고 한 번 실행한 뒤 다시 시도하거나,
   OW_PREFIX 환경변수로 직접 지정하세요. 예:
   OW_PREFIX=~/.local/share/Steam/steamapps/compatdata/1234567890/pfx $0 install"
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
    die "시스템 CA 번들을 찾지 못했습니다"
}

build_certdir() {
    local src stamp cur
    src="$(host_bundle)"
    stamp="$CERTDIR/.built-from"
    cur="$(sha256sum "$src" | cut -d' ' -f1)"
    [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$cur" ] && return

    msg "신뢰 목록 생성 중 (원본: $src)"
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
    raise SystemExit("경고: 시스템 CA 번들에서 자체서명 DigiCert Trusted Root G4를 "
                     "찾지 못했습니다. 배포판이 이미 제외했거나 구성이 다를 수 있습니다.")

bundle = "\n".join(kept) + "\n"
for n in ("ca-certificates.crt", "ca-bundle.crt"):
    open(os.path.join(out, n), "w").write(bundle)
print("  인증서 %d개 유지, 1개 제외 (자체서명 DigiCert Trusted Root G4)" % len(kept))
PY

    # pressure-vessel 은 c_rehash 레이아웃을 요구한다
    openssl rehash "$CERTDIR" >/dev/null 2>&1 || c_rehash "$CERTDIR" >/dev/null 2>&1 \
        || die "openssl rehash 실패"
    echo "$cur" > "$stamp"
}

# ── 프리픽스에 교차서명 인증서 설치 ───────────────────────────────────────
install_cert() {
    local pfx="$1" reg="$pfx/system.reg"
    [ -f "$reg" ] || die "system.reg 가 없습니다: $reg"

    if grep -q "CA\\\\\\\\Certificates\\\\\\\\$CROSS_G4" "$reg" 2>/dev/null; then
        msg "교차서명 인증서가 이미 설치돼 있습니다"
        return
    fi

    if pgrep -x wineserver >/dev/null 2>&1; then
        die "wineserver 가 실행 중입니다. 게임과 배틀넷, Steam을 완전히 종료한 뒤 다시 실행하세요.
   (강제 종료: pkill -x wineserver)"
    fi

    cp -n "$reg" "$reg.bak-overwatch-nexon-fix" 2>/dev/null || true
    msg "교차서명 인증서를 프리픽스 CA 저장소에 추가 (백업: $reg.bak-overwatch-nexon-fix)"

    printf '%s' "$CROSS_G4_B64" | base64 -d > "$STATE_DIR/crossg4.der"
    OW_REG="$reg" OW_DER="$STATE_DIR/crossg4.der" OW_THUMB="$CROSS_G4" python3 - <<'PY'
import os, hashlib, struct, time
reg, der_path, thumb = os.environ["OW_REG"], os.environ["OW_DER"], os.environ["OW_THUMB"]
der = open(der_path, "rb").read()
sha1 = hashlib.sha1(der).digest()
if sha1.hex().upper() != thumb:
    raise SystemExit("내장 인증서의 지문이 맞지 않습니다 — 스크립트가 손상되었습니다")

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
block = "\n[%s] %d\n#time=%x\n%s\n" % (key, now, ft, "\n".join(lines))

with open(reg, "a", encoding="utf-8") as f:
    f.write(block)
print("  등록 완료: %s" % thumb)
PY
}

# ── 서브커맨드 ────────────────────────────────────────────────────────────
cmd_install() {
    check_deps
    mkdir -p "$STATE_DIR"
    local pfx; pfx="$(find_prefix)"
    msg "프리픽스: $pfx"
    echo "$pfx" > "$STATE_DIR/prefix"
    install_cert "$pfx"
    build_certdir
    echo
    msg "설치 완료."
    echo
    echo "  이제 Steam에서 배틀넷 바로가기 → 속성 → 실행 옵션에 아래를 넣으세요:"
    echo
    echo "      $(readlink -f "$0") run %command%"
    echo
}

cmd_status() {
    check_deps
    local pfx; pfx="$(cat "$STATE_DIR/prefix" 2>/dev/null || find_prefix)"
    echo "프리픽스        : $pfx"
    if grep -q "CA\\\\\\\\Certificates\\\\\\\\$CROSS_G4" "$pfx/system.reg" 2>/dev/null; then
        echo "교차서명 인증서 : 설치됨 ✓"
    else
        echo "교차서명 인증서 : 없음 ✗  ('install' 을 실행하세요)"
    fi
    if [ -f "$CERTDIR/ca-certificates.crt" ]; then
        if grep -rqil "$SELF_SIGNED_G4" "$CERTDIR" 2>/dev/null; then
            echo "신뢰 목록       : 생성됨, 그러나 자체서명 G4가 남아 있음 ✗"
        else
            echo "신뢰 목록       : 생성됨, 자체서명 G4 제외 확인 ✓ ($(ls "$CERTDIR" | wc -l) 파일)"
        fi
    else
        echo "신뢰 목록       : 없음 ✗  ('install' 을 실행하세요)"
    fi
}

cmd_run() {
    [ $# -gt 0 ] || die "run 뒤에 실행할 명령이 없습니다. Steam 실행 옵션에 '%command%' 를 함께 넣으세요."
    check_deps
    build_certdir
    # 인증서 교체는 이 프로세스의 마운트 네임스페이스 안에서만 유효하다.
    # PRESSURE_VESSEL_IMPORT_CA_CERTS=1 이 있어야 Steam 런타임 컨테이너가
    # 자기 내장 인증서 대신 이걸 사용한다.
    exec bwrap --dev-bind / / --bind "$CERTDIR" /etc/ssl/certs -- \
        env PRESSURE_VESSEL_IMPORT_CA_CERTS=1 "$@"
}

cmd_uninstall() {
    local pfx; pfx="$(cat "$STATE_DIR/prefix" 2>/dev/null || find_prefix)"
    if pgrep -x wineserver >/dev/null 2>&1; then
        die "wineserver 가 실행 중입니다. 게임과 Steam을 종료한 뒤 다시 실행하세요."
    fi
    if [ -f "$pfx/system.reg.bak-overwatch-nexon-fix" ]; then
        cp "$pfx/system.reg.bak-overwatch-nexon-fix" "$pfx/system.reg"
        msg "프리픽스 레지스트리를 원래대로 복원했습니다"
    else
        warn "백업 파일이 없어 레지스트리는 그대로 둡니다 (교차서명 인증서는 무해합니다)"
    fi
    rm -rf "$STATE_DIR"
    msg "제거 완료. Steam 실행 옵션에서 이 스크립트를 지우는 것도 잊지 마세요."
}

case "${1:-}" in
    install)   shift; cmd_install   "$@" ;;
    status)    shift; cmd_status    "$@" ;;
    run)       shift; cmd_run       "$@" ;;
    uninstall) shift; cmd_uninstall "$@" ;;
    *)
        cat >&2 <<USAGE
오버워치(넥슨) 리눅스 오류 0xE01300B0 해결 스크립트

  $0 install     설치 (1회)
  $0 status      상태 확인
  $0 uninstall   되돌리기

설치 후 Steam에서 배틀넷 바로가기 → 속성 → 실행 옵션:
  $(readlink -f "$0") run %command%
USAGE
        exit 2 ;;
esac
