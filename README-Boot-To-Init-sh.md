## 두 asm 소스의 차이와 역할

### 1. `boot/bootsect.asm` — 부트 섹터 (부트로더)

**역할**: BIOS가 플로피 첫 섹터(부트 섹터)를 메모리에 로드한 후 실행되는 **1단계 부트로더**입니다.

- BIOS `INT 13h`를 사용해 플로피 디스크의 **블록 1~119**에서 커널(`unix.com`)을 메모리 `0x1000:0x0100`에 로드합니다.
- LBA(논리 블록 주소) → CHS(실린더/헤드/섹터) 변환을 수행합니다 (9섹터/트랙, 2헤드).
- 로드 완료 후 `retf`(far jump)로 커널 엔트리(`0x1000:0x0100`)로 점프합니다.
- 마지막에 `0xAA55` 부트 시그니처를 포함하여 BIOS가 부팅 가능한 섹터로 인식하게 합니다.

**빌드되는 바이너리**: `boot.com`

```
wasm -bt=DOS -mt -1 bootsect.asm -fo=bootsect.obj
wlink ... NAME boot.com
```

이 `boot.com`은 `Unix360.img` 플로피 이미지의 **첫 섹터(블록 0)**에 배치됩니다.

---

### 2. `usr/boots.asm` — init 부트 스텁 (대체용)

**역할**: 커널이 부팅 후 첫 사용자 프로세스로 `init`을 실행하기 위한 **부트스트랩 프로그램**입니다.

- `exec("init")` 시스템 콜(`INT 129` = 0x81)을 직접 호출하는 아주 작은 어셈블리 코드입니다.
- `argv` 배열(`["init", NULL]`)을 스택에 push하고 `sys_exec`(번호 11)를 호출합니다.

**빌드되는 바이너리**: **없음 (빌드되지 않음)**

`usr/Makefile`의 `BINS` 목록에 `boots.asm`이 포함되어 있지 않으며, 어떤 타겟에서도 참조되지 않습니다. 이 파일은 **커널 내장 `icode[]` 배열의 대체용 참고 소스**입니다.

실제로는 `ken/main.c`의 `icode[]` 배열이 동일한 역할을 수행합니다:

```c
char icode[] = {
    0xB8, 0x12, 0x01, 0x50, 0xB8, 0x0D, 0x01, 0x50,
    0xBA, 0x0B, 0x00, 0xCD, 0x81, 0x69, 0x6E, 0x69,
    0x74, 0x00, 0x0D, 0x01, 0x00, 0x00
};
// MOV AX, argv; PUSH AX; MOV AX, prog; PUSH AX; MOV DX, 11; INT 81h; "init\0"; argv
```

커널 `main()`이 `newproc()`으로 init 프로세스를 만들고, 이 `icode[]`를 사용자 메모리 `0x100`에 복사한 후 실행하여 `exec("init")`을 호출합니다.

---

## 실행 순서

```
BIOS 부팅
   │
   ▼
① boot.com (bootsect.asm)  ←── 먼저 수행
   │  BIOS INT 13h로 플로피 블록 1~119에서 unix.com(커널)을 0x1000:0x0100에 로드
   │  far jump로 커널 엔트리 진입
   ▼
② unix.com (커널, dmr/m86.asm + ken/*.c)
   │  pc_init() → cinit() → binit() → iinit() → 루트 마운트
   │  newproc()으로 init 프로세스 생성
   │  icode[] (또는 usr/boots.asm과 동일한 코드)를 사용자 메모리에 복사
   ▼
③ init.com (첫 사용자 프로세스)
   │  exec("init") 시스템 콜로 시작
   │  콘솔 열기, 시그널 처리, /bin/sh를 fork/exec
   ▼
④ sh.com (셸) → cat, ls, grep, ed, ps, ...
```

**결론**:

- **`boot/bootsect.asm` → `boot.com`** 이 **먼저 수행**되는 실제 부트로더입니다.
- **`usr/boots.asm`** 은 빌드되지 않는 참고용 소스로, 커널 내장 `icode[]` 배열이 동일한 역할(init 부트 스텁)을 대신 수행합니다.

---

## 부팅 후 셸 프롬프트가 표시되는 지점

### 직접 출력 지점: `usr/sh.c`

프롬프트는 **`usr/sh.c`의 `getcmd()` 함수**에서 출력됩니다.

**① 프롬프트 문자열 정의 (151행)**

```c
char *prompt = "$ ";
```

**② 프롬프트 실제 출력 (getcmd 함수, 153~162행)**

```c
int
getcmd(char *buf, int nbuf)
{
  fprintf(2, prompt);      // ← 프롬프트를 stderr(fd 2)로 출력
  memset(buf, 0, nbuf);
  gets(buf, nbuf);
  if(buf[0] == 0) /* EOF */
    return -1;
  return 0;
}
```

- `fprintf(2, prompt)` — 파일 디스크립터 2(stderr)로 `"$ "`를 출력합니다. fd 2는 init이 `/dev/console`을 열고 `dup(0)`으로 복제한 것이므로 **콘솔(터미널)에 표시**됩니다.

**③ main() 루프 (166~187행)**

```c
int main()
{
    static char buf[100];

    if(getuid() == 0) prompt[0] = '#';   // root면 '#' 프롬프트
    while(getcmd(buf, sizeof(buf)) >= 0){ // ← 여기서 매 반복마다 프롬프트 출력
        ...
    }
    return 0;
}
```

- `getuid() == 0`(root)이면 프롬프트가 `#`, 일반 사용자면 `$`가 표시됩니다.
- `while` 루프에서 명령을 한 번 실행하고 나면 다시 `getcmd()`가 호출되어 **프롬프트가 반복 출력**됩니다.

---

### 부팅 → 프롬프트 표시까지의 전체 흐름

```
boot/bootsect.asm (boot.com)
   │  BIOS INT 13h로 커널(unix.com) 로드
   ▼
ken/main.c — printk("Unix Ready.\r\n")
   │  newproc() → icode[]를 사용자 메모리에 복사
   ▼
icode[] (exec("init") 시스템 콜)
   ▼
usr/init.c — main()
   │  콘솔(/dev/console) open → dup(0)로 stdout/stderr 복제
   │  printf("init: starting sh\n")        ← 31행
   │  fork() → exec("/bin/sh", argv)       ← 38행
   ▼
usr/sh.c — main() (166행)
   │  getuid() == 0 → prompt[0] = '#'      ← 170행
   ▼
usr/sh.c — getcmd() (153행)
   │  fprintf(2, prompt)                   ← 156행  ★ 프롬프트 출력
   ▼
   터미널에 "$ " 또는 "# " 표시
```

**핵심 요약**: 셸 프롬프트가 터미널에 보이게 되는 지점은 **`usr/sh.c` 156행의 `fprintf(2, prompt)`** 입니다. 이 출력은 `usr/init.c`가 `/dev/console`을 fd 0/1/2로 연결해 준 덕분에 터미널 화면에 표시됩니다. 루트로 부팅하면 `#`, 일반 사용자 셸이면 `$`가 보입니다.
