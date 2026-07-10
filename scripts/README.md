# scripts

`delegate.sh`는 Codex 위임 작업의 입력·실행 로그·최종 결과를 저장합니다.

```bash
scripts/delegate.sh <task-slug> <role> <model> [input-file]
```

`input-file`을 주면 해당 파일을 `input.md`로 복사합니다. 생략하면 표준 입력에서 프롬프트를 읽습니다.

```bash
printf '검증할 작업입니다.' | \
  scripts/delegate.sh stage0-sample luna-verify gpt-5.6-luna

scripts/delegate.sh stage0-sample terra-implement gpt-5.6-terra prompt.md
```

결과는 저장소 루트의 다음 경로에 남습니다.

```text
agents/<YYYY-MM-DD>-<task-slug>/<role>/
  input.md
  output.md
  result.md
```

기존 `result.md`가 있으면 안전을 위해 실행하지 않습니다. 의도적으로 다시 실행하려면 `-f` 또는 `--force`를 함께 전달합니다.

Codex가 실행 초기에 실패해 최종 메시지를 쓰지 못한 경우에도 빈 `result.md`를 남겨 감사 경로를 일관되게 유지합니다. 스크립트의 종료 코드는 Codex의 종료 코드를 그대로 반환합니다.

```bash
scripts/delegate.sh --force stage0-sample luna-verify gpt-5.6-luna prompt.md
```
