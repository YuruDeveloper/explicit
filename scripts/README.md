# scripts

`delegate.sh`(bash)와 `delegate.ps1`(Windows PowerShell)은 Codex 위임 작업의 입력·실행 로그·최종 결과를 저장합니다. 두 스크립트는 동일한 계약을 따릅니다.

```bash
scripts/delegate.sh <task-slug> <role> <model> [input-file]
```

```powershell
scripts/delegate.ps1 [-f|--force|-Force] <task-slug> <role> <model> [input-file]
```

`input-file`을 주면 해당 파일을 `input.md`로 복사합니다. 생략하면 표준 입력에서 프롬프트를 읽습니다.

```bash
printf '검증할 작업입니다.' | \
  scripts/delegate.sh stage0-sample luna-verify gpt-5.6-luna

scripts/delegate.sh stage0-sample terra-implement gpt-5.6-terra prompt.md
```

```powershell
'검증할 작업입니다.' | pwsh -NoProfile -File scripts/delegate.ps1 stage0-sample luna-verify gpt-5.6-luna

pwsh -NoProfile -File scripts/delegate.ps1 stage0-sample terra-implement gpt-5.6-terra prompt.md
```

결과는 저장소 루트의 다음 경로에 남습니다.

```text
agents/<YYYY-MM-DD>-<NN>-<task-slug>/<NN>-<role>/
  input.md
  output.md
  result.md
```

`<NN>`은 두 자리 순번입니다. task 디렉터리는 날짜 기준, role 디렉터리는 task 기준으로 스크립트가 자동 할당(기존 최대 번호 +1)하며, 같은 slug/role의 디렉터리가 이미 있으면 번호와 무관하게 재사용합니다.

기존 `result.md`가 있으면 안전을 위해 실행하지 않습니다. 의도적으로 다시 실행하려면 `-f` 또는 `--force`를 함께 전달합니다. 강제 실행은 Codex를 시작하기 전에 이전 `result.md`를 비웁니다.

같은 날짜·task-slug·role 대상으로 이미 실행 중인 경우에는 감사 파일이 섞이지 않도록 새 실행을 거부합니다. lock에는 wrapper와 Codex child PID를 기록합니다. 둘 중 하나라도 살아 있거나 owner PID 파일이 없으면 새 실행을 거부합니다. 두 PID가 모두 죽은 stale lock은 고유 경로로 원자적으로 옮긴 프로세스만 lock 획득을 한 번 다시 시도하며, 경쟁 프로세스가 먼저 새 lock을 잡으면 거부합니다. 정상적인 `TERM`·`INT`는 Codex child로 전달합니다. (`delegate.ps1`은 Windows 제약으로 신호 포워딩 대신 try/finally 락 정리를 사용하며, wrapper가 강제 종료되어 고아 Codex child가 남으면 다음 호출이 stale lock으로 감지해 처리합니다.)

Codex가 실행 초기에 실패해 최종 메시지를 쓰지 못한 경우에도 빈 `result.md`를 남겨 감사 경로를 일관되게 유지합니다. 스크립트의 종료 코드는 Codex의 종료 코드를 그대로 반환합니다.

```bash
scripts/delegate.sh --force stage0-sample luna-verify gpt-5.6-luna prompt.md
```
