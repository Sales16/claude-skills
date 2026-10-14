# claude-skills

Skills para o [Claude Code](https://claude.com/claude-code), escritas para responder em português (pt-BR).

## Skills

| Skill | Como chamar | O que faz |
|---|---|---|
| `revisar-branch` | `/revisar-branch` ou "revise essa branch" | Revisão profunda da branch atual ou do PR dela. Detecta a branch-pai real (develop/main ou outra branch de issue) e revisa só os commits próprios. Usa a issue do Jira do nome da branch como escopo, dispara agentes em paralelo (bugs, edge-cases, segurança, performance etc.), faz red/green de cada teste alterado e valida cada achado antes de reportar. |
| `atualizar-prs` | `/atualizar-prs` ou "atualiza os PRs em cadeia" | Atualiza uma pilha de PRs empilhados (`develop -> PR1 -> PR2 -> PR3`), uma branch por vez a partir da mais próxima da develop. Em cada branch: remove a migration EF própria, mergeia a anterior, resolve conflitos, recria a migration com o custom code, compara antiga x nova, compila e testa. Só commita local, nunca dá push sem ordem explícita e nunca dá force push. |
| `grilling` | "me grelha nesse plano" ou qualquer gatilho "grill" | Entrevista implacável sobre um plano ou decisão, uma pergunta por vez, sempre pelo `AskUserQuestion`, com a resposta recomendada em primeiro. |
| `grill-me` | `/grill-me` | Atalho manual para o `grilling`. |
| `grill-with-docs` | `/grill-with-docs` | `grilling` + `domain-modeling`: grelha o design e já escreve glossário (`CONTEXT.md`) e ADRs durante a conversa. |
| `domain-modeling` | automático ao discutir termos do domínio, `CONTEXT.md` ou ADR | Constrói e afia o modelo de domínio do projeto: questiona termos, inventa cenários de borda e registra glossário e decisões. Conversa em pt-BR, mas mantém o idioma dos arquivos existentes. |

As skills `grilling`, `grill-me`, `grill-with-docs` e `domain-modeling` são versões adaptadas das skills de [mattpocock/skills](https://github.com/mattpocock/skills). As mudanças são: idioma pt-BR e perguntas sempre pelo `AskUserQuestion`.

`revisar-branch` e `atualizar-prs` assumem o padrão: branch `{tipo}/{ISSUE-KEY}`, `gh` autenticado e, no caso do `atualizar-prs`, projeto .NET com EF Core.

## Instalação

### Opção 1 — Marketplace de plugins (recomendado)

Dentro do Claude Code:

```
/plugin marketplace add Sales16/claude-skills
/plugin install sales16-toolkit@sales16-skills
```

Reinicie a sessão. As skills ficam com o prefixo do plugin, por exemplo `/sales16-toolkit:revisar-branch`. Os gatilhos em linguagem natural ("revise essa branch") funcionam igual.

Para atualizar depois:

```
/plugin marketplace update sales16-skills
```

### Opção 2 — `npx skills`

```bash
npx skills add Sales16/claude-skills
```

As skills vão para `~/.agents/skills` com link em `~/.claude/skills`, sem prefixo (`/revisar-branch`).

### Opção 3 — Cópia manual

Clone o repo e copie (ou crie um link de) cada pasta de `skills/` em `~/.claude/skills/`:

```bash
git clone https://github.com/Sales16/claude-skills.git
cp -r claude-skills/skills/* ~/.claude/skills/
```

Para uma skill valer só em um projeto, use `.claude/skills/` na raiz dele em vez de `~/.claude/skills/`.

## Conflito com as skills originais do grill

Se você já instalou as originais com `npx skills add mattpocock/skills`, existem duas skills com o mesmo nome (`grilling`, `grill-me`, `grill-with-docs`, `domain-modeling`). Nesse caso:

- `/grill-me` pode abrir a original, em inglês.
- `grill-me` e `grill-with-docs` chamam o `grilling` pelo nome e podem cair na versão errada.
- `npx skills update` **sobrescreve** as pastas em `~/.agents/skills` com as originais e apaga as adaptações.

Para evitar isso, mantenha só uma versão:

1. Remova as originais:

   ```bash
   npx skills remove grilling grill-me grill-with-docs domain-modeling
   ```

   Se o comando não existir na sua versão do CLI, apague as pastas e os links à mão:

   ```bash
   rm -rf ~/.agents/skills/{grilling,grill-me,grill-with-docs,domain-modeling}
   rm -f  ~/.claude/skills/{grilling,grill-me,grill-with-docs,domain-modeling}
   ```

2. Instale este repo por uma das opções acima.
3. Confira com `/skills` no Claude Code que cada nome aparece uma vez só.
4. Daqui pra frente, não rode `npx skills add mattpocock/skills` sem filtro, nem `npx skills update` para essas quatro skills. Para instalar outras skills do mattpocock, escolha só as que não colidem.

Se quiser manter as duas versões lado a lado, renomeie as daqui: mude o `name:` no `SKILL.md` e o nome da pasta, por exemplo `grilling-ptbr`. Atualize também a referência dentro de `grill-me` e `grill-with-docs` ("Call the Skill tool with ...").

## Licença

[MIT](LICENSE).
