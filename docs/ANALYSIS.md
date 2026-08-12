# 원인 분석: 한 칸 모자란 인증서 체인

오버워치(넥슨 한국 서비스)가 Proton/Wine에서 `0xE01300B0` 으로 실행 실패하는
문제의 근본 원인 분석입니다. 적용 방법은 [README](../README.md) 를 보세요.

---

## 1. 표면 증상과 실제 예외

사용자에게 보이는 것은 블리자드 오류창 `0xE01300B0` 이지만, 실제로 발생하는 예외는
다릅니다. `Overwatch.exe` 로드 약 1.6초 뒤:

```
seh:dispatch_exception code=c06d007e (unknown) addr=kernelbase.dll+0xD947
seh:RtlUnwindEx code=c06d007e target_ip=Overwatch.exe+0x57F62B
```

`0xC06D007E` = `VcppException(ERROR_SEVERITY_ERROR, ERROR_MOD_NOT_FOUND)`.
MSVC 지연 로딩(delay-load) 헬퍼가 "지연 로딩 모듈을 찾을 수 없다"고 던지는 예외입니다.

## 2. 이상한 점: 로드 시도 자체가 없다

`+module` 채널을 켜고 뽑은 로그에 **`load_dll looking for L"gamescale64.dll"` 이
전혀 없습니다.** 프로세스 전체에서 실패한 모듈 로드는 `wineoss.drv` /
`winecoreaudio.drv` (오디오 백엔드 탐색, 정상 동작) 둘뿐입니다.

파일은 존재하고, 열리고, 서명 검증까지 통과합니다. 그런데 로드 요청이 Wine 로더에게
**한 번도 가지 않습니다.**

안티치트의 수동 매핑(manual mapping)을 의심할 수 있지만, `+virtual` 채널로 확인한
결과 그 흔적도 없습니다.

| 확인 항목 | 결과 |
|---|---|
| `trace:virtual` 12,745줄 중 실패 | 0건 |
| `NtCreateSection` 호출 | 0회 |
| RWX / 실행 권한 할당 | 0건 (전부 `PAGE_READWRITE`, `PAGE_READONLY`) |
| `warn:virtual` / `err:virtual` | 0건 |

## 3. 바이너리가 답을 알려준다

크래시 백트레이스는 6프레임입니다.

```
kernelbase.dll + 0xD977          ← RaiseException
Overwatch.exe  + 0x57AFF0
Overwatch.exe  + 0x57AF97
Overwatch.exe  + 0x2A00648
Overwatch.exe  + 0x2A004E9
Overwatch.exe  + 0x57F649
```

`Overwatch.exe+0x57AF97` 은 `call` 바로 다음 주소입니다. 그 직전 명령을 보면:

```asm
14057af88:  ba 82 04 00 00       mov    $0x482,%edx      ; ← 하드코딩 상수
14057af8d:  48 8d 4c 24 20       lea    0x20(%rsp),%rcx
14057af92:  e8 29 00 00 00       call   0x14057afc0      ; → RaiseException(0xC06D007E)
14057af97:  cc                   int3                    ; ← 백트레이스의 이 프레임
```

`dli.dwLastError` 가 `GetLastError()` 가 아니라 **박아넣은 값 `0x482`**
(`ERROR_INVALID_DLL`) 입니다. 무언가 실패해서 나는 예외가 아니라 **의도적으로
거부하는 분기**라는 뜻입니다. 예외 레지스터 덤프의 `rbx=0000000000000482` 와도
일치합니다.

### 커스텀 지연 로딩 헬퍼

거꾸로 타고 올라가면 제어 흐름이 드러납니다.

```
RVA 0x57AE42  GetModuleFileNameW(NULL, buf, MAX_PATH)   ← 자기 경로
              XOR 난독화된 구분자로 디렉토리까지 절단
              지연 로딩 DLL 이름 이어붙임 → ...\_retail_\gamescale64.dll
RVA 0x57AF0F  GetFileAttributesW(fullpath)              ← 존재 확인 (통과)
RVA 0x57AF1F  call sub_14057E210                        ← BOOL 서명 검증
RVA 0x57AF26    test al,al / je 0x57AF88
RVA 0x57AF88      mov $0x482,%edx → RaiseException(0xC06D007E)   ★ 크래시
RVA 0x57AF2D  LoadLibraryW(fullpath)                    ← 검증 통과해야만 도달
```

**`LoadLibraryW` 에 도달하지 못하기 때문에** 로그에 로드 시도가 없었던 것입니다.
Wine 로더 버그도, 수동 매핑도 아니었습니다.

## 4. 검증 함수가 확인하는 것

`sub_14057E210` 의 판정 순서:

```
① WinVerifyTrust(WINTRUST_ACTION_GENERIC_VERIFY_V2)   == 0 필요
② WTHelperProvDataFromStateData(hState)               != NULL 필요
③ WTHelperGetProvSignerFromChain(pData, 0, FALSE, 0)  != NULL 필요
④ pSigner->pChainContext (offset 0x38) 순회:
     cChain (0x0C) != 0 필요
     rgpChain[i]->TrustStatus.dwErrorStatus (0x04) == 0 필요
     cElement (0x0C) != 0 필요
     ★ SHA-1(rgpElement[cElement-1]->pCertContext->pbCertEncoded)
       == 하드코딩된 핀 값 1개
⑤ 전 체인 불일치 → WinVerifyTrust(dwStateAction=2, CLOSE) → return FALSE
```

즉 **체인의 마지막 인증서(루트)의 DER 전체를 SHA-1 해시해서 핀된 값과 비교**합니다.
전형적인 루트 인증서 피닝입니다.

핀 값은 즉치 상수 5개로 박혀 있습니다
(RVA `0x57E234` / `0x57E23E` / `0x57E279` / `0x57E281` / `0x57E289`):

```asm
movl $0x63b86305,0x48(%rsp)
movl $0x5ad7620d,0x4c(%rsp)
movl $0x1eabc8bb,0x50(%rsp)
movl $0xa8b5df4b,0x54(%rsp)
movq $0x434db299,0x58(%rsp)
```

리틀엔디언으로 조립하면:

```
0563B863 0D62D75A BBC8AB1E 4BDFB5A8 99B24D43
= SHA-1 of "DigiCert Assured ID Root CA"
```

## 5. 함정: `DigiCert Trusted Root G4` 가 두 개다

이름도 같고 공개키도 같고 Subject Key ID까지 같은 인증서가 두 버전 존재합니다.

| | SHA-1 | 발급자 |
|---|---|---|
| 자체서명본 | `DDFB16CD4931C973A2037D3FC83A4D7D775D05E4` | 자기 자신 |
| 교차서명본 | `A99D5B79E9F1CDA59CDAB6373169D5353F5874C6` | DigiCert Assured ID Root CA |

DigiCert가 일부러 만든 것입니다. 새 루트(G4)를 모르는 구형 시스템에서도 옛 루트
(Assured ID)를 통해 신뢰가 이어지도록 하기 위해서입니다.

결과적으로 같은 DLL이 두 갈래 족보를 가질 수 있습니다.

```
윈도우 :  NEXON Korea Corporation                      98B44893…
            → DigiCert Trusted G4 Code Signing CA1     7B0F360B…
              → DigiCert Trusted Root G4 (교차서명본)   A99D5B79…
                → DigiCert Assured ID Root CA          0563B863…  ← 4단계, 핀 일치 ✓

Wine   :  NEXON Korea Corporation                      98B44893…
            → DigiCert Trusted G4 Code Signing CA1     7B0F360B…
              → DigiCert Trusted Root G4 (자체서명본)   DDFB16CD…  ← 3단계, 종료 ✗
```

`gamescale64.dll` 의 PKCS#7에는 리프와 중간 인증서만 들어 있고 루트는 없습니다.
루트는 신뢰 저장소에서 와야 하는데, 여기서 갈립니다.

## 6. Wine이 짧은 쪽을 고르는 이유

두 가지가 겹칩니다.

- **리눅스 CA 번들에는 자체서명 트러스트 앵커만 들어 있습니다.** 교차인증서는 담지
  않습니다. Wine의 crypt32는 호스트 CA 번들(`/etc/ssl/certs` 등)에서 루트를 자동
  임포트하므로 자체서명 G4를 갖게 됩니다.
- **Wine의 체인 빌더는 처음 찾은 신뢰 루트에서 종료합니다.** 윈도우는 가능한 체인을
  모두 만들어 품질 점수로 고르는데, Wine은 대안 경로를 열거하지 않습니다.

`+chain` 로그가 이를 그대로 보여줍니다.

```
chain:CRYPT_GetIssuer issuer found by key id
chain:CRYPT_CheckSimpleChain checking chain with 3 elements
chain:CertGetCertificateChain error status: 00000000
wintrust:WinVerifyTrust returning 00000000
wintrust:WTHelperGetProvSignerFromChain returning 000000000030E330
wintrust:WinVerifyTrust dwStateAction=2 (CLOSE) -> 0
seh:dispatch_exception code=c06d007e
```

`issuer found by key id` — 두 G4가 Subject Key ID까지 같으니 키 ID로는 구분이 안 되고,
저장소에서 먼저 나온 쪽이 채택됩니다.

**중요한 점: 서명 검증 자체는 완벽히 정상입니다.** `WinVerifyTrust` 가 0을 반환하고
체인의 `dwErrorStatus` 도 `0x00000000` 입니다. 인증서 유효기간도 정상입니다
(리프 2025-02-18 ~ 2028-02-13, 중간 ~2036-04-28). **다른 것은 체인의 종착점 하나뿐입니다.**

## 7. 재현 케이스

게임의 검사 ①~④를 그대로 재현하는 프로그램을 mingw로 작성해 확인했습니다.
`WinVerifyTrust` → `WTHelperProvDataFromStateData` → `WTHelperGetProvSignerFromChain`
을 게임과 동일한 플래그(`WTD_UI_NONE`, `WTD_REVOKE_NONE`, `WTD_CHOICE_FILE`,
`dwProvFlags=0x2000`)로 호출하고 체인을 덤프합니다.

수정 전:

```
[1] WinVerifyTrust           -> 0x00000000 (PASS)
[2] ProvDataFromStateData    -> ... (PASS)
[3] GetProvSignerFromChain   -> ... (PASS)
    cChain                   =  1 (PASS)
  TrustStatus.dwErrorStatus  =  0x00000000 (PASS)
  cElement                   =  3
    [0] NEXON Korea Corporation                   98B44893…
    [1] DigiCert Trusted G4 Code Signing … CA1    7B0F360B…
    [2] DigiCert Trusted Root G4   <-- ROOT       DDFB16CD…
RESULT: pinned root NOT MATCHED
```

**검사가 전부 통과하고 마지막 핀 비교에서만 어긋납니다.**

수정 후 (실제 게임 경로 = Steam Linux Runtime 컨테이너 + GE-Proton11-5 + 게임 프리픽스):

```
  cElement                   =  4
    [2] DigiCert Trusted Root G4                  A99D5B79…
    [3] DigiCert Assured ID Root CA  <-- ROOT     0563B863…
RESULT: pinned root MATCHED -> game would call LoadLibraryW()
```

## 8. 해결 원리

지름길을 없애서 윈도우와 같은 족보를 만들게 합니다.

1. 공개 교차서명 인증서를 프리픽스의 **중간 CA 저장소**에 설치
2. 게임에 보여주는 신뢰 목록에서 **자체서명 G4만 제외**

이러면 신뢰 앵커로 가는 길이 교차인증서 하나뿐이라, Wine이 한 칸 더 올라가
`DigiCert Assured ID Root CA` 에 도달합니다.

교차서명 인증서는 게임 폴더의 `bink2w64.dll` 서명에 마침 포함돼 있어 거기서
추출했습니다. 공개 DigiCert 인증서이므로 재배포에 문제가 없습니다.

## 9. 실패한 시도들

| 시도 | 결과 |
|---|---|
| 교차인증서를 `CA` 저장소에만 추가 | 무효. 자체서명 G4가 여전히 먼저 잡힘 |
| 교차인증서를 `Root` 저장소에 추가 | 무효. Subject Key ID가 같아 구분 안 됨 |
| 자체서명 G4를 `Disallowed` 저장소에 등록 | Wine이 체인 구성에 반영하지 않음 |
| 프리픽스 Root에서 자체서명 G4 삭제 | 실행할 때마다 호스트 번들에서 자동 재임포트 |
| `CertCreateCertificateChainEngine(hExclusiveRoot)` | Wine 미구현, `E_INVALIDARG` |
| 동 `hRestrictedRoot` | 역시 `E_INVALIDARG` |
| 호스트 CA 번들만 수정 | **무효.** 컨테이너는 런타임 이미지 인증서를 사용 |
| `bwrap` 바인드만 (`IMPORT_CA_CERTS` 없이) | 컨테이너까지 전파되지 않음 |
| `gamescale64.dll` 삭제 / 이동 | 동일 실패 |
| Proton 버전 변경, 재설치, 셰이더 캐시 삭제 | 무관 |
| `PROTON_USE_WINED3D=1`, `PROTON_FSR4_UPGRADE` | 무관 (그래픽 초기화 전에 종료) |
| SELinux `setenforce 0` | 무관 (AVC 거부 없음) |

### 컨테이너의 함정

Proton은 pressure-vessel 컨테이너 안에서 실행되고, 컨테이너의 신뢰 저장소는
**호스트가 아니라 런타임 이미지**(`/usr/share/ca-certificates/mozilla/`)에서 옵니다.
따라서 호스트 트러스트 스토어를 아무리 고쳐도 게임에는 영향이 없습니다.

이를 뚫는 열쇠가 `PRESSURE_VESSEL_IMPORT_CA_CERTS=1` 입니다. 이 변수를 켜면
pressure-vessel이 호스트 인증서를 컨테이너로 가져오고, 그때 `bwrap` 으로 호스트측
`/etc/ssl/certs` 를 바꿔치기하면 컨테이너 신뢰 목록을 통제할 수 있습니다.
단 pressure-vessel은 c_rehash 레이아웃과 `ca-certificates.crt` 를 **둘 다** 요구합니다.

## 10. 부수적으로 확인된 사실

- **`gamescale64.dll` 은 안티치트가 아닙니다.** 지연 로딩 임포트 17개의 이름을 보면
  넥슨의 GameScale 플랫폼 SDK입니다: `auth::SignIn/SignOut/GetUserInfo`,
  `billing::Purchase/Restore`, `push::PushInit`, `localization::SetLocale`,
  `lifecycle::CreateInstance/Tick`, `service::Initialize`, `support::GetLaunchMode`.
  검증 코드에도 Wine 탐지 로직은 없습니다. 순수한 변조 방지 서명 검사입니다.
- `Overwatch.exe` 의 지연 로딩 DLL은 `dbghelp.dll`, `gamescale64.dll`, `grap64.dll`
  셋뿐입니다. `grap64.dll` 은 gamescale64보다 뒤이므로 도달하지 않습니다.
- `NtUserSystemParametersInfo` 의 `SPI_SETSTICKYKEYS` / `SETTOGGLEKEYS` /
  `SETFILTERKEYS` 미구현 fixme가 로그에 나타나지만(WineHQ bug 59927과 동일),
  **크래시 1.3초 뒤 종료 경로**에서 발생하므로 이 문제와 무관합니다.

## 11. 근본 해결 (Wine 업스트림)

이 저장소의 스크립트는 우회책입니다. 진짜 고쳐야 할 곳은 Wine `crypt32` 입니다.

- `CertGetCertificateChain` 이 교차인증서를 통한 대체 경로를 후보로 고려하지 않음.
  윈도우는 가능한 체인을 모두 구성해 품질 점수로 선택하지만, Wine은 처음 찾은
  신뢰 루트에서 종료합니다.
- `CertCreateCertificateChainEngine` 의 `hExclusiveRoot` / `hRestrictedRoot` 미구현
  (`E_INVALIDARG` 반환). 애플리케이션이 신뢰 루트를 제한할 수 없습니다.

업스트림에서 고쳐지면 이 스크립트는 필요 없어집니다.

## 부록: 조사에 쓴 로그 채널

```bash
# 1차 — 모듈 로드 추적
PROTON_LOG="+timestamp,+pid,+tid,+seh,+unwind,+loaddll,+module" %command%

# 2차 — 수동 매핑 가설 검증 (가설 기각)
PROTON_LOG="+timestamp,+pid,+tid,+seh,+virtual,+ntdll" %command%

# 3차 — 인증서 체인 (원인 확정)
PROTON_LOG="+timestamp,+pid,+tid,+seh,+chain,+crypt,+wintrust,+cryptasn" %command%
```

로그는 수백 MB가 되므로 통째로 열지 말고 pid로 잘라서 보세요.
크래시 프로세스는 `grep -n 'c06d007e'` 로 찾을 수 있습니다.
