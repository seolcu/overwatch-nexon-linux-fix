# 오버워치 넥슨 리눅스 실행 오류 `0xE01300B0` 해결

2026년 8월 12일 넥슨 이관 이후 리눅스(Proton/Wine)에서 오버워치가 실행되지 않고
블리자드 오류 **`0xE01300B0`** 이 뜨는 문제의 해결 스크립트입니다.

**한국어** · [English](README.en.md)

## 증상

- 배틀넷에서 오버워치 실행 → 검은 창이 잠깐 뜨다가 사라짐
- 아래 두 개의 오류창이 순서대로 뜸 (내부 예외는 `0xC06D007E`)
- 재설치, 검사 및 복구, Proton 버전 변경, 셰이더 캐시 삭제 — 전부 무효
- 넥슨 이관 직전까지는 같은 환경에서 정상 플레이됐음

**오류창 1** — 제목 `오버워치`

```
Overwatch has encountered a critical error during startup.
Please reinstall the game and try again.
```

**오류창 2** — 제목 `오버워치`

```
설치한 파일에 문제가 있습니다. 문제가 지속되면 게임을 다시 설치해 주십시오.
(0xE01300B0)

블리자드와 이 문제에 대해 논의할 때 아래의 신고 ID를 사용하십시오.
```

괄호 안의 코드가 `0xE01300B0` 이 아니면 원인이 다를 수 있습니다.

증상이 다르면(로그인은 되는데 매치가 안 잡힌다든가, 그래픽이 깨진다든가)
이 문제가 아닙니다.

## 준비물

```bash
sudo dnf install bubblewrap openssl python3     # Fedora
sudo apt install bubblewrap openssl python3     # Ubuntu / Debian
sudo pacman -S bubblewrap openssl python        # Arch
sudo zypper install bubblewrap openssl python3  # openSUSE
```

`bubblewrap`(`bwrap`)은 대부분 Steam과 함께 이미 깔려 있습니다.

## 1단계 — 설치

```bash
git clone https://github.com/seolcu/overwatch-nexon-linux-fix.git
cd overwatch-nexon-linux-fix
chmod +x overwatch-nexon-linux-fix.sh
./overwatch-nexon-linux-fix.sh install
```

`install` 이 하는 일은 두 가지입니다.

1. **오버워치 Wine 프리픽스를 찾습니다.** Steam(비스팀 게임), Lutris, Bottles,
   Heroic, 순정 wine 위치를 훑어 `gamescale64.dll` 이 있는 프리픽스를 찾습니다.
2. **교차서명 인증서를 프리픽스에 넣고, 신뢰 목록을 만듭니다.** 프리픽스
   레지스트리는 수정 전에 `system.reg.bak-overwatch-nexon-fix` 로 백업합니다.
   신뢰 목록은 `~/.local/share/overwatch-nexon-fix/certs` 에 생성되며 시스템은
   건드리지 않습니다.

성공하면 프리픽스 경로와 함께 런처별 설정 방법을 출력합니다.

### 프리픽스를 못 찾는 경우

프리픽스가 홈 디렉토리 밖(외장 드라이브 등)에 있거나 흔치 않은 위치라면
직접 지정하세요.

```bash
# 먼저 찾아보고
find ~ / -name gamescale64.dll 2>/dev/null

# 나온 경로에서 위로 올라가 system.reg 가 있는 디렉토리가 프리픽스입니다
OW_PREFIX=/경로/to/prefix ./overwatch-nexon-linux-fix.sh install
```

프리픽스가 여러 개 나오면 어느 것인지 알려 주고 멈춥니다. `OW_PREFIX` 로
하나를 골라 주세요.

## 2단계 — 런처에 실행 래퍼 등록

인증서만 넣어서는 안 됩니다. **게임을 실행할 때마다 래퍼를 거쳐야** 합니다.
신뢰 목록 교체가 실행된 프로세스에만 적용되기 때문입니다(그래서 시스템이
안전합니다).

래퍼 명령은 어느 런처에서든 같습니다.

```
/전체/경로/overwatch-nexon-linux-fix.sh run <원래 실행 명령>
```

전체 경로는 `install` 출력이나 `./overwatch-nexon-linux-fix.sh status` 에서
확인할 수 있습니다. 아래에서 본인이 쓰는 런처를 찾으세요.

### Steam에 비스팀 게임으로 추가한 경우 ✅ 검증됨

배틀넷 바로가기 우클릭 → **속성** → **실행 옵션**:

```
/전체/경로/overwatch-nexon-linux-fix.sh run %command%
```

`%command%` 를 빼먹으면 안 됩니다.

### Lutris

게임 우클릭 → **Configure** → **System options** → **Command prefix**:

```
/전체/경로/overwatch-nexon-linux-fix.sh run
```

`run` 까지만 넣습니다. Lutris가 뒤에 실제 명령을 붙여 줍니다.
(System options가 안 보이면 우측 하단 **Advanced** 토글을 켜세요.)

### Heroic Games Launcher

게임 **Settings** → **Advanced** → **Wrapper command / 래퍼 명령**에 추가:

```
/전체/경로/overwatch-nexon-linux-fix.sh run
```

### Bottles

Bottles에는 명령 래퍼 필드가 없습니다. 터미널에서 실행하세요.

```bash
/전체/경로/overwatch-nexon-linux-fix.sh run \
  bottles-cli run -b "보틀이름" -p "Battle.net"

# Flatpak 버전이면
/전체/경로/overwatch-nexon-linux-fix.sh run \
  flatpak run --command=bottles-cli com.usebottles.bottles run -b "보틀이름" -p "Battle.net"
```

매번 치기 번거로우면 위 명령을 `.desktop` 파일이나 셸 별칭으로 만들어 두세요.
터미널 실행이 싫다면 아래 **대안** 을 보세요.

### 순정 wine (터미널에서 직접 실행)

원래 쓰던 명령 앞에 붙이기만 하면 됩니다.

```bash
/전체/경로/overwatch-nexon-linux-fix.sh run \
  env WINEPREFIX=~/.wine wine "C:\\Program Files (x86)\\Battle.net\\Battle.net Launcher.exe"
```

### 대안 — 래퍼를 쓸 수 없을 때

Bottles를 GUI로만 쓰거나, Flatpak 샌드박스 때문에 `bwrap` 중첩이 막히는 경우엔
시스템 신뢰 목록에서 자체서명 인증서를 직접 제외할 수 있습니다.

> ⚠️ **주의할 점 둘**
> - **시스템 전체에 영향을 줍니다.** 브라우저 등 다른 프로그램의 TLS 검증에도
>   적용됩니다. 대부분의 서버는 교차인증서를 함께 보내므로 실사용에 문제는
>   거의 없지만, 래퍼 방식보다 위험합니다.
> - **Steam으로 실행하는 경우엔 효과가 없습니다.** Steam 런타임 컨테이너는
>   호스트가 아니라 자체 런타임 이미지의 인증서를 쓰기 때문입니다. Steam
>   사용자는 반드시 래퍼를 써야 합니다.

```bash
# 제외할 인증서를 꺼냅니다
./overwatch-nexon-linux-fix.sh export-root ./g4.pem

# Fedora / RHEL 계열
sudo cp ./g4.pem /etc/pki/ca-trust/source/blacklist/
sudo update-ca-trust

# Debian / Ubuntu 계열 — 아래 줄 앞에 ! 를 붙이고 저장
sudo sed -i 's|^mozilla/DigiCert_Trusted_Root_G4.crt|!&|' /etc/ca-certificates.conf
sudo update-ca-certificates
```

이 경우에도 **1단계(`install`)는 필요합니다.** 교차서명 인증서가 프리픽스에
들어가야 하기 때문입니다.

되돌리려면 Fedora는 blacklist에서 파일을 지우고, Debian은 `!` 를 떼고
각각 `update-ca-trust` / `update-ca-certificates` 를 다시 실행합니다.

## 확인

```bash
./overwatch-nexon-linux-fix.sh status
```

```
프리픽스 / prefix        : /home/사용자/.local/share/Steam/steamapps/compatdata/…/pfx
교차서명 인증서 / cert   : 설치됨 installed ✓
신뢰 목록 / trust list   : 정상 ok ✓ (292 files)
```

셋 다 ✓ 이고 런처에 래퍼를 넣었다면 게임을 실행하세요.

## 문제 해결

**`install` 이 "wineserver 가 실행 중" 이라며 멈춥니다**
게임·배틀넷·런처·Steam을 모두 종료하세요. 그래도 남아 있으면
`pkill -x wineserver` 로 정리한 뒤 다시 실행합니다.

**"자체서명 DigiCert Trusted Root G4 를 찾지 못했습니다"**
배포판이 이미 그 인증서를 신뢰 목록에서 뺐다는 뜻입니다. 그렇다면 신뢰 목록
교체가 필요 없으니, 1단계만 하고 래퍼 없이 실행해 보세요.

**래퍼를 넣었는데 여전히 `0xE01300B0`**
- `status` 가 셋 다 ✓ 인지 확인하세요.
- Steam이라면 실행 옵션에 `%command%` 가 들어갔는지 확인하세요.
- Flatpak Steam/Bottles/Heroic이라면 샌드박스 안에서 `bwrap` 중첩이 막혔을 수
  있습니다. 네이티브 패키지를 쓰거나 위 **대안** 을 시도하세요.
- 시스템 CA 번들이 갱신되면 신뢰 목록이 자동 재생성되지만, 강제로 다시 만들려면
  `rm -rf ~/.local/share/overwatch-nexon-fix/certs` 후 `install` 을 실행하세요.

**증상이 다릅니다 (로그인 실패, 매치 안 잡힘 등)**
이 문제가 아닙니다. 이 스크립트는 게임이 아예 뜨지 않는 `0xE01300B0` 만 다룹니다.

## 되돌리기

```bash
./overwatch-nexon-linux-fix.sh uninstall
```

프리픽스 레지스트리를 백업에서 복원하고 신뢰 목록을 지웁니다.
**런처의 실행 옵션/래퍼 설정에서도 스크립트를 지워 주세요.**

## 무엇을 하는 스크립트인가

게임은 `gamescale64.dll` 의 서명을 검증하면서 **인증서 체인의 최상단 루트**가
특정 인증서인지까지 확인합니다. 그런데 Wine이 만드는 체인이 윈도우보다 한 칸
짧게 끝나서 이 검사가 실패합니다.

```
윈도우 :  NEXON → G4 코드서명 CA → G4(교차서명본) → DigiCert Assured ID Root CA  ✓
Wine   :  NEXON → G4 코드서명 CA → G4(자체서명본) ■ 종료                          ✗
```

스크립트는 윈도우와 같은 체인이 만들어지도록 공개 교차서명 인증서를 프리픽스에
추가하고, 게임에 보여주는 신뢰 목록에서 자체서명본을 제외합니다.

**서명 검사를 무력화하는 게 아니라 정상적으로 통과시키는 것입니다.** DLL은 진짜
NEXON Korea Corporation 서명 정품이고 그대로 검증됩니다. 게임 파일을 수정하지
않고, 안티치트를 건드리지 않으며, 시스템 신뢰 저장소도 바꾸지 않습니다.

📄 **자세한 원인 분석은 [`docs/ANALYSIS.md`](docs/ANALYSIS.md)** 에 있습니다.
디스어셈블 결과, 인증서 체인 비교, 실패한 시도 목록, Wine 업스트림 이슈까지
정리했습니다.

## 확인된 환경

| | |
|---|---|
| 배포판 | Fedora 44, 커널 7.1.8, KDE Plasma (Wayland) |
| GPU | AMD Radeon RX 7700 XT, Mesa 26.1.6 (RADV) |
| Proton | GE-Proton11-5 / Proton Experimental 11.0, Steam Linux Runtime (steamrt4) |
| 실행 방식 | 배틀넷 런처를 Steam에 비스팀 게임으로 등록 |
| 결과 | 게임 실행 → 로그인 → **매치 진입까지 정상** |

Lutris·Heroic·Bottles·순정 wine 설정은 **직접 검증하지 못했습니다.** 원리는
동일하므로 동작할 것으로 보지만, 각 런처의 설정 항목 이름은 버전에 따라 다를 수
있습니다. 되거나 안 되면 이슈로 알려 주시면 문서에 반영하겠습니다.

## 라이선스 / License

[MIT](LICENSE). 자유롭게 퍼가고 수정하세요. 저작권 표시만 남겨 주세요.

스크립트에 내장된 DigiCert 교차서명 인증서는 DigiCert가 배포하는 공개 CA
인증서이며 MIT 적용 대상이 아닙니다. [NOTICE](NOTICE) 참조.

<sub>
키워드: 오버워치 리눅스, 오버워치 넥슨 리눅스, 오버워치 0xE01300B0, 0xC06D007E,
오버워치 프로톤 실행 안됨, 배틀넷 리눅스, gamescale64.dll, 스팀덱 오버워치,
Overwatch Linux fix, Overwatch Nexon Korea Proton, Overwatch 0xE01300B0,
Battle.net Proton, Steam Deck Overwatch, Wine certificate chain, DigiCert Trusted Root G4.
오류 메시지: "설치한 파일에 문제가 있습니다. 문제가 지속되면 게임을 다시 설치해 주십시오.",
"블리자드와 이 문제에 대해 논의할 때 아래의 신고 ID를 사용하십시오.",
"Overwatch has encountered a critical error during startup. Please reinstall the game and try again."
</sub>
