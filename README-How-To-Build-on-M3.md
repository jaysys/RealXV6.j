# RealXV6 — Apple Silicon (M3) 빌드 가이드

이 문서는 **Apple Silicon (M3) Mac**에서 RealXV6를 빌드하고 QEMU로 실행하는 방법을 설명합니다.

---

## 1. 사전 요구사항

| 도구                         | 용도                                                   | 설치 상태      |
| ---------------------------- | ------------------------------------------------------ | -------------- |
| **Homebrew**                 | 패키지 관리자                                          | 설치 필요      |
| **Open Watcom v2**           | 8086 크로스 컴파일러 (`wcc`, `wasm`, `wlink`, `wmake`) | 설치 필요      |
| **QEMU (i386)**              | 8086 에뮬레이터                                        | 설치 필요      |
| **Xcode Command Line Tools** | 호스트 `gcc`/`clang` (mkfs 빌드용)                     | 설치 필요, Mac |

> **중요**: Open Watcom v2는 Apple Silicon 네이티브 바이너리(`armo64`)를 제공합니다.
> Rosetta 2가 **필요 없습니다**.

---

## 2. Open Watcom v2 설치

### 2.1 Homebrew Tap 설치 (권장)

```bash
brew tap SharkyRawr/homebrew-openwatcom
brew install openwatcom-v2
```

### 2.2 환경 변수 설정

설치 후 셸 환경을 설정합니다:

```bash
. $(brew --prefix)/bin/owenv.sh
```

영구적으로 적용하려면 `~/.zshrc`에 추가합니다:

```bash
echo '. $(brew --prefix)/bin/owenv.sh' >> ~/.zshrc
```

### 2.3 설치 확인

```bash
wcc --version
wmake --version
wasm --version
wlink --version
```

모두 정상적으로 실행되면 준비 완료입니다.

---

## 3. 빌드

### 3.1 전체 빌드 (권장)

최상위 `Makefile`의 `all` 타겟이 **커널, 사용자 프로그램, 부트 이미지를 모두 일괄 빌드**합니다:

```bash
cd /Users/jaehojoo/workspace/os-study/RealXV6.j
wmake clean all
```

이 명령은 다음 순서로 실행됩니다:

```
1. clean        → 루트 + boot/ + usr/ 의 빌드 산출물 일괄 삭제
2. build        → 커널 빌드 (unix.com)
3. cd usr       → 사용자 프로그램 빌드 (*.com)
4. cd boot      → 부트 이미지 생성 (Unix360.img, unix.img)
```

### 3.2 단계별 빌드

전체 빌드 대신 각 단계를 개별적으로 실행할 수도 있습니다:

```bash
# 1. 커널 (unix.com) → 최상위 Makefile
wmake

# 2. 사용자 프로그램 (.com) → usr/Makefile
cd usr && wmake

# 3. 부트 이미지 (.img) → boot/Makefile
cd ../boot && wmake Unix360.img unix.img
```

### 3.3 빌드 산출물 위치

| 산출물 | 위치 | 설명 |
| ------ | ---- | ---- |
| `unix.com` | 루트 | 커널 |
| `dmr/*.obj`, `ken/*.obj` | 소스 폴더 | 커널 오브젝트 파일 (소스 폴더에서 관리) |
| `usr/*.com` | `usr/` | 사용자 프로그램 |
| `boot/boot.com` | `boot/` | 부트 섹터 |
| `boot/Unix360.img` | `boot/` | 부팅 플로피 이미지 |
| `boot/unix.img` | `boot/` | 루트 파일시스템 (하드디스크) 이미지 |

> **참고**: obj 파일은 각 소스 폴더(`dmr/`, `ken/`)에서 생성·관리됩니다. 루트에는 obj가 쌓이지 않습니다.

---

## 4. QEMU로 실행

### 4.1 기본 실행 (터미널 / curses 모드)

```bash
cd boot
wmake q
```

> **참고**: `boot/Makefile`의 `q` 타겟은 `-display curses`를 사용하여 **터미널**에서 VGA 텍스트 모드로 실행됩니다.
> 라운드 가장자리가 없고 키보드 입력이 정상 동작합니다.
> **반드시 실제 터미널에서 실행**하세요 (파이프로 실행하면 "We need a terminal output" 오류가 발생합니다).

또는 직접:

```bash
qemu-system-i386 -display curses \
  -drive file=Unix360.img,format=raw,if=floppy \
  -drive file=unix.img,format=raw,if=ide \
  -boot a
```

### 4.2 macOS 네이티브 창으로 실행 (cocoa 모드)

```bash
qemu-system-i386 -display cocoa \
  -drive file=Unix360.img,format=raw,if=floppy \
  -drive file=unix.img,format=raw,if=ide \
  -boot a
```

> **참고**: `-display cocoa`는 macOS 네이티브 창을 엽니다.
> 창 가장자리가 라운드 처리되어 있어 터미널 입력창 첫 글자가 릴 수 있습니다.
> `wmake q` (curses 모드)를 권장합니다.

### 4.3 원본 RK 디스크 이미지로 실행

```bash
cd boot
wmake qemu
```

> `qemu` 타겟은 `-display cocoa` (네이티브 창)를 사용합니다.
> 이 모드는 새로 빌드한 `unix.img` 대신 **원본 UNIX V6 RK 디스크 이미지**(`unix0_rk.img`)를 루트 파일시스템으로 사용합니다.

---

## 5. 전체 빌드 스크립트

한 번에 모든 것을 빌드하고 실행하려면:

```bash
#!/bin/bash
# build-m3.sh
set -e

cd "$(dirname "$0")"

echo "=== [1/1] 전체 빌드 (커널 + 사용자 프로그램 + 부트 이미지) ==="
wmake clean all

echo "=== 빌드 완료! QEMU로 실행 ==="
cd boot
qemu-system-i386 -display curses \
  -drive file=Unix360.img,format=raw,if=floppy \
  -drive file=unix.img,format=raw,if=ide \
  -boot a
```

---

## 6. 문제 해결

### 6.1 `wmake: Command not found`

환경 변수가 설정되지 않았습니다:

```bash
. $(brew --prefix)/bin/owenv.sh
```

### 6.2 `wcc: Command not found` / `wlink: undefined system name: dos`

Open Watcom이 설치되지 않았거나 PATH에 없습니다. 새 터미널을 열 때마다 환경 변수가 필요합니다:

```bash
brew tap SharkyRawr/homebrew-openwatcom
brew install openwatcom-v2
. $(brew --prefix)/bin/owenv.sh
```

**영구 설정** (권장) — `~/.zshrc`에 추가:

```bash
echo '. /opt/homebrew/opt/openwatcom-v2/bin/owenv.sh' >> ~/.zshrc
```

이후 새 터미널에서도 `wmake`가 바로 동작합니다.

### 6.3 `tools/mkfs` 컴파일 오류

`boot/Makefile`의 mkfs 빌드 규칙은 호스트 `gcc`를 사용합니다.
Xcode Command Line Tools가 설치되어 있는지 확인:

```bash
xcode-select --install
```

### 6.4 QEMU가 설치되지 않은 경우

```bash
brew install qemu
```

### 6.5 `-curses: invalid option` 오류

Homebrew QEMU는 `-curses` 옵션을 지원하지 않습니다. `-display curses` 또는 `-display cocoa`를 사용하세요:

```bash
# boot/Makefile (q 타겟 - 터미널에서 실행)
q: .symbolic Unix360.img unix.img
	qemu-system-i386 -display curses -drive file=Unix360.img,format=raw,if=floppy -drive file=unix.img,format=raw,if=ide -boot a

# boot/Makefile (qemu 타겟 - 네이티브 창)
qemu: .symbolic Unix360.img unix0_rk.img
	qemu-system-i386 -display cocoa -drive file=Unix360.img,format=raw,if=floppy -drive file=unix0_rk.img,format=raw,if=ide -boot a
```

### 6.6 키보드 입력이 안 되는 문제

`-nographic` 옵션은 시리얼 콘솔만 사용하므로 PS/2 키보드 입력이 처리되지 않습니다.
`-display curses` (터미널 VGA 에뮬레이션) 또는 `-display cocoa` (macOS 네이티브 창)를 사용하세요.

### 6.7 QEMU 창 라운드 가장자리로 인한 글자 절림

`-display cocoa`는 macOS 네이티브 창으로 라운드 가장자리가 적용됩니다.
터미널 입력창의 첫 글자가 릴 수 있습니다.

**해결법**: `wmake q`를 사용하세요 (`-display curses` 모드, 라운드 가장자리 없음).

### 6.8 `dd: /dev/zero: No such file or directory`

macOS에서 `/dev/zero`는 항상 존재하므로 이 오류는 발생하지 않습니다.
만약 발생한다면 `boot/Makefile`의 `dd` 명령이 정상인지 확인하세요.

### 6.9 `gunzip: command not found`

macOS에는 기본적으로 `gunzip`이 포함되어 있습니다. 없으면:

```bash
brew install gzip
```

---

## 7. 참고 사항

- **Open Watcom v2**는 `open-watcom/open-watcom-v2` GitHub 저장소에서 관리됩니다.
- Apple Silicon용 바이너리는 `armo64` 디렉토리에, Intel용은 `bino64`에 있습니다.
- Homebrew Tap: `SharkyRawr/homebrew-openwatcom`
- 이 프로젝트의 Makefile은 **GNU make가 아닌 `wmake`** 전용 문법을 사용합니다.
  반드시 `wmake`로 빌드해야 합니다.
- 최상위 `Makefile`의 `all` 타겟은 커널 + 사용자 프로그램 + 부트 이미지를 모두 빌드하며,
  `clean` 타겟은 루트 + `boot/` + `usr/` 의 빌드 산출물을 일괄 삭제합니다.