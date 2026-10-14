---
name: atualizar-prs
description: Atualiza em cadeia uma pilha de PRs empilhados (develop -> PR1 -> PR2 -> PR3), de qualquer branch da pilha. Começa pela branch mais próxima da develop e desce uma por vez, sem paralelismo. Em cada branch remove a migration EF própria, mergeia a branch anterior, resolve conflitos, recria a migration preservando o custom code, compara antiga x nova, compila e testa. Só commita local, nunca dá push sem ordem explícita. Use quando pedirem "atualiza os PRs em cadeia", "atualiza a stack", "atualiza minhas branches com a develop" ou /atualizar-prs.
---

# Atualizar PRs em cadeia

Objetivo: deixar cada branch de uma pilha de PRs atualizada com a anterior, com a migration recriada no topo e o build e os testes verdes. Tudo fica em commits locais para o dev revisar.

**Responda sempre em português (pt-BR).** Termos técnicos, comandos, código e mensagens de erro ficam no original.

## Regras invioláveis

- **Nunca dê push durante a skill.** Nenhum `git push`: nem de branch, nem de tag, nem de branch nova. Tudo fica em commits locais. O push só acontece depois do relatório final, quando o dev mandar explicitamente, conforme a seção 6.
- **Force push é proibido sempre**, em qualquer situação, mesmo que o dev peça durante a skill. Isso vale para `--force`, `--force-with-lease`, `+refspec` e push que apague branch remota.
- **Uma branch por vez, em ordem.** Nada em paralelo, nada de subagente mexendo em git ou banco.
- **Qualquer erro interrompe a cadeia inteira**, exceto os erros simples da seção 4. Na dúvida se é simples, não é: pare.
- **Problema não previsto nesta skill: interrompa e avise.** Isso inclui situação estranha, saída inesperada de comando, arquivo inesperado, estado de git ou banco diferente do esperado, ou qualquer coisa que esta skill não descreva. Não improvise solução. Pare, reporte com o formato da seção 4 e espere o dev.
- **Sempre termine com relatório:** o da seção 5 quando a cadeia completa, o da seção 4 quando interromper. Nunca encerre sem um dos dois.
- Nunca rode `git reset --hard`, `git push`, `git rebase`, `git checkout -- .`, `git clean` nem `--no-verify` por conta própria. Na interrupção, só **imprima** os comandos de rollback para o dev.
- Arquivos em `*/Migrations/*`: o hook do cnb-toolkit bloqueia o `Edit`/`Write` neles. Não tente contornar o hook. A migration só é alterada por `dotnet ef` e por cópia de arquivo via shell (`cp`), como descrito no passo 6.

## 1. Descobrir a cadeia

A cadeia vem **só dos PRs abertos no GitHub**.

1. Árvore de trabalho limpa: `git status --porcelain` vazio. Se houver qualquer alteração, aborte e peça para o dev commitar ou guardar. Não faça stash.
2. `git fetch origin --prune`.
3. `gh pr list --state open --limit 200 --json number,headRefName,baseRefName,url` → mapa `head -> base`.
4. A branch atual precisa ser `head` de algum PR aberto. Se não for, pare e pergunte qual é a pilha.
5. **Subir até a raiz:** a partir do PR da branch atual, siga `baseRefName`:
   - A base é `develop`, ou `main`/`master` se o repo não tiver develop → chegou na raiz.
   - A base é `head` de outro PR aberto → continue subindo.
   - Nenhum PR aberto tem essa base como `head`: rode `gh pr list --state merged --head <base> --json number,mergedAt`.
     - **Mergeado:** essa branch já saiu da cadeia. A branch de baixo passa a ser a raiz, com pai `origin/develop`. Anote que o PR dela precisa ter o destino trocado no GitHub.
     - **Fechado sem merge, ou sem PR:** pare e pergunte.
6. **Descer até a folha:** a partir da branch atual, procure PRs abertos com `baseRefName == <branch>`:
   - **Zero:** fim da cadeia.
   - **Um:** continue descendo.
   - **Dois ou mais:** a cadeia bifurca. Pare e pergunte ao dev qual ramo seguir.
7. Para cada branch da cadeia:
   - Garanta a branch local. Se ela não existir, crie com `git branch <b> origin/<b>`.
   - Sincronize com o origin **só por fast-forward**. Se a local estiver atrás, rode `git merge --ff-only origin/<b>` com ela em checkout, ou `git fetch origin <b>:<b>` sem checkout.
   - Local e remota divergiram (a local tem commits que a remota não tem e vice-versa)? Pare.
8. Grave o estado inicial no scratchpad da sessão, em `atualizar-prs/estado.md`. Registre:
   - a branch original;
   - para cada branch, o nome, o número do PR, o pai efetivo e o **SHA inicial** (`git rev-parse <b>`);
   - as migrations próprias de cada branch, calculadas no item 9.

   O SHA inicial é a base de todo rollback.
9. **Migrations próprias** de cada branch: arquivos de migration adicionados desde o ponto em que ela saiu do pai **original**. Use o SHA inicial do pai, ou `origin/develop` na raiz:

   ```bash
   git diff --name-only --diff-filter=A $(git merge-base <b> <pai-ref-inicial>) <b> -- '*/Migrations/*.cs' \
     | grep -Ev '\.Designer\.cs$|ModelSnapshot\.cs$'
   ```

   - Zero migrations: a branch só passa por merge, build e testes. Pule os passos de migration.
   - **Mais de uma migration na mesma branch:** pare e pergunte ao dev.
10. **Parâmetros do EF**, uma vez por repo:
    - `--project`: o `.csproj` que contém a pasta `Migrations`.
    - `--context`: o tipo em `[DbContext(typeof(X))]` do `.Designer.cs`.
    - `--startup-project`: o projeto do site/API. Procure no `CLAUDE.md` ou em scripts do repo. Se houver mais de uma opção, pergunte.

    Monte `EF_ARGS="--project ... --startup-project ... --context ..."` e use em **todo** comando `dotnet ef`.
11. Mostre ao dev:
    - a cadeia em ordem, por exemplo `origin/develop -> feature/EN-5000 (#12) -> feature/EN-5001 (#13)`;
    - os PRs já mergeados que foram pulados;
    - as migrations de cada branch e os SHAs iniciais.

    Peça confirmação com `AskUserQuestion` antes de mexer em qualquer coisa.

## 2. Banco local

`dotnet ef migrations remove` exige que a migration **não** esteja aplicada no banco. O banco é um só para a cadeia inteira, então o estado dele é controlado entre uma branch e a próxima.

**Alvo do banco antes do remove:** a última migration presente **ao mesmo tempo** na branch (antes do merge) e no pai que ela vai receber (já atualizado). Quando o pai não ganhou migration nova, esse alvo é a penúltima migration da branch. Quando o pai ganhou migrations novas (vindas da develop, ou a migration recriada do pai), voltar só até a penúltima deixaria aplicada no banco uma migration que vai mudar de id. Por isso o alvo é o ponto comum. Para calcular:

```bash
# ids de migration de uma ref (timestamp_Nome), sem Designer e sem snapshot
git ls-tree -r --name-only <ref> -- <pasta>/Migrations | grep -E '/[0-9]{14}_[^/]+\.cs$' | grep -v '\.Designer\.cs$' | xargs -n1 basename | sed 's/\.cs$//' | sort
```

O alvo é o maior id da interseção entre `<b>` e `<pai-ref>`.

- **Primeira branch da cadeia (raiz):**
  - Em checkout nela, rode `dotnet ef migrations list $EF_ARGS`.
  - Se houver **qualquer** migration `(Pending)`, o banco não está na última migration da branch. Pare a cadeia e reporte o estado do banco.
  - Se estiver tudo aplicado, rode `dotnet ef database update <alvo> $EF_ARGS`.
- **Transição para a próxima branch:**
  - Ainda na branch que acabou de ser atualizada, calcule o alvo da próxima: a interseção da próxima, antes do merge, com a atual, já atualizada.
  - Rode `dotnet ef database update <alvo> $EF_ARGS`.
  - Só então faça o checkout da próxima.
  - Na próxima, confira com `dotnet ef migrations list` que a migration própria aparece como `(Pending)`.

Se qualquer `database update` falhar, pare.

## 3. Fluxo por branch

Faça o checkout da branch e execute os passos em ordem. Pai efetivo: `origin/develop` na raiz; nas demais, a branch **local** anterior, já atualizada e sem push.

Sem migration própria: pule os passos 1–3 e 6–9, mas rode o merge, os conflitos, o build e os testes.

### Passo 1 — Remover a migration

1. Salve cópias **antes** de remover, no scratchpad, em `atualizar-prs/<branch>/`: a migration `<ts>_<Nome>.cs` e o `<ts>_<Nome>.Designer.cs`. Anote o `<Nome>`.
2. Custom code: liste as chamadas `migrationBuilder.Sql(` em `Up` e `Down` da cópia. Só isso é considerado custom code.
3. Coloque o banco no alvo, conforme a seção 2.
4. `dotnet ef migrations remove $EF_ARGS`. Confira que os dois arquivos sumiram e que o `ModelSnapshot` mudou.

### Passo 2 — Build

`dotnet build` da solution. O build regenera o XML de documentação do site, por exemplo `CnbCF.Signer.Site.xml`. Confira que os `<member>` da migration removida (`T:...Migrations.<Nome>`, `M:...<Nome>.Up`, `.Down`, `.BuildTargetModel`) **não** aparecem mais no XML.

### Passo 3 — Commit da remoção

1. `git status --porcelain` só pode mostrar:
   - os dois arquivos da migration, deletados;
   - o `ModelSnapshot`;
   - o XML de documentação.

   Qualquer outro arquivo alterado pelo build é inesperado. Pare.
2. `git add` desses caminhos, e só deles.
3. `git commit -m "chore: remove migration <Nome> para atualizar com <pai>"`.

### Passo 4 — Merge do pai

`git merge --no-edit <pai>`. Merge limpo: siga para o passo 6.

### Passo 5 — Conflitos

- **`ModelSnapshot.cs`:** fique com a versão do pai (`git checkout --theirs -- <arquivo>`). A migration própria foi removida, então o snapshot certo é o do pai. O passo 6 recria o resto.
- **XML de documentação:** fique com a versão do pai. O build do passo 7 regenera o arquivo.
- **Código:** resolva só quando a resolução for óbvia e mecânica:
  - os dois lados adicionaram coisas independentes (usings, itens de lista, métodos diferentes);
  - a mesma mudança foi feita dos dois lados.

  Conflito que exige decisão de regra de negócio, ou em que um lado apaga o que o outro altera: **pare**.
- **Migration de outra branch duplicada:** por exemplo, um pai mergeado por squash traz a mesma migration com outro timestamp. Pare.

Ao terminar, confira que não sobrou marcador de conflito: `git diff --check` e `grep -rn '^<<<<<<<\|^>>>>>>>' -- <arquivos resolvidos>`. Depois rode `git add` dos arquivos resolvidos e `git commit --no-edit`.

Depois do merge, confira que não existem duas migrations com o mesmo `<Nome>` nem com a mesma classe. Se existirem, pare.

### Passo 6 — Recriar a migration e reaplicar o custom code

1. `dotnet ef migrations add <Nome> $EF_ARGS`, com o **mesmo nome** da antiga.
2. Compare a antiga com a nova gerada:

   ```bash
   git diff --no-index --ignore-cr-at-eol <scratch>/<ts-antigo>_<Nome>.cs <pasta>/Migrations/<ts-novo>_<Nome>.cs
   ```

   Diferenças aceitas: **só** linhas removidas (`-`) que pertencem às chamadas `migrationBuilder.Sql(...)` listadas no passo 1. Isso inclui as linhas internas de strings verbatim de várias linhas.

   Qualquer outra diferença significa que o código gerado mudou: linha adicionada (`+`), ou linha removida fora de um `Sql(...)`. Exemplos: a develop já criou a coluna, ou mudou um tipo. Pare e mostre o diff.
3. Diff aceito: reaplique o custom code **copiando o arquivo antigo por cima do novo** via shell:

   ```bash
   cp <scratch>/<ts-antigo>_<Nome>.cs <pasta>/Migrations/<ts-novo>_<Nome>.cs
   ```

   O arquivo de classe não carrega o timestamp, que fica só no nome do arquivo e no `Designer.cs`. Por isso a cópia preserva o custom code, a encoding e os finais de linha. Não use `Edit`/`Write` aqui. O `Designer.cs` novo fica como o EF gerou.

### Passo 7 — Build

`dotnet build` da solution. Confira que os `<member>` da migration voltaram ao XML de documentação.

### Passo 8 — Commit da migration refeita

1. `git status --porcelain` só pode mostrar:
   - a migration nova (`.cs` e `.Designer.cs`);
   - o `ModelSnapshot`;
   - o XML de documentação.

   Qualquer outro arquivo é inesperado. Pare.
2. `git add` desses caminhos.
3. `git commit -m "chore: refaz migration <Nome>"`.

### Passo 9 — Comparar antiga x nova

- `git diff --no-index --ignore-cr-at-eol <cópia antiga> <migration nova>` deve sair **vazio**: `Up`/`Down` idênticos, com o custom code incluído.
- O `Designer.cs` novo deve ter o mesmo namespace e a mesma classe da cópia antiga. Só o id em `[Migration("...")]` e o modelo alvo podem mudar.
- Diferença em `Up`/`Down`: pare.

### Passo 10 — Compilar, testar e aplicar

1. `dotnet build` da solution, sem erro.
2. `dotnet test` se o repo tiver projeto de teste. Teste falhando interrompe a cadeia.
3. `dotnet ef database update $EF_ARGS` aplica as migrations do pai e a recriada. Isso também valida que a migration roda de verdade.
4. `git status --porcelain` vazio ao final da branch.

Depois siga para a transição da seção 2 e para a próxima branch.

## 4. Erros: corrigir ou parar

**Corrija e continue** só nestes casos, todos mecânicos e causados pelo merge:

- marcador de conflito esquecido;
- `using` faltando ou duplicado;
- símbolo renomeado no pai cujo novo nome é inequívoco;
- assinatura alterada no pai com um único jeito óbvio de adaptar a chamada.

Commite a correção separada: `git commit -m "fix: corrige <o quê> após merge com <pai>"`.

**Pare a cadeia inteira** em todo o resto. Exemplos:

- erro do `dotnet ef`;
- diff de migration fora do permitido;
- teste falhando;
- conflito de lógica;
- banco fora do estado esperado;
- hook de git falhando;
- qualquer coisa que exija decidir comportamento.

Ao parar, **não** desfaça nada sozinho. Reporte:

```markdown
## Atualização interrompida — <branch> · passo <N>

**Erro**: <mensagem exata, a linha decisiva>
**Causa provável**: <uma ou duas frases>

**Estado atual**
- Branch em checkout: <b> · merge em andamento: sim/não
- Banco local: última migration aplicada <id>
- Branches já atualizadas (commits locais, sem push): <lista>
- Branches não tocadas: <lista>

**Rollback (rode só se quiser descartar)**
git merge --abort            # se houver merge em andamento
git checkout <b1> && git reset --hard <sha-inicial-b1>
git checkout <b2> && git reset --hard <sha-inicial-b2>
dotnet ef database update <id> <EF_ARGS>   # volta o banco ao estado inicial
```

## 5. Relatório final

Ao terminar a cadeia, faça o checkout da branch original e reporte:

```markdown
## PRs atualizados (nada foi enviado ao remoto)

Cadeia: origin/develop -> <b1> (#N) -> <b2> (#N) -> ...
PRs já mergeados pulados: <lista ou "nenhum">

### <b1> (#N) — pai: origin/develop
- Commits: <sha> remove migration · <sha> merge · <sha> refaz migration · <sha> fix (se houve)
- Conflitos: <arquivo> — <como foi resolvido> / nenhum
- Migration <Nome>: <ts-antigo> -> <ts-novo> · Up/Down idênticos · custom code: <N> Sql reaplicados
- Build OK · Testes OK (<n> testes)

### <b2> ...

### Pendências no GitHub
- PR #N aponta para <branch-mergeada>: trocar o destino para develop

### Banco local
Na última migration de <última branch> (<id>). A branch em checkout agora é <original>.
Se necessário, ajuste com `dotnet ef database update <id>`.
```

Termine dizendo que as branches estão só com commits locais e esperando a revisão do dev.

## 6. Push (só com ordem explícita do dev)

Só quando o dev pedir o push, por exemplo "pode dar push":

1. Envie em ordem da raiz até a folha, um por vez, com `git push origin <b>`. O merge preserva o histórico, então o push é fast-forward.
2. **Nunca use force push**, em nenhuma forma: `--force`, `--force-with-lease` ou `+refspec`.
3. Push rejeitado (alguém enviou commit no meio do caminho): pare e reporte. Não force, não faça pull e não faça rebase.
4. Ao terminar, liste as branches enviadas e os SHAs.
5. Troque o destino dos PRs listados em "Pendências no GitHub" (`gh pr edit <N> --base develop`) **só** se o dev confirmar.
