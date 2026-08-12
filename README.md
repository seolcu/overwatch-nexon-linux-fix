# 오버워치 넥슨 리눅스 실행 오류 `0xE01300B0` 해결

2026년 8월 12일 넥슨 이관 이후 리눅스(Proton/Wine)에서 오버워치가 실행되지 않고
블리자드 오류 **`0xE01300B0`** 이 뜨는 문제의 해결 스크립트입니다.

> Fix for **Overwatch (Nexon Korea) failing to launch on Linux with Blizzard error
> `0xE01300B0`** under Proton/Wine. See [English](#english) below.

## 증상

- 배틀넷에서 오버워치 실행 → 검은 창이 잠깐 뜨다가 사라짐
- 블리자드 오류창 **`0xE01300B0`** (내부 예외 `0xC06D007E`)
- 재설치, 검사 및 복구, Proton 버전 변경, 셰이더 캐시 삭제 — 전부 무효
- 넥슨 이관 직전까지는 같은 환경에서 정상 플레이됐음

## 적용 방법

**1. 필요 패키지**

```bash
sudo dnf install bubblewrap openssl python3     # Fedora
sudo apt install bubblewrap openssl python3     # Ubuntu / Debian
sudo pacman -S bubblewrap openssl python        # Arch
```

**2. 설치**

```bash
git clone https://github.com/seolcu/overwatch-nexon-linux-fix.git
cd overwatch-nexon-linux-fix
chmod +x overwatch-nexon-linux-fix.sh
./overwatch-nexon-linux-fix.sh install
```

프리픽스는 자동으로 찾습니다. 못 찾으면 `OW_PREFIX` 로 지정하세요.

**3. Steam 실행 옵션**

배틀넷 바로가기 → 속성 → 실행 옵션에 아래를 입력합니다.
경로는 `install` 이 출력해 준 것을 그대로 쓰세요.

```
/전체/경로/overwatch-nexon-linux-fix.sh run %command%
```

끝입니다. 게임을 실행하세요.

## 확인 / 되돌리기

```bash
./overwatch-nexon-linux-fix.sh status      # 상태 확인
./overwatch-nexon-linux-fix.sh uninstall   # 되돌리기
```

되돌릴 때는 Steam 실행 옵션에서 스크립트도 함께 지워 주세요.

## 무엇을 하는 스크립트인가

게임은 `gamescale64.dll` 의 서명을 검증하면서 **인증서 체인의 최상단 루트**가
특정 인증서인지까지 확인합니다. 그런데 Wine이 만드는 체인이 윈도우보다 한 칸 짧게
끝나서 이 검사가 실패합니다. 스크립트는 윈도우와 같은 체인이 만들어지도록
공개 교차서명 인증서를 프리픽스에 추가하고, 게임에 보여주는 신뢰 목록을 조정합니다.

서명 검사를 무력화하는 게 아니라 **정상적으로 통과시키는 것**입니다. 게임 파일을
수정하지 않고, 안티치트를 건드리지 않으며, 시스템 신뢰 저장소도 바꾸지 않습니다.

📄 **자세한 원인 분석과 조사 과정은 [`docs/ANALYSIS.md`](docs/ANALYSIS.md) 에 있습니다.**
디스어셈블 결과, 인증서 체인 비교, 실패한 시도 목록, Wine 업스트림 이슈까지 정리했습니다.

## 동작 확인된 환경

- Fedora 44, 커널 7.1.8, KDE Plasma (Wayland)
- AMD Radeon RX 7700 XT, Mesa 26.1.6 (RADV)
- GE-Proton11-5 / Proton Experimental 11.0, Steam Linux Runtime (steamrt4)
- 배틀넷 런처를 Steam에 비스팀 게임으로 등록한 구성
- 게임 실행 → 로그인 → **매치 진입까지 정상 확인**

다른 환경에서 되거나 안 되면 이슈로 알려주세요.

<a name="english"></a>

## English

Since Overwatch's Korean service moved to **Nexon** on 2026-08-12, the game fails to
launch under **Proton/Wine on Linux** with Blizzard error **`0xE01300B0`** (internally
exception `0xC06D007E`). Reinstalling, Scan and Repair, switching Proton builds, and
clearing shader caches have no effect.

`Overwatch.exe` verifies the Authenticode signature of `gamescale64.dll` and **pins the
SHA-1 of the certificate chain's root certificate**. Windows builds a 4-element chain
ending at `DigiCert Assured ID Root CA`; Wine stops one certificate short at the
self-signed `DigiCert Trusted Root G4`, so the pin fails.

This script makes Wine build the same chain Windows does. It does not patch the game,
disable the signature check, or touch anti-cheat.

```bash
sudo apt install bubblewrap openssl python3      # or dnf / pacman
./overwatch-nexon-linux-fix.sh install
```

Then set Steam launch options for the Battle.net shortcut:

```
/full/path/overwatch-nexon-linux-fix.sh run %command%
```

📄 Full root-cause analysis in [`docs/ANALYSIS.md`](docs/ANALYSIS.md).

## 라이선스 / License

Public domain ([CC0 1.0](LICENSE)). 자유롭게 퍼가고 수정하세요.

<sub>
키워드: 오버워치 리눅스, 오버워치 넥슨 리눅스, 오버워치 0xE01300B0, 0xC06D007E,
오버워치 프로톤 실행 안됨, 배틀넷 리눅스, gamescale64.dll, 스팀덱 오버워치,
Overwatch Linux fix, Overwatch Nexon Korea Proton, Overwatch 0xE01300B0,
Battle.net Proton, Steam Deck Overwatch, Wine certificate chain, DigiCert Trusted Root G4.
</sub>
