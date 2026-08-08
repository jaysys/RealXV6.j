# RealXV6.j 소스 분석

RealXV6는 **UNIX V6 커널을 Intel 8086 PC(리얼 모드)로 포팅한 프로젝트**입니다. PDP-11용으로 작성된 고전 V6 커널의 구조와 알고리즘을 최대한 보존하면서, 8086 아키텍처에 맞게 이식되었습니다. 사용자 공간은 원본 V6 프로그램과 xv6 프로젝트의 프로그램이 혼합되어 있습니다.

## 디렉토리 구조

| 디렉토리 | 역할                                                                            |
| -------- | ------------------------------------------------------------------------------- |
| `h/`     | 커널 헤더 — 핵심 데이터 구조와 상수 정의                                        |
| `ken/`   | 기계 독립 커널 (Ken Thompson) — 시스템 콜, 프로세스 관리, 파일시스템, 스케줄러  |
| `dmr/`   | 기계 의존 코드 (Dennis M. Ritchie) — 저수준 엔트리/컨텍스트 스위치, PC 드라이버 |
| `usr/`   | 사용자 프로그램과 소형 libc                                                     |
| `boot/`  | 부트 섹터, 파일시스템 프로토타입, 에뮬레이터/이미지 빌드                        |
| `tools/` | 호스트 측 유틸리티 (파일시스템 이미지 빌더 `mkfs`)                              |

---

## 1. h/ — 커널 헤더 파일

### h/buf.h — 버퍼 캐시 / 블록 I/O 서브시스템

- `struct buf` — 버퍼 헤더. 각 버퍼는 장치 리스트(`b_forw`/`b_back`)와 자유 리스트(`av_forw`/`av_back`)에 이중 연결됨. `b_flags`(상태 플래그), `b_dev`(장치 번호), `b_wcount`(전송 워드 수), `b_addr`/`b_xmem`(코어 주소), `b_blkno`(블록 번호), `b_error`(I/O 오류 코드) 필드 포함.
- `struct devtab` — 블록 장치별 상태: 활성 플래그, 오류 카운트, 버퍼 리스트 헤드, I/O 큐.
- 버퍼 플래그 상수: `B_WRITE`, `B_READ`, `B_DONE`, `B_ERROR`, `B_BUSY`, `B_PHYS`, `B_MAP`, `B_WANTED`, `B_RELOC`, `B_ASYNC`, `B_DELWRI`.
- 전역: `buf[NBUF]` 버퍼 풀, `bfreelist` 자유 리스트 헤드.
- **담당 서브시스템**: 블록 I/O — 버퍼 캐시, 장치 I/O 큐, 자유 버퍼 관리 (`bio.c`와 블록 장치 드라이버가 사용).

### h/conf.h — 장치 설정 (디바이스 스위치 테이블)

- `struct dev_t` — 장치 코드를 major/minor로 분해.
- `struct bdevsw` — 블록 장치 스위치: open/close/strategy 함수 포인터 + devtab.
- `struct cdevsw` — 문자 장치 스위치: open/close/read/write/sgtty 함수 포인터.
- 매크로: `minor(x)`, `major(x)`, `makedev(ma,mi)`.
- 전역: `bdevsw[]`, `cdevsw[]`, `nblkdev`, `nchrdev`.
- **담당 서브시스템**: 장치 드라이버 구성 — 커널과 드라이버를 연결하는 디스패치 테이블.

### h/file.h — 열린 파일 테이블

- `struct file` — 프로세스가 연 파일 구조체. 파일 오프셋, 아이노드 포인터, 읽기/쓰기 플래그(`FREAD`/`FWRITE`), 파이프 플래그(`FPIPE`), 참조 카운트 포함.
- **담당 서브시스템**: 파일 디스크립터 관리 — `fio.c`, `sys2.c` 등에서 사용.

### h/filsys.h — 디스크 상 슈퍼블록

- `struct filsys` — 파일시스템의 슈퍼블록. `s_isize`(아이노드 영역 크기), `s_fsize`(전체 블록 수), `s_nfree`/`s_free[100]`(자유 블록 리스트), `s_ninode`/`s_inode[100]`(자유 아이노드 리스트), `s_flock`/`s_ilock`(락), `s_fmod`(수정 플래그), `s_time[2]`(마지막 수정 시간).
- **담당 서브시스템**: 파일시스템 — 블록/아이노드 할당의 근간 (`alloc.c`가 사용).

### h/ino.h — 디스크 상 아이노드

- `struct inode` — 디스크에 저장되는 아이노드 형식. `i_mode`(파일 타입/권한), `i_nlink`(링크 수), `i_uid`/`i_gid`(소유자), `i_size0`/`i_size1`(파일 크기), `i_addr[8]`(데이터 블록 주소), `i_time[4]`(타임스탬프).
- 모드 상수: `IALLOC`, `IFMT`, `IFDIR`, `IFCHR`, `IFBLK`, `ISUID`, `ISGID`, `IREAD`, `IWRITE`, `IEXEC`.
- **담당 서브시스템**: 파일시스템 — 디스크 상 파일 메타데이터.

### h/inode.h — 인코어 아이노드

- `struct inode` — 메모리 상주 아이노드. 디스크 아이노드 필드 + `i_flag`(상태 플래그), `i_count`(참조 카운트), `i_dev`/`i_number`(장치/번호), `i_lastr`(순차 읽기 최적화) 등.
- 플래그: `ILOCK`, `IUPD`, `IACC`, `IMOUNT`, `IWANT`, `ITEXT`.
- 전역: `inode[NINODE]` 인코어 아이노드 테이블.
- **담당 서브시스템**: 파일시스템 — 아이노드 캐시 (`iget.c`, `iput.c`가 사용).

### h/os.h — 마스터 인클루드

- 커널 전체가 공통으로 포함하는 헤더. `pc.h`, `param.h`, `reg.h`, `text.h`, `buf.h`, `conf.h`, `inode.h`, `filsys.h`, `file.h`, `user.h`, `proc.h`, `tty.h`, `systm.h`를 순서대로 인클루드.
- **담당 서브시스템**: 커널 전역 — 모든 커널 소스의 공통 헤더.

### h/param.h — 튜너블 상수

- 버퍼/테이블 크기: `NBUF`(15), `NINODE`(100), `NFILE`(100), `NMOUNT`(5), `NPROC`(50), `NTEXT`(40), `NCLIST`(100), `NCALL`(20).
- 메모리: `MAXMEM`(64\*32 워드), `SSIZE`/`SINCR`(스택 크기), `USIZE`(16 페이지), `PAGESIZ`(4096), `USPACE`(0x20), `USTACK`(0xF000).
- 스케줄링 우선순위: `PSWP`(-100), `PINOD`(-90), `PRIBIO`(-50), `PPIPE`(1), `PWAIT`(40), `PSLEP`(90), `PUSER`(100).
- 시그널 번호: `NSIG`(20), `SIGHUP`~`SIGPIPE`(1~13).
- 기타: `HZ`(60 틱/초), `ROOTINO`(1), `DIRSIZ`(14), `NODEV`(-1).
- `struct hilo_t`/`struct integ_t` — 정수를 바이트 단위로 접근하는 구조체.
- **담당 서브시스템**: 커널 전역 — 시스템 전체 튜닝 파라미터.

### h/pc.h — PC/x86 플랫폼 매크로

- `typedef unsigned uint` 등 기본 타입 정의.
- `FP_OFF`/`FP_SEG` — far 포인터 분해 매크로.
- `disable()`/`enable()` — 인터럽트 금지/허용.
- `MK_FP(seg, off)` — 세그먼트/오프셋으로 far 포인터 생성.
- `#pragma pack(1)` — 구조체 패킹 (8086 정렬).
- **담당 서브시스템**: 플랫폼 추상화 — 8086 실모드 메모리 모델 지원.

### h/proc.h — 프로세스 테이블

- `struct proc` — 활성 프로세스당 하나씩 할당. 스왑 아웃되어도 유지되는 데이터: `p_stat`(상태), `p_flag`(플래그), `p_pri`(우선순위), `p_sig`(시그널), `p_uid`, `p_time`/`p_cpu`/`p_nice`(스케줄링), `p_ttyp`(제어 터미널), `p_pid`/`p_ppid`, `p_addr`(스왑 이미지 주소), `p_size`, `p_wchan`(대기 이벤트), `p_textp`(텍스트 구조체 포인터).
- 상태 코드: `SSLEEP`, `SWAIT`, `SRUN`, `SIDL`, `SZOMB`, `SSTOP`.
- 플래그: `SLOAD`(인코어), `SSYS`(시스템 프로세스), `SLOCK`, `SSWAP`, `STRC`, `SWTED`.
- 전역: `proc[NPROC]`.
- **담당 서브시스템**: 프로세스 관리 — 스케줄러와 프로세스 생성/종료의 핵심.

### h/reg.h — 인터럽트 스택 프레임

- `struct ctx` — 컨텍스트 스위치 시 저장되는 레지스터 집합 (ds..sp).
- 레지스터 오프셋 상수: `R0`~`R3`(범용 레지스터), `R_BX`, `R_CX`, `R_DX`, `R_DS`, `R_ES` 등.
- **담당 서브시스템**: 트랩/시스템 콜 — 사용자 레지스터 접근 (`trap.c`, `m86.asm`이 사용).

### h/systm.h — 전역 변수 및 함수 프로토타입

- 전역 변수: `canonb`(정규 입력 버퍼), `coremap`/`swapmap`(메모리 맵), `rootdir`, `mount[NMOUNT]`, `callout[NCALL]`, `time[2]`, `runrun`, `runin`, `runout`, `curpri`, `lbolt`, `mpid`, `rootdev`, `swapdev`, `swplo`, `nswap`.
- 구조체: `struct callo`(콜아웃 큐), `struct mount`(마운트 테이블), `struct sysent`(시스템 콜 엔트리).
- 커널 전체 함수 프로토타입 선언 (파일시스템, 프로세스, 시그널, TTY, 드라이버 등).
- **담당 서브시스템**: 커널 전역 — 전역 상태와 인터페이스 선언.

### h/text.h — 순수 텍스트 세그먼트

- `struct text` — 공유 순수 텍스트(코드) 세그먼트. `x_daddr`(디스크 주소), `x_caddr`(코어 주소), `x_size`, `x_count`(참조 수), `x_iptr`(아이노드 포인터), `x_flag`(플래그).
- **담당 서브시스템**: 프로세스 관리 — 공유 텍스트 세그먼트 관리 (`text.c`가 사용).

### h/tty.h — 터미널 서브시스템

- `struct clist` — 문자 큐 (링 버퍼): `c_cc`(카운트), `c_cf`/`c_cl`(앞/뒤 포인터).
- `struct tty` — 터미널 상태: 입력/출력 큐, `t_flags`(모드 플래그: ECHO, RAW, CRMOD 등), `t_state`, `t_erase`/`t_kill`(편집 문자), `t_intr`/`t_quit`(시그널 문자), 속도, 지연 탭.
- **담당 서브시스템**: TTY — 라인 편집, 에코, 시그널 생성 (`tty.c`, `kl.c`가 사용).

### h/user.h — 사용자 영역 (u-area)

- `struct user` — 프로세스당 스왑되는 사용자 데이터: `u_procp`(proc 포인터), `u_ar0`(레지스터 배열), `u_arg[3]`(시스템 콜 인자), `u_dirp`, `u_error`(오류 코드), `u_qsav`/`u_ssav`(컨텍스트 저장), `u_intflg`, `u_uid`/`u_gid`, `u_cdir`(현재 디렉토리), `u_ofile[NOFILE]`(파일 디스크립터 테이블), `u_textp`, `u_stack[KSSIZE]`(커널 스택).
- **담당 서브시스템**: 프로세스 관리 — 프로세스별 커널 상태 (스왑 단위).

---

## 2. ken/ — 기계 독립 커널

### ken/alloc.c — 파일시스템 블록/아이노드 할당

- `iinit()` — 부팅 시 루트 장치의 슈퍼블록을 읽어 마운트 테이블 초기화, 시스템 날짜 설정.
- `alloc(dev)` — 슈퍼블록 자유 리스트에서 디스크 블록 할당 (100개 캐시, 소진 시 블록 단위로 재충전).
- `free(dev, bno)` — 디스크 블록을 자유 리스트에 반환.
- `ialloc(dev)` / `ifree(dev, ino)` — 아이노드 할당/해제 (100개 캐시 유지).
- `badblock()` — 블록 번호 유효성 검사.
- `getfs(dev)` — 장치의 슈퍼블록 조회.
- `update()` — 수정된 슈퍼블록/아이노드를 디스크에 플러시 (sync).
- **서브시스템**: 파일시스템 — 슈퍼블록 및 자유 리스트 관리.

### ken/clock.c — 클럭 인터럽트 & 시간 관리

- `clock(mode)` — 메인 클럭 ISR: 콜아웃 실행, 시간 증가, 번개(wakeup), CPU 사용량 집계, 스케줄러 호출.
- `timeout(fun, arg, tim)` — N 틱 후 함수 호출을 예약 (콜아웃 큐).
- `isr_savuar()` — 인터럽트 시 사용자 영역(u-area) 저장.
- `isr_router(irq, mode)` — 8086 인터럽트 라우팅.
- `check_runrun()` — runrun 플래그 확인 후 재스케줄.
- **서브시스템**: 프로세스 스케줄링 & 시간 유지.

### ken/fio.c — 파일 디스크립터 & 접근 제어

- `getf(f)` — 파일 디스크립터 번호로 `struct file` 획득.
- `falloc()` / `ufalloc()` — 파일 구조체/디스크립터 슬롯 할당.
- `closef(fp)` / `closei(ip, rw)` / `openi(ip, rw)` — 열기/닫기 (장치 드라이버 디스패치 포함).
- `access(aip, mode)` — 파일 접근 권한 검사.
- `owner()` — 파일 소유자 확인.
- `suser()` — 슈퍼유저(uid 0) 확인.
- **서브시스템**: 파일 시스템 — 파일 디스크립터 관리와 권한 검사.

### ken/iget.c — 아이노드 캐시 & 관리

- `iget(dev, ino)` — 아이노드를 인코어 테이블에서 찾거나 디스크에서 읽어옴.
- `iput(p)` — 아이노드 참조 해제 (마지막이면 디스크에 기록).
- `iupdat(p, tm)` — 아이노드의 수정/접근 시간 갱신.
- `itrunc(aip)` — 파일의 데이터 블록을 모두 해제 (파일 잘라내기).
- `maknode(mode)` — 새 아이노드 생성.
- `wdir(ip)` — 디렉토리 아이노드 갱신.
- **서브시스템**: 파일시스템 — 인코어 아이노드 캐시 관리.

### ken/main.c — 커널 시작

- `main()` — 커널 엔트리: `pc_init()`(하드웨어 초기화) → 메모리 맵 초기화 → 시스템 프로세스(proc[0]) 설정 → `cinit()`/`binit()`/`iinit()`(TTY/버퍼/파일시스템 초기화) → 루트 디렉토리 마운트 → `newproc()`으로 init 프로세스 생성 → `sched()` 스케줄링 루프 진입.
- `icode[]` — init 프로그램을 실행하는 부트스트랩 머신 코드 (exec("init")).
- `bdevsw[]` / `cdevsw[]` — 장치 스위치 테이블 정의 (rk 디스크, kl 콘솔, mem).
- 전역 변수: `u`, `proc[NPROC]`, `rootdir`, `mount[]`, `inode[]`, `coremap[]`, `swapmap[]`, `callout[]`.
- **서브시스템**: 커널 부팅 — 시스템 초기화 및 스케줄러 시작.

### ken/malloc.c — 메모리 맵 할당자

- `struct map` — 메모리 맵 엔트리 (주소/크기 쌍).
- `malloc(mp, size)` — 맵에서 연속 영역 할당 (최초 적합).
- `mfree(mp, size, aa)` — 맵에 영역 반환 (인접 병합).
- **서브시스템**: 메모리 관리 — 코어/스왑 영역 할당 (coremap, swapmap).

### ken/nami.c — 경로명 검색

- `namei(func, flag)` — 경로명을 따라가며 아이노드 검색 (디렉토리 트리 탐색).
- `uchar()` / `schar()` — 사용자 공간에서 문자 읽기 (경로명 인자).
- **서브시스템**: 파일시스템 — 경로명 해석 (open, exec, chdir 등에서 사용).

### ken/pipe.c — 파이프 IPC

- `pipe()` — 파이프 생성 (파일 디스크립터 2개 반환).
- `readp(fp)` / `writep(fp)` — 파이프 읽기/쓰기 (블록/언블록, 시그널 처리).
- `plock(ip)` / `prele(ip)` — 파이프 아이노드 락/언락.
- **서브시스템**: 프로세스 간 통신 — 파이프 구현.

### ken/prf.c — 커널 printf & 진단

- `printn(n, b)` — 숫자를 진수 변환 출력.
- `printk(fmt, ...)` — 커널 포맷 출력 (콘솔).
- `panic(s)` — 치명적 오류 시 메시지 출력 후 중단.
- `prdev(str, dev)` — 장치 오류 메시지 출력.
- `deverror(bp, o1, o2)` — 디스크 오류 진단.
- **서브시스템**: 커널 진단 — 디버그/오류 출력.

### ken/rdwri.c — 파일 I/O 엔진

- `readi(aip)` — 아이노드에서 데이터 읽기 (bmap으로 블록 매핑).
- `writei(aip)` — 아이노드에 데이터 쓰기 (블록 할당 포함).
- `iomove(bp, o, an, flag)` — 버퍼와 사용자 공간 간 데이터 이동.
- **서브시스템**: 파일시스템 — 파일 데이터 읽기/쓰기 핵심.

### ken/sig.c — 시그널 전달

- `signal(tp, sig)` — 터미널에서 시그널 생성 (제어 터미널 프로세스 그룹에 전달).
- `psignal(p, sig)` — 프로세스에 시그널 설정.
- `issig()` — 처리할 시그널 확인.
- `psig()` — 시그널 처리 (기본 동작/핸들러 호출).
- `core()` — 코어 덤프 생성.
- **서브시스템**: 시그널 — 시그널 생성/전달/처리.

### ken/slp.c — 프로세스 스케줄링 & 컨텍스트 스위치

- `sleep(chan, pri)` — 이벤트 대기 (우선순위에 따라 스왑 가능).
- `wakeup(chan)` — 이벤트 대기 프로세스 깨우기.
- `setrun(p)` — 프로세스를 실행 큐에 등록.
- `setpri(up)` — 우선순위 재계산.
- `sched()` — 스케줄링 루프 (가장 높은 우선순위 프로세스 선택).
- `swtch()` — 프로세스 컨텍스트 스위치.
- `newproc()` — 새 프로세스 생성 (fork의 커널 측).
- `resume(p, ctx)` — 저장된 컨텍스트로 복귀.
- `estabur(addr)` — 사용자 영역 주소 설정.
- **서브시스템**: 프로세스 스케줄링 — V6 스와핑 메커니즘 포함.

### ken/subr.c — 파일 블록 매핑 & 데이터 이동

- `bmap(ip, bn)` — 논리 블록 번호를 물리 블록 번호로 매핑 (직접/간접 블록).
- `passc(c)` / `cpass()` — 사용자 공간과 커널 간 문자 단위 전송.
- `nodev()` / `nulldev(d, flag)` — 장치 없음/무동작 드라이버.
- `bcopy(from, to, count)` — 메모리 복사.
- **서브시스템**: 파일시스템 — 블록 매핑과 데이터 전송 유틸리티.

### ken/sys1.c — 프로세스 시스템 콜

- `exec()` — 프로그램 실행 (새 이미지 로드, 인자 설정).
- `rexit()` / `exit()` — 프로세스 종료.
- `wait()` — 자식 프로세스 종료 대기.
- `fork()` — 프로세스 복제.
- `sbreak()` — 데이터 세그먼트 크기 변경 (brk).
- **서브시스템**: 시스템 콜 — 프로세스 수명주기.

### ken/sys2.c — 파일 I/O 시스템 콜

- `read()` / `write()` — 파일 읽기/쓰기.
- `rdwr(mode)` — 공통 읽기/쓰기 처리.
- `open()` / `creat()` / `open1()` — 파일 열기/생성.
- `close()` — 파일 닫기.
- `seek()` — 파일 오프셋 이동.
- `link()` — 하드 링크 생성.
- `mknod()` — 장치 노드 생성.
- `sslep()` — sleep 시스템 콜.
- **서브시스템**: 시스템 콜 — 파일 I/O.

### ken/sys3.c — 파일 & 마운트 시스템 콜

- `fstat()` / `stat()` / `stat1()` — 파일 상태 조회.
- `dup()` — 파일 디스크립터 복제.
- `smount()` / `sumount()` — 파일시스템 마운트/언마운트.
- `getmdev()` — 마운트 장치 번호 획득.
- **서브시스템**: 시스템 콜 — 파일 상태/마운트.

### ken/sys4.c — 기타 시스템 콜

- `getswit()` — 스위치 (프로세스 전환).
- `gtime()` / `stime()` — 시간 조회/설정.
- `setuid()` / `getuid()` / `setgid()` / `getgid()` — 사용자/그룹 ID.
- `getpid()` — 프로세스 ID.
- `sync()` — 파일시스템 플러시.
- `nice()` — 우선순위 조정.
- `unlink()` — 파일 삭제.
- `chdir()` — 작업 디렉토리 변경.
- `chmod()` / `chown()` — 권한/소유자 변경.
- `ssig()` — 시그널 설정.
- `kill()` — 시그널 전송.
- `times()` — 프로세스 시간 조회.
- `getkaddr()` — 커널 심볼 주소 조회 (ps용).
- **서브시스템**: 시스템 콜 — 기타 유틸리티.

### ken/sysent.c — 시스템 콜 디스패치 테이블

- `struct sysent sysent[64]` — 시스템 콜 번호 → 처리 함수 매핑 테이블.
- 0~63번 시스템 콜 정의: exit(1), fork(2), read(3), write(4), open(5), close(6), wait(7), creat(8), link(9), unlink(10), exec(11), chdir(12), time(13), mknod(14), chmod(15), chown(16), break(17), stat(18), seek(19), getpid(20), mount(21), umount(22), setuid(23), getuid(24), stime(25), fstat(28), stty(31), gtty(32), nice(34), sleep(35), sync(36), kill(37), switch(38), getkaddr(39), dup(41), pipe(42), times(43), setgid(46), getgid(47), sig(48) 등.
- **서브시스템**: 시스템 콜 — 디스패치.

### ken/text.c — 텍스트 세그먼트 관리

- `xswap(p, ff, a)` — 텍스트 세그먼트 스왑.
- `xfree()` — 텍스트 세그먼트 해제.
- `xccdec(xp)` — 텍스트 참조 카운트 감소.
- **서브시스템**: 프로세스 관리 — 공유 텍스트(코드) 세그먼트.

### ken/trap.c — 트랩/시스템 콜 처리

- `trap()` — 시스템 콜 디스패치: sysent 테이블에서 처리 함수 호출, 오류 코드 설정, 시그널 처리.
- `trap0()` — 인터럽트 스택 프레임에서 레지스터/인자 추출.
- `trap1(f)` — 시스템 콜 함수 호출 (시그널로 중단 가능).
- `nosys()` — 존재하지 않는 시스템 콜 (오류 100).
- `nullsys()` — 무시되는 시스템 콜.
- `trap_epilogue()` — 처리 결과를 사용자 레지스터에 반영.
- **서브시스템**: 시스템 콜 — INT 81h 진입점 처리.

---

## 3. dmr/ — 기계 의존 코드 (드라이버 & 저수준)

### dmr/bio.c — 버퍼 캐시 & 블록 I/O

- `bread(dev, blkno)` — 블록 읽기 (캐시 히트 시 즉시 반환).
- `breada(dev, blkno, rablkno)` — 선반입(read-ahead) 포함 블록 읽기.
- `bwrite(bp)` — 블록 쓰기 (동기).
- `bdwrite(bp)` — 지연 쓰기 (delayed write).
- `bawrite(bp)` — 비동기 쓰기.
- `brelse(bp)` — 버퍼 해제 (자유 리스트 반환).
- `incore(dev, blkno)` — 캐시 히트 확인.
- `getblk(dev, blkno)` — 버퍼 할당 (busy면 대기).
- `iowait(bp)` / `iodone(bp)` — I/O 완료 대기/통지.
- `clrbuf(bp)` — 버퍼 초기화.
- `binit()` — 버퍼 풀 초기화.
- `swap(blkno, coreaddr, count, rdflg)` — 프로세스 스와핑 I/O.
- `bflush(dev)` — 장치의 지연 쓰기 버퍼 플러시.
- `physio(strat, abp, dev, rw)` — 물리 I/O (raw 장치).
- `geterror(abp)` — I/O 오류 코드 반환.
- **서브시스템**: 블록 I/O — 버퍼 캐시 관리.

### dmr/ide.c — ATA/IDE 디스크 드라이버

- `idewait(checkerr)` — IDE 상태 레지스터 폴링.
- `idestart(sector, data)` — IDE 읽기/쓰기 명령 발행.
- `ideio(sector, count, buf, cmd)` — 다중 섹터 전송 시작.
- `ideintr()` — IDE 인터럽트 핸들러 (섹터당 256워드 전송 후 `rkintr()` 호출).
- **서브시스템**: 디스크 드라이버 — RK 디스크를 IDE 하드웨어로 구현.

### dmr/kbd.c — PC 키보드 드라이버

- `kbd_init()` — 키보드 상태/스캔코드 맵 초기화.
- `kbd_getc()` — 키보드 포트 읽기, Shift/Ctrl/Alt/CapsLock 상태 추적, 스캔코드 디코딩 (E0 이스케이프 포함).
- `kbdintr()` — 키보드 인터럽트 핸들러 (`klrxintr()`로 전달).
- **서브시스템**: 입력 드라이버 — PS/2 키보드.

### dmr/kl.c — KL/DL-11 시리얼(tty) 드라이버

- `klopen(dev, flag)` / `klclose(dev, flag)` — 콘솔 열기/닫기.
- `klread(dev)` / `klwrite(dev)` — 콘솔 읽기/쓰기.
- `klxint(dev)` / `klrint(dev)` — 전송/수신 인터럽트 처리.
- `klsgtty(dev, v)` — 터미널 설정 조회.
- `klrxintr()` / `kltxintr()` — 수신/전송 인터럽트 엔트리 (UART 또는 키보드 백엔드).
- **서브시스템**: 콘솔 드라이버 — V6 KL-11 시리얼 인터페이스.

### dmr/m86.asm — 8086 어셈블리 저수준 루틴

- `STARTX` — 커널 엔트리: 세그먼트 설정, BSS 초기화, `main()` 호출.
- `EnterISR`/`ExitISR` — 인터럽트 진입/복귀 매크로 (레지스터 저장).
- `SwitchToKernelStack`/`SwitchToUserStack` — 커널/사용자 스택 전환.
- `_clock_isr` / `_ide_isr` / `_kbd_isr` / `_uart_isr` — 하드웨어 인터럽트 핸들러.
- `_common_isr` — 공통 ISR (EOI 전송, u-area 저장, `isr_router` 호출).
- `_trap_isr` — INT 81h 시스템 콜 핸들러 (`trap0` → `trap`).
- `_getps` / `_setps` — 프로세서 상태 플래그 읽기/쓰기.
- `_save` / `_do_resume` — 컨텍스트 저장/복원 (V7 save/resume).
- `_use_resume_stack` — 복원용 스택 전환.
- `_move_to_user_mode` — 사용자 모드로 전환 (세그먼트/스택 설정 후 far return).
- `_memcpy` / `_memset` — 메모리 복사/초기화 (워드 단위 최적화).
- `_bios_getc` / `_bios_putc` — BIOS 키보드/텍스트 출력 (INT 16h/10h).
- **서브시스템**: 저수준 플랫폼 — 인터럽트/컨텍스트 스위치/메모리.

### dmr/mem.c — 메모리 특수 파일 드라이버

- `mmread(dev)` — `/dev/mem`(물리 메모리), `/dev/kmem`(커널 메모리), `/dev/null` 읽기.
- `mmwrite(dev)` — 메모리 쓰기.
- `mmsgtty(dev, v)` — sgtty 처리.
- **서브시스템**: 문자 장치 — 메모리 접근 특수 파일.

### dmr/pc.c — PC 플랫폼 저수준 루틴

- `savu(p)` / `retu(p)` — 프로세스 u-area 저장/복원 (memcpy 기반, MMU 없음).
- `spl0()`~`spl7()` — 인터럽트 우선순위 레벨 설정 (8086에서는 enable/disable).
- `fubyte()` / `fuword()` / `subyte()` / `suword()` — 사용자 공간 메모리 접근.
- `copyseg(src, dst)` / `clearseg(dst)` — 페이지 복사/초기화.
- `copyout(srcAddr, dstAddr, size)` — 커널→사용자 복사.
- `dpadd()` / `dpcmp()` / `ldiv()` / `lrem()` / `lshift()` — 32비트 산술 (PDP-11 호환).
- `outport()` / `outportb()` / `inport()` / `inportb()` — 포트 I/O.
- `idle()` — 인터럽트 대기 (sti/hlt).
- `putck(c)` — 콘솔 문자 출력 (UART 또는 BIOS).
- `setvect(vectnumber, vectfunc)` — 인터럽트 벡터 설정.
- `PC_SetTickRate()` — 8254 PIT 타이머를 60Hz로 설정.
- `pc_init()` — 하드웨어 초기화: UART/키보드/IDE/클럭/시스템 콜 인터럽트 벡터 설정.
- **서브시스템**: 플랫폼 추상화 — 8086 실모드 저수준 지원.

### dmr/rk.c — RK 디스크 드라이버

- `rkstrategy(abp)` — 버퍼를 장치 큐에 등록.
- `rkaddr(bp)` — 디스크 주소 계산.
- `rkstart()` — I/O 시작 (IDE로 디스패치).
- `rkintr()` — I/O 완료 인터럽트 처리.
- `devstart(bp)` — 장치 I/O 시작.
- **서브시스템**: 디스크 드라이버 — V6 RK05 디스크 인터페이스 (IDE 하드웨어 위에 구현).

### dmr/tty.c — 일반 TTY 서브시스템

- `gtty()` / `stty()` / `sgtty(v)` — 터미널 설정 조회/변경.
- `cinit()` — clist(문자 큐) 초기화.
- `flushtty(atp)` / `wflushtty(atp)` — 터미널 출력 플러시.
- `canon(atp)` — 정규 모드 라인 편집 (에코, erase/kill 처리).
- `ttyinput(ac, atp)` — 문자 입력 처리 (시그널 문자 감지 포함).
- `ttyoutput(ac, tp)` — 문자 출력 (지연 처리).
- `ttstart(atp)` — 출력 시작.
- `ttread(atp)` / `ttwrite(atp)` — 터미널 읽기/쓰기.
- `ttystty(tp, av)` — sgtty 구조체 변환.
- `getc(pList)` / `putc(c, pList)` — clist 문자 큐 연산.
- **서브시스템**: TTY — 라인 규율(discipline)과 문자 큐 관리.

### dmr/uart.c — 16550 UART 드라이버

- `uart_init()` — COM1을 115200-8N1로 설정.
- `uartintr()` — UART 인터럽트 디스패치 (RX/TX).
- `uart_putc(c)` — 문자 전송.
- `uart_getc()` — 문자 수신.
- **서브시스템**: 시리얼 드라이버 — 콘솔 백엔드 (KL_BACKEND_UART).

---

## 4. usr/ — 사용자 프로그램

### usr/cat.c — 파일 내용 출력

- 파일 내용을 표준 출력으로 복사하는 `cat` 명령.

### usr/chmod.c — 권한 변경

- 8진수 모드로 파일 권한을 변경하는 `chmod` 명령.

### usr/cp.c — 파일 복사

- 파일을 새 파일 또는 디렉토리로 복사하는 `cp` 명령.

### usr/ctime.c — 시간 변환 라이브러리

- `ctime()`, `localtime()`, `gmtime()`, `asctime()`, `dysize()` 등 시간 변환 함수.
- 1970년 1월 1일 epoch 기준, 일광 절약 시간 처리 포함.

### usr/date.c — 날짜/시간 출력

- 현재 날짜와 시간을 출력하는 `date` 명령.

### usr/echo.c — 인자 출력

- 명령줄 인자를 표준 출력으로 출력하는 `echo` 명령.

### usr/ed.c — 라인 에디터

- V6 원본 `ed` 에디터 포트. 명령 모드/입력 모드, 주소 지정, 검색/치환, 정규식, 파일 저장/로드, `setexit()`/`reset()` 비로컬 점프 사용.

### usr/fib.c — 피보나치 수열

- 큰 수(big-number) 산술로 피보나치 수열을 계산/출력하는 데모 프로그램.

### usr/forktest.c — fork 테스트

- 프로세스 테이블이 가득 찼을 때 `fork()`가 우아하게 실패하는지 테스트.

### usr/grep.c — 패턴 검색

- 정규식 패턴으로 파일/표준 입력에서 일치하는 줄을 검색하는 `grep` 명령.

### usr/id.c — 사용자 ID 출력

- 현재 프로세스의 사용자/그룹 ID를 출력하는 `id` 명령.

### usr/init.c — 첫 사용자 프로세스

- 커널이 부팅 후 실행하는 첫 프로그램. 콘솔 열기, 시그널 처리, `/bin/sh`를 fork/exec, 좀비 수거.

### usr/kill.c — 시그널 전송

- PID로 시그널(기본 SIGHUP)을 보내는 `kill` 명령.

### usr/ln.c — 하드 링크 생성

- 대상 파일에 하드 링크를 만드는 `ln` 명령.

### usr/login.c — 로그인

- root 또는 사용자로 uid/gid를 설정한 후 셸을 exec하는 `login` 명령.

### usr/ls.c — 디렉토리 목록

- 권한, 링크 수, 소유자, 크기, 날짜를 표시하는 `ls` 명령 (stat/ctime 사용).

### usr/mkdir.c — 디렉토리 생성

- 디렉토리를 생성하는 `mkdir` 명령.

### usr/mkfs.c — 파일시스템 생성 (사용자 버전)

- V6 `mkfs` 포트. proto 파일을 읽어 파일시스템 이미지를 생성 (tools/mkfs.c와 동일 계열).

### usr/mknod.c — 장치 노드 생성

- 블록/문자 특수 파일(장치 노드)을 만드는 `mknod` 명령.

### usr/more.c — 페이지 표시

- 파일을 24줄 단위로 표시하는 `more` 명령. raw 모드로 전환해 Space(다음 페이지)/q(종료) 키 처리.

### usr/mount.c — 파일시스템 마운트

- 파일시스템을 마운트하고 `/etc/mtab`에 기록하는 `mount` 명령 (읽기 전용 마운트 지원).

### usr/nice.c — 우선순위 조정 실행

- 낮은 스케줄링 우선순위로 명령을 실행하는 `nice` 명령.

### usr/printf.c — 포맷 출력 라이브러리

- `printf()`, `sprintf()`, `fprintf()`, `vsprintf()` 구현. %d, %o, %x, %c, %s, %u 지원.

### usr/ps.c — 프로세스 상태

- `/dev/kmem`과 `getkaddr()` 시스템 콜로 커널 proc 테이블을 읽어 프로세스 상태를 출력하는 `ps` 명령.

### usr/pwd.c — 작업 디렉토리 출력

- `..` 엔트리를 따라 올라가며 현재 작업 디렉토리를 계산하는 `pwd` 명령.

### usr/rm.c — 파일 삭제

- 파일을 삭제(unlink)하는 `rm` 명령.

### usr/sh.c — 셸

- xv6 스타일 셸. 명령 파서(exec/redir/pipe/list/back)와 실행기(`runcmd`) 구현. `/bin/` 접두어 자동 추가, `cd`/`exit` 내장.

### usr/sigtest.c — 시그널 테스트

- 부모가 자식에게 SIGINT를 보내고, 자식의 시그널 핸들러 동작과 종료 코드를 확인하는 테스트.

### usr/sleep.c — 지연

- 지정된 틱 수만큼 sleep하는 `sleep` 명령.

### usr/stty.c — 터미널 모드 설정

- 터미널 속도/모드 플래그를 설정/조회하는 `stty` 명령.

### usr/sync.c — 파일시스템 플러시

- `sync()` 시스템 콜을 호출하는 `sync` 명령.

### usr/syscall.c — 시스템 콜 래퍼 라이브러리

- 모든 시스템 콜의 C 래퍼: `exit`, `fork`, `open`, `read`, `write`, `close`, `wait`, `exec`, `stat`, `mount`, `kill`, `signal` 등.
- `syscall(fn, r0, ...)` — 가변 인자로 시스템 콜 번호와 인자를 전달.

### usr/ulib.c — 사용자 라이브러리

- K&R 스타일 `malloc`/`free` (4KB 힙).
- 문자열 함수: `strcpy`, `strcmp`, `strlen`, `strcat`, `strchr`, `strncpy`, `safestrcpy`.
- 메모리 함수: `memset`, `memcpy`, `memmove`, `memcmp`.
- `atoi`, `gets`, `perror`, `mkdir`.

### usr/umount.c — 파일시스템 언마운트

- 파일시스템을 언마운트하고 `/etc/mtab`에서 제거하는 `umount` 명령.

### usr/unix.h — 사용자 공간 헤더

- `struct stat`, `struct dirent`, 시그널 번호, 오류 코드(`u_error`), 파일 플래그.
- 모든 시스템 콜/라이브러리 함수 프로토타입.

### usr/wc.c — 줄/단어/문자 수

- 파일의 줄, 단어, 문자 수를 세는 `wc` 명령.

### usr/zombie.c — 좀비 테스트

- 자식이 먼저 exit하고 부모가 sleep하는 좀비 프로세스 생성 테스트.

### usr/boots.asm — init 부트 스텁

- `exec("init")` 시스템 콜을 직접 호출하는 작은 어셈블리 프로그램 (커널 icode 대체용).

### usr/setexit.asm — 비로컬 점프

- `setexit()`/`reset()` — V6 스타일 비로컬 점프 (ed 에디터의 오류 복구용). SP/BP/복귀 주소 저장/복원.

### usr/startup.asm — .COM 시작 코드

- `startx` — BSS 초기화 후 `main()` 호출, 종료 시 exit 시스템 콜.
- `_callsig` — 시그널 핸들러 호출 스텁.
- `_syscall` — INT 81h 시스템 콜 진입점 (오류 코드 처리, errno 설정).

---

## 5. boot/ & tools/ — 부팅 및 빌드

### boot/bootsect.asm — 부트 섹터

- BIOS INT 13h로 플로피에서 커널(블록 1~119)을 0x1000:0x0100에 로드.
- LBA→CHS 변환 (9섹터/트랙, 2헤드).
- 로드 완료 후 커널 엔트리로 far jump.
- 0xAA55 부트 시그니처 포함.

### boot/proto — 파일시스템 프로토타입

- `mkfs`가 읽는 파일시스템 레이아웃 정의: 부트 블록, 파일시스템/아이노드/스왑 블록 수, 루트 디렉토리 구조.
- `/bin`(모든 명령), `/dev`(console, rk0-3, mem, kmem, null), `/etc`, `/tmp`, `/usr` 디렉토리와 각 파일의 모드/소유자/외부 경로 지정.

### boot/genimage.py — 이미지 생성 스크립트

- 부트/디스크 이미지 생성 보조 스크립트.

### boot/unix0_rk.img.gz — 원본 RK05 디스크 이미지 (압축)

- **원본 UNIX V6 RK05 디스크 이미지**를 gzip으로 압축한 파일.
- `boot/Makefile`의 `unix0_rk.img` 타겟이 `gunzip -c unix0_rk.img.gz > $@`로 압축을 해제하여 사용.
- `qemu` 타겟에서 `-drive file=unix0_rk.img,format=raw,if=ide`로 QEMU에 IDE 디스크로 연결되어 **원본 V6 파일시스템/데이터가 담긴 디스크로 부팅**하는 데 사용.
- 즉, 새로 빌드한 `unix.img`(tools/mkfs로 생성) 대신 **원본 V6 배포판의 RK 디스크 이미지**를 그대로 사용해 시스템을 실행할 수 있게 하는 용도.
- `boot/Makefile`의 `qemu` 타겟과 `qemu-uart` 타겟이 이 이미지를 사용.

### tools/mkfs.c — 호스트용 파일시스템 빌더

- 호스트 gcc로 컴파일되는 V6 `mkfs` 포트.
- proto 파일을 읽어 슈퍼블록, 아이노드, 디렉토리, 파일 데이터를 생성하고 `unix.img` 하드디스크 이미지를 만듦.
- 스왑 블록 지원 추가.

### Makefile (최상위) — 커널 빌드

- Open Watcom `wmake` 전용 문법.
- `wcc`로 dmr/와 ken/의 C 소스를 8086 실모드(.COM)로 컴파일.
- `wasm`으로 m86.asm 어셈블, `wlink`으로 `unix.com` 생성.

### usr/Makefile — 사용자 프로그램 빌드

- `syscall.obj`, `ulib.obj`, `ctime.obj`, `printf.obj`, `setexit.obj`를 `unix.lib`로 묶음.
- 각 사용자 프로그램을 `startup.obj` + `unix.lib`와 링크하여 `.com` 생성.
- init, sh, ls, cat, wc, echo, pwd, kill, date, rm, login, cp, chmod, mkdir, sync, id, zombie, mount, umount, forktest, sigtest, stty, more, fib, ln, nice, mknod, sleep, grep, ps, ed, mkfs 빌드.

### boot/Makefile — 부트 이미지 생성 & 실행

- `Unix360.img` — bootsect.asm → boot.com, unix.com을 720KB 플로피 이미지에 배치.
- `unix.img` — tools/mkfs + proto로 하드디스크 이미지 생성.
- `unix0_rk.img` — 원본 RK 디스크 이미지 압축 해제 (`unix0_rk.img.gz`에서 gunzip).
- `q` 타겟 — QEMU curses 모드 실행 (빌드한 unix.img 사용).
- `qemu` 타겟 — QEMU cocoa 모드 실행 (원본 unix0_rk.img 사용).
- `qemu-uart` 타겟 — QEMU cocoa 모드 + UART 콘솔 (원본 unix0_rk.img 사용).
- `b`/`bochs` 타겟 — Bochs 에뮬레이터 실행.

### readme.txt — 문서

- 프로젝트 관련 텍스트 문서 (디스크 이미지에 포함됨).

---

## 6. 시스템 아키텍처 요약

```
┌─────────────────────────────────────────────────────┐
│  사용자 공간 (usr/)                                  │
│  init → sh → cat, ls, grep, ed, ps, ...             │
│  startup.asm + unix.lib (syscall.c, ulib.c, ...)    │
│  INT 81h 시스템 콜                                   │
├─────────────────────────────────────────────────────┤
│  커널 (ken/ + dmr/)                                  │
│  ┌─────────────────────────────────────────────┐    │
│  │ 시스템 콜: sysent.c → sys1~4.c, trap.c      │    │
│  │ 프로세스: slp.c, sys1.c, text.c, sig.c      │    │
│  │ 파일시스템: alloc.c, iget.c, nami.c,        │    │
│  │             rdwri.c, pipe.c, subr.c, fio.c  │    │
│  │ 시간: clock.c, prf.c                        │    │
│  ├─────────────────────────────────────────────┤    │
│  │ 드라이버: bio.c, rk.c/ide.c, kl.c, tty.c,   │    │
│  │            kbd.c, uart.c, mem.c             │    │
│  │ 저수준: m86.asm, pc.c                       │    │
│  └─────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────┤
│  부트: bootsect.asm (BIOS INT 13h) → unix.com       │
│  이미지: tools/mkfs + proto → unix.img              │
│         unix0_rk.img.gz → unix0_rk.img (원본 V6)    │
└─────────────────────────────────────────────────────┘
```

### 핵심 설계 특징

1. **8086 실모드 포트** — PDP-11용 V6 커널을 16비트 8086에 이식. MMU가 없어 프로세스 스와핑은 u-area를 `memcpy`로 전환.
2. **컨텍스트 스위치** — V6의 `savu`/`retu`(u-area 전환) + V7의 `save`/`resume`(레지스터/스택 전환) 조합.
3. **시스템 콜** — INT 81h 인터럽트로 진입, sysent 테이블로 디스패치.
4. **스와핑** — V6 원본 스케줄러/스와핑 메커니즘 유지 (coremap/swapmap, swplo/nswap).
5. **파일시스템** — V6 원본 형식 (슈퍼블록, 아이노드, 디렉토리 14자 이름).
6. **드라이버** — V6 장치 인터페이스(rk, kl)를 PC 하드웨어(IDE, 키보드, UART) 위에 구현.

---

## ken/ 와 dmr/ 폴더 구분 기준과 최초 작성자의 철학

### 1. 구분 기준: **기계 독립 vs 기계 의존** 계층

|                   | ken/ (Ken Thompson)                                                                                                    | dmr/ (Dennis Ritchie)                                                                                             |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| **성격**          | **기계 독립**(machine-independent) 커널 코어                                                                           | **기계 의존**(machine-dependent) 코드 + 장치 드라이버                                                             |
| **대상 하드웨어** | PDP-11(원본), 어떤 CPU든 무관하게 동작                                                                                 | 특정 하드웨어(원본: PDP-11, 이 프로젝트: 8086 PC)에 의존                                                          |
| **업무 영역**     | 프로세스 관리, 파일시스템, 시스템 콜, 스케줄링, 시그널, 메모리                                                         | 장치 드라이버, 인터럽트 처리, 컨텍스트 스위치, 하드웨어 초기화                                                    |
| **파일 예**       | main.c, slp.c(스케줄러), sys1~4.c(시스템 콜), alloc.c, iget.c, nami.c, pipe.c, rdwri.c, sig.c, text.c, clock.c, trap.c | bio.c(버퍼 I/O), rk.c/ide.c(디스크), kl.c/tty.c(콘솔), kbd.c/uart.c(입력/시리얼), pc.c(플랫폼), m86.asm(어셈블리) |

### 2. 결합 지점 — 장치 스위치 테이블 (`ken/main.c`)

이 두 계층의 경계는 **`ken/main.c`의 장치 스위치 테이블**에서 명확히 드러납니다. ken/은 하드웨어에 직접 접근하지 않고, **함수 포인터 테이블을 통해 dmr/의 드라이버를 호출**합니다.

```c
/* ken/main.c — 기계 독립 계층이 드라이버를 참조하는 유일한 지점 */
extern struct devtab rktab;   /* dmr/rk.c */

struct bdevsw bdevsw[] = {    /* 블록 장치 스위치 */
    { nulldev, nulldev, rkstrategy, &rktab },   /* rk 디스크 → dmr/rk.c */
    { NULL, NULL, NULL, NULL},
};

struct cdevsw cdevsw[] = {    /* 문자 장치 스위치 */
    { klopen, klclose, klread, klwrite, klsgtty },  /* 콘솔 → dmr/kl.c */
    { nulldev, nulldev, mmread, mmwrite, mmsgtty }, /* 메모리 → dmr/mem.c */
    { NULL, NULL, NULL, NULL, NULL }
};
```

- ken/은 `rkstrategy`, `klopen`, `mmread` 등의 **드라이버 함수를 몰라도** `bdevsw[dev].d_strategy(...)` 형태로만 호출합니다.
- 반대로 dmr/의 드라이버는 ken/의 캐시, 버퍼(`struct buf`), 스케줄러, TTY 서브시스템의 API를 호출합니다.

### 3. 최초 작성자의 철학 — Ken Thompson / Dennis Ritchie의 설계 의도

이 구분은 **UNIX V6의 원본 소스 구조**에서 유래한 것으로, 두 저자의 명확한 철학이 담겨 있습니다:

**① 이식성(Portability) 우선 설계**

- ken/은 CPU, 메모리 맵, 디스크, 콘솔 등 **하드웨어와 무관한 알고리즘**만 가집니다. 그래서 소스가 PDP-11에서 8086으로 이식될 때 ken/은 거의 그대로 유지되고, dmr/만 다시 작성됐습니다. 이 프로젝트에서 m86.asm, pc.c, ide.c, kbd.c, uart.c가 추가된 것이 바로 dmr/ 계층만 교체된 증거입니다.

**② 관심사의 분리 (드라이버 = 하드웨어 세계, 커널 = 추상 세계)**

- dmr/은 "이 하드웨어에서 어떻게 동작하는가"에 집중하고, ken/은 "파일시스템·프로세스·시스템 콜이란 무엇인가"에 집중합니다. 장치 스위치 테이블이 그 사이의 유일한 계약(contract)입니다.

**③ UNIX의 철학 "프로그램은 한 가지 일을 잘 하라"**

- UNICES의 도구(Pipe, 필터) 철학을 커널 구조에도 적용해, "기계 독립 코어"와 "기계 의존 드라이버"를 분리했습니다. 이는 이후 BSD, Linux의 구조(arch/, drivers/ 분리)로 이어지는 시초가 됩니다.

**④ V6의 "메모리 최소화" 원칙**

- PDP-11 시절 32KB 코어에서 동작하기 위해, 드라이버를 별도 계층으로 두고 커널 코어를 최대한 작고 단순하게 유지했습니다. 하드웨어 종속 부분만 떼어내 재작성하면 새 기계에서 부팅 가능하게 한 것이 이식성의 핵심 철학입니다.

---

### 4. 주의점 — `bio.c`(버퍼 캐시)의 특이 케이스

흥미롭게도 **`dmr/bio.c`** 는 일반적인 "드라이버"가 아니라 **버퍼 캐시(블록 I/O 서브시스템)** 입니다. 이는 원본 V6에서도 `bio.c`가 기계 독립 코드이지만, V6 소스가 `dmr/`(vanilla V6 구조에서 "동일한 디렉토리에 있는 기계 독립 코드"가 불완전하게 분리된) 부분에 위치한 데서 온 전통입니다. ken/ 쪽의 `alloc.c`·`iget.c`·`rdwri.c`가 파일시스템 논리(아이노드/블록 매핑)를 담당하고, dmr/bio.c는 그 아래의 **실제 버퍼 읽기/쓰기/캐시**를 담당하는 계층입니다.

이는 **세밀한 3계층**으로 이해할 수 있습니다:

```
ken/ (기계 독립 논리) → dmr/bio.c (버퍼 I/O, 반기계독립) → dmr/rk.c, ide.c (하드웨어)
```

---

### 요약

> **ken/ = "컴퓨터가 무엇을 하는가" (Ken Thompson의 기계 독립 커널)**
> **dmr/ = "하드웨어가 어떻게 하는가" (Dennis Ritchie의 기계 의존 드라이버)**
>
> 이 구분은 **이식성을 최우선으로 하는 UNIX 설계 철학**에서 나온 것이며, 장치 스위치 테이블(ken/main.c)을 경계로 두 계층이 연결됩니다. 덕분에 이 RealXV6.j 프로젝트는 ken/을 거의 수정하지 않고 dmr/만 8086 PC용으로 재작성하여 포팅할 수 있었습니다.
