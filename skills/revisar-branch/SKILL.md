---
name: revisar-branch
description: Revisão profunda da branch atual (ou do PR aberto dela) contra a branch-pai real — develop/main ou outra branch de issue da qual ela foi criada, revisando só os commits próprios —, usando a issue do Jira do nome da branch como contexto de escopo. Dispara múltiplos agentes em paralelo — bugs, exceções, edge-cases, duplicidade, segurança, performance, manutenibilidade —, verifica red/green de cada teste novo ou alterado, valida criticamente cada achado e propõe um fix por achado. Use quando pedirem "revise essa branch", "revise meu PR", "review antes de abrir PR", ou antes de /finish-issue.
---

# Revisão de branch / PR

Objetivo: entregar uma lista curta de problemas **reais**, cada um com localização exata (`arquivo:linha`), severidade e um fix concreto. Falsos positivos custam mais que achados perdidos — todo achado passa por validação antes de aparecer na resposta.

## Regras invioláveis do working tree

O dev pode rodar esta revisão **antes de commitar**. As mudanças não commitadas (staged, unstaged e arquivos novos não rastreados) fazem parte da revisão em **todas** as etapas e **nunca** podem ser alteradas.

- **No working tree principal só se lê.** Ninguém — main loop ou agente — faz ali `Edit`/`Write`, `git stash`, `git checkout`/`switch`/`restore`/`reset`/`clean`/`commit`/`add`, formatter, build ou teste (build/teste escrevem em `bin/`/`obj/` e podem disparar hooks).
- **Tudo que modifica algo roda num worktree separado** criado a partir do estado atual, incluindo as mudanças não commitadas (seção 2.3). Hoje isso é o script de testes da seção 4; qualquer outra etapa que precise buildar, rodar ou mutar código segue a mesma regra.
- Agentes que só leem (revisores da seção 3) ficam no working tree principal e recebem no prompt a instrução explícita: "somente leitura — não edite arquivos, não rode build/teste, não rode comando git que altere working tree, index ou branch".
- Comandos permitidos no principal: `git fetch`, `git diff`, `git log`, `git status`, `git show`, `git merge-base`, `git rev-list`, `git for-each-ref`, `git ls-files`, `git worktree add/remove`, e `git read-tree`/`git add -A`/`git write-tree` **somente com `GIT_INDEX_FILE` apontando para um índice temporário** mais `git commit-tree` (seção 2.3 — só gravam objetos e metadados, não tocam arquivos nem o index do dev), `gh pr view`, leitura e busca de arquivos.

**Responda sempre em português (pt-BR).** Termos técnicos, nomes de API, código e mensagens de erro ficam no original.

## 1. Contexto: issue do Jira

O nome da branch é a chave do card: `{tipo}/{ISSUE-KEY}` (ex.: `feature/EN-5386` → `EN-5386`).

1. Extraia a chave de `git rev-parse --abbrev-ref HEAD`. Se a branch não tiver chave reconhecível, siga sem Jira e diga isso na resposta.
2. Leia a issue pelo MCP Atlassian (`getJiraIssue`, cloudId `lacuna.atlassian.net`): título, descrição, critérios de aceite, tipo (bug/feature/refactor), status.
3. Leia os **comentários** da issue — costumam conter a regra de negócio real, exceções combinadas e mudanças de escopo que não estão na descrição.
4. Veja issues relacionadas/subtasks e o epic pai quando a descrição citar dependência ou contrato de outro sistema.
5. Se a issue for **bug**: extraia o passo-a-passo de reprodução — ele é o roteiro de validação e deveria existir como teste.

Use a issue para três checagens que só o Jira permite:

- **Escopo coberto**: cada critério de aceite tem código correspondente no diff? Falta algum?
- **Escopo excedido**: o diff mexe em coisa que a issue não pede? Se sim, não é bug, mas vale citar (risco de regressão fora do combinado).
- **Interpretação**: o código resolve o que a issue pede, ou resolve outra coisa parecida? Divergência aqui é o achado mais caro de todos.

## 2. Escopo do diff

### 2.1 Descobrir a branch-pai

A branch atual pode ter sido criada a partir de outra branch de issue (ex.: `feature/EN-5001` criada de `feature/EN-5000`, que por sua vez sai da `develop`). Nesse caso revise **só os commits da branch atual** — as mudanças da branch-pai pertencem a outra issue e outro PR.

1. `git fetch origin --prune` para ter as refs remotas atualizadas.
2. **PR aberto manda**: se existir PR, `gh pr view --json baseRefName -q .baseRefName` é a branch-pai. Use-a e pule para o passo 6.
3. Base padrão: `origin/develop` (ou `origin/main` se o repo não tiver develop). Calcule `MB_DEFAULT=$(git merge-base HEAD origin/develop)`.
4. Candidatas a pai: toda branch remota de issue (`git for-each-ref --format='%(refname:short)' refs/remotes/origin`, excluindo `HEAD`, a própria branch atual, `develop`, `main`, `master`, `release/*`, `hotfix/*` de versão). Para cada candidata `C`:
   - `MB_C=$(git merge-base HEAD C)`.
   - Ela é pai plausível só se `MB_C` for **diferente** de `MB_DEFAULT` e descendente dele: `git merge-base --is-ancestor $MB_DEFAULT $MB_C`.
   - Distância: `git rev-list --count $MB_C..HEAD` (commits exclusivos da branch atual a partir dessa candidata).
5. Escolha a candidata com **menor distância**. Sem candidata válida → a branch sai direto da develop/main, base = `origin/develop`. Empate ou dúvida real (duas branches apontando para o mesmo commit) → pergunte ao dev qual é a pai antes de seguir.
6. Base final do diff: `BASE=$(git merge-base HEAD <branch-pai>)`. Diga na resposta qual branch-pai foi detectada e como (PR ou heurística).
7. **Pai já mergeada**: se a branch-pai já entrou na develop por merge normal, `git merge-base --is-ancestor origin/<pai> origin/develop` retorna sucesso → use `origin/develop` como base (dá o mesmo diff e é o alvo real do PR). Se entrou por squash, a develop não contém os commits dela: continue usando a branch-pai como base e avise o dev que o PR vai precisar de rebase sobre a develop.

Se a branch-pai for de outra issue (`{tipo}/{OUTRA-KEY}`), leia o título dela no Jira só para saber o que **não** é escopo deste review — não revise o diff dela.

### 2.2 Diff

1. Diff completo **incluindo as mudanças não commitadas**: `git diff $BASE` e `git diff --stat $BASE` (sem `...HEAD` — assim compara o `BASE` com o working tree, pegando staged e unstaged). Sempre contra o `BASE` da seção 2.1, nunca direto contra a develop quando houver branch-pai.
2. Arquivos novos não rastreados não aparecem no `git diff`: liste com `git ls-files --others --exclude-standard` e trate cada um como arquivo inteiro adicionado.
3. Confira a sanidade: os commits de `git log --oneline $BASE..HEAD` devem ser todos da issue atual. Commit com a chave da branch-pai na mensagem indica base errada — reavalie a 2.1. Diga na resposta se a revisão incluiu mudanças não commitadas e quantos arquivos.
4. Histórico: `git log --oneline $BASE..HEAD` — commits `WIP`, revert seguido de reaplicação e "fix review points" indicam pontos frágeis; olhe esses arquivos com mais atenção.
5. PR aberto: `gh pr view` e `gh pr view --comments`. Se houver review anterior, **verifique um por um se os pontos apontados foram realmente resolvidos** — não assuma pelo commit message.
6. Leia o `CLAUDE.md` da raiz e os aninhados nas pastas tocadas; as regras deles são critério de revisão.
7. Liste os arquivos por camada (backend, frontend, migrations, testes, configs) — isso define quais agentes valem a pena.

Não revise código fora do diff, exceto para entender o contexto de uma linha alterada (chamadores, contrato, invariantes). Código vindo da branch-pai conta como fora do diff. Passe aos agentes o comando `git diff $BASE` com o `BASE` resolvido (nunca `origin/develop` genérico, nunca `$BASE...HEAD`) mais a lista de arquivos não rastreados.

### 2.3 Worktree isolado para os testes

Sempre que o repo tiver solução buildável, prepare logo aqui uma cópia isolada do estado atual, **com** as mudanças não commitadas. A seção 4 builda, roda testes e, quando há teste novo, muta código de produção; fazer isso no working tree principal faria os agentes de revisão lerem código mutado e disputarem `bin/`/`obj/` com o build.

A cópia é um commit sintético montado com um índice temporário — pega staged, unstaged, não rastreados, binários, renames e deleções sem tocar no working tree nem no index do dev. Rode tudo numa **única** chamada `Bash` (o `GIT_INDEX_FILE` não pode vazar para outras chamadas):

```bash
RB="$(mktemp -d)"
command -v cygpath > /dev/null && RB="$(cygpath -m "$RB")"
touch "$RB/.revisar-branch" && mkdir -p "$RB/mut" &&
GIT_INDEX_FILE="$RB/idx" git read-tree HEAD &&
GIT_INDEX_FILE="$RB/idx" git add -A &&
T="$(GIT_INDEX_FILE="$RB/idx" git write-tree)" &&
C="$(git commit-tree "$T" -p HEAD -m revisar-branch)" &&
git worktree add --detach "$RB/wt" "$C" &&
{ [ ! -f "$RB/wt/.gitmodules" ] || git -C "$RB/wt" submodule update --init --recursive; } &&
git -C "$RB/wt" status --porcelain && echo "RB=$RB"
```

1. Anote o `RB` impresso: ele é absoluto e, no Windows, sai no formato `C:/...` (via `cygpath -m`), que serve igual para Bash, git, dotnet e para as ferramentas `Read`/`Write`/`Edit`. Use **sempre** os caminhos literais `<RB>/wt` (o worktree, `WT`) e `<RB>/mut` (`MUT`) — variáveis de shell não persistem entre chamadas.
2. `git status --porcelain` do worktree deve sair vazio. Se não sair, ou qualquer comando falhar, pare a seção 4 e diga na resposta que o red/green não foi verificado.
3. **Dispare o script de testes já aqui**, antes dos revisores — o restore/build frio é a etapa mais lenta e deve começar o quanto antes (seção 4.1).

O worktree é usado **só** pelo script de testes. Todo o resto da revisão continua no working tree principal.

## 3. Agentes em paralelo

Dispare os agentes aplicáveis **numa única mensagem** para rodarem concorrentes, enquanto o script de testes da seção 4 já roda em background. Cada revisor recebe: resumo da issue do Jira, lista de arquivos alterados (incluindo não rastreados), o comando `git diff $BASE` que deve rodar, a instrução de **somente leitura** das regras invioláveis e a instrução de retornar achados como `arquivo:linha — severidade — problema — fix sugerido`, sem elogios e sem sugestões fora do diff.

**Custo por complexidade**: nem todo achado exige o modelo mais caro. Regra de bolso ao chamar `Agent`:

- **Sem `model` (herda o do main loop)** — só para o que exige mais raciocínio e onde um falso negativo é caro: interpretação de escopo vs. Jira, bugs/exceções, segurança, contrato/compatibilidade, qualidade geral (`code-reviewer`).
- **`model: "sonnet"`** — raciocínio moderado, escopo bem definido: `silent-failure-hunter`, `pr-test-analyzer`, `type-design-analyzer`, performance.
- **`model: "haiku"`** — checagem mecânica ou grep-driven, baixo risco de falso negativo caro: `comment-analyzer`, duplicidade/reuso (é busca + comparação, não julgamento fino), manutenibilidade (nome/tamanho/número mágico), higiene do diff (seção 5), `cavecrew-reviewer`.

Se o diff for pequeno/trivial, prefira subir tudo pra `haiku` — a régua acima é para o caso geral com diff de porte médio/grande.

Base recomendada (use o que existir no ambiente):

- `pr-review-toolkit:code-reviewer` — qualidade geral e aderência ao CLAUDE.md. *(sem override de model)*
- `pr-review-toolkit:silent-failure-hunter` — catch vazio, erro engolido, fallback que esconde falha, valor default em caso de exceção. *(`model: "sonnet"`)*
- `pr-review-toolkit:pr-test-analyzer` — cobertura comportamental dos testes novos/alterados e lacunas críticas. *(`model: "sonnet"`)*
- `pr-review-toolkit:type-design-analyzer` — só se houver tipos/DTOs/enums novos ou alterados. *(`model: "sonnet"`)*
- `pr-review-toolkit:comment-analyzer` — só se houver comentários/docs adicionados ou alterados. *(`model: "haiku"`)*
- `caveman:cavecrew-reviewer` — segunda opinião barata sobre o mesmo diff. *(`model: "haiku"`)*

Além desses, use agentes `general-purpose` com escopos explicitamente disjuntos, um por ponto de vista, para não convergirem na mesma leitura:

- **Bugs e exceções** *(sem override)*: null/undefined, índice, conversão, `await` faltando, task não aguardada, ordem de operações, transação não commitada/rollback, race condition, exceção não tratada subindo ao usuário.
- **Edge-cases** *(sem override)*: coleção vazia, item único, limites (0, 1, máximo), string vazia vs. nula, timeout, cancelamento, resposta HTTP de erro, payload malformado, timezone/cultura, concorrência, requisição duplicada/reentrante.
- **Duplicidade e reuso** *(`model: "haiku"`)*: o diff reimplementa algo que já existe no repo ou nas libs compartilhadas? Faça grep antes de afirmar que não existe.
- **Segurança** *(sem override)*: autorização por endpoint, IDOR (objeto de outro tenant/cartório), dado sensível em log, injeção (SQL/HTML/comando), validação server-side ausente, segredo hardcoded, redirect/CORS aberto, upload sem validação de tipo/tamanho.
- **Performance** *(`model: "sonnet"`)*: N+1 query, consulta dentro de loop, `await` em loop que poderia ser paralelo, sync-over-async (`.Result`/`.Wait()`), falta de paginação, carregar coleção inteira em memória, índice ausente para o novo filtro, chamada HTTP externa sem timeout, cache não invalidado.
- **Manutenibilidade** *(`model: "haiku"`)*: acoplamento novo, método fazendo coisas demais, nome que mente, número mágico, config hardcoded, fluxo difícil de seguir, indireção desnecessária.
- **Contrato e compatibilidade** *(sem override)*: endpoint/rota alterada, campo removido ou renomeado em DTO, valor de enum reordenado, mudança que quebra cliente já publicado, migration destrutiva (drop/alter de coluna com dado), nova config sem valor definido nos ambientes, feature flag sem default seguro.

Ajuste por camada:

- **Frontend (Angular)**: subscription sem `takeUntil`/`unsubscribe`, estado de loading/erro não tratado, validador duplicado em vez de reuso das libs compartilhadas, cor/tamanho hardcoded em vez do tema, texto de UI fora do pt-BR ou sem revisão de copy, formulário sem validação equivalente no backend.
- **Backend (.NET)**: migration editada à mão (proibido — deve ser gerada), `DbContext` usado fora de escopo, query com `AsNoTracking` faltando ou sobrando, validação de entrada, mapeamento DTO↔entidade incompleto.

Se o diff tocar apenas 1–2 arquivos triviais, corte a lista de agentes — não gaste enxame em mudança mecânica; diga isso e revise inline.

## 4. Verificação red/green dos testes (script em background)

Sem agente: o main loop prepara as mutações e um único script, `scripts/red-green.sh` (na pasta desta skill), roda tudo em sequência dentro de `<RB>/wt`, sem volta de LLM entre os passos. O tempo de build/teste é o mesmo; some o overhead de raciocínio e de tool call por passo. O script é .NET; em outra stack, faça uma cópia com os comandos equivalentes (build uma vez, testes sem rebuild, filtro por nome).

O script recusa rodar se `WT`/`MUT` vierem vazios ou relativos, se `WT` não estiver num diretório com o marcador `.revisar-branch` da seção 2.3, ou se `WT` for o worktree principal (sai com código 90). **Nunca** rode `cp`, `dotnet build` ou `dotnet test` à mão para o red/green — sempre pelo script. Todo `dotnet test` roda com timeout de 600 s (`RB_TEST_TIMEOUT` muda), para uma mutação que gere loop infinito não travar a revisão.

### 4.1 Disparo (ainda na seção 2.3)

**Sem teste novo ou alterado no diff**: não há red/green a fazer — basta garantir que as alterações não quebraram nada. Dispare só a suíte completa, com `Bash` e `run_in_background: true`, e pule a 4.2:

```bash
bash "<pasta-da-skill>/scripts/red-green.sh" suite "<RB>/wt" "<RB>/mut" "<solução relativa ao WT>"
```

O modo `suite` roda `dotnet restore`, `dotnet build --no-restore` e `dotnet test --no-build` da solução inteira e grava `restore`/`build`/`final-test` no `status`. Na 4.3 valem só as linhas desses três.

**Com teste novo ou alterado**: monte o filtro de todos os testes novos/alterados (`FullyQualifiedName~TesteA|FullyQualifiedName~TesteB`) e dispare com `Bash` e `run_in_background: true`, usando os caminhos literais:

```bash
bash "<pasta-da-skill>/scripts/red-green.sh" run "<RB>/wt" "<RB>/mut" "<solução relativa ao WT>" "<filtro green>"
```

O script faz, sem esperar ninguém: `dotnet restore` e `dotnet build --no-restore` da solução uma vez, e o green em lote com `dotnet test --no-build --filter`. Se restore ou build falharem, ele grava `mutations=skipped` e termina sem tentar mutação nenhuma. Senão, fica aguardando o arquivo `<RB>/mut/READY` (timeout de 30 min, `RB_READY_TIMEOUT` muda) para começar as mutações.

### 4.2 Mutações (main loop, enquanto o script e os revisores rodam)

Para cada teste novo ou alterado, uma mutação, em **um único arquivo** de produção:

1. Leia o teste e o código de produção que ele protege no working tree principal (só leitura).
2. Escolha uma quebra que **esse** teste deveria pegar e que **compile**: inverter a condição, remover a validação, retornar o valor errado. Mutação que não compila não serve.
3. Copie o arquivo original do worktree: `cp "<RB>/wt/<caminho>" "<RB>/mut/<id>.file"`. Depois faça `Read` + `Edit` **só no trecho mutado** de `<RB>/mut/<id>.file`. Nunca reescreva o arquivo inteiro com `Write` (perde BOM/CRLF e altera linhas fora da mutação), nunca edite no working tree principal nem no `<RB>/wt` (o script está buildando lá).
4. Adicione a linha do manifesto via `Bash`, com TAB garantido e sem BOM — nunca com `Write`:
   ```bash
   printf '%s\t%s\t%s\t%s\n' "<id>" "<projeto de teste relativo ao WT>" "<filtro do teste>" "<arquivo de produção relativo ao WT>" >> "<RB>/mut/manifest.tsv"
   ```
   Use `<id>` curto e único (`m01`, `m02`...). Nenhum campo pode ficar vazio.

Ao terminar todas, crie `<RB>/mut/READY` com `touch` (mesmo sem nenhuma mutação, para o script não ficar esperando o timeout). Depois do `READY`, não mexa em mais nada dentro de `<RB>/mut`.

Para cada linha do manifesto, o script: salva o original, copia o mutado por cima, confere que o conteúdo mudou, roda `dotnet build <proj> --no-restore` (incremental), roda `dotnet test <proj> --no-build --filter <filtro>` só se o build passou, restaura o original e confere que o arquivo e o `git diff HEAD` do worktree voltaram ao estado de antes da mutação. Restauração falha aborta o script (código 92). No fim roda build e suíte completa uma vez.

### 4.3 Leitura do resultado (seção 6)

O harness avisa quando o script termina. Leia `<RB>/mut/log/status` e, conforme a linha, o log correspondente. Primeiro confira que **todo** `<id>` do `manifest.tsv` tem uma linha no `status` — id sem linha foi perdido; trate como "red não verificado".

- `restore`/`build` ≠ 0 com `mutations=skipped` → leia o `.txt` da etapa. Build quebrado no estado do dev é achado crítico. Nenhum red foi tentado; não refaça mutações.
- `green` ≠ 0 ou `green=timeout` → leia `green.txt`. Teste que falha no green é achado, e o red dele não vale. Mesmo com `green=0`, confirme que **cada** teste do filtro aparece como executado e aprovado — filtro que não casou com nenhum teste também pode sair com código 0.
- `<id> build≠0 test=skip` → **mutação inválida** (não compilou), não é red OK. Refaça uma vez: recopie o original para `<RB>/mut/<id>.file`, aplique outra mutação com `Edit` e rode `bash "<pasta-da-skill>/scripts/red-green.sh" one "<RB>/wt" "<RB>/mut" <id>` (resultado sai como `<id>.retry` no `status`). Se falhar de novo, reporte como "red não verificado".
- `<id> mut=NOOP` → o arquivo mutado ficou igual ao original; refaça a mutação e rode o modo `one`, como acima.
- `<id> build=0 test≠0` → abra `<id>.test.txt` e confirme que falhou **esse** teste, na asserção esperada. Falha por exceção não relacionada ou outro teste não conta como red OK.
- `<id> build=0 test=timeout` → abra `<id>.test.txt`. Só é red OK se o log mostrar que o teste certo travou por causa da mutação; senão, "red não verificado".
- `<id> build=0 test=0` → abra `<id>.test.txt`: se o teste rodou e passou, ele **não testa nada** — achado de severidade alta. Se o filtro não casou com nenhum teste, corrija o filtro na linha do manifesto (reescreva o arquivo via `printf`) e rode o modo `one`.
- `<id> setup=FAIL` → campo vazio, arquivo mutado, de produção ou projeto não encontrado, ou `cp` falhou; corrija e rode o modo `one`.
- `<id> restore=FAIL`, `ready=timeout`, código 90 ou ausência de `done` → o script parou no meio; diga isso na resposta e não assuma resultado para os testes restantes.
- `final-build`/`final-test` ≠ 0 → quebra colateral; leia o log. Se não houver como rodar no ambiente, diga isso explicitamente em vez de assumir que passam.

Cobertura vs. Jira: cada critério de aceite e cada passo de reprodução do bug deveria ter um teste. Aponte os que não têm.

## 5. Higiene do diff

Checagem mecânica rápida, direto no diff:

- `console.log`, `debugger`, `Debug.WriteLine`, print de depuração, código comentado, `TODO`/`FIXME` novo sem issue.
- Segredo, token, senha, connection string ou URL de ambiente em código ou config commitada.
- Arquivo gerado/binário/lock desnecessário, arquivo de IDE, arquivo temporário, pasta de build.
- Arquivo tocado sem relação com a issue (rename automático do editor, reformatação de arquivo inteiro escondendo a mudança real).
- Mudança de formatação misturada com mudança de lógica no mesmo arquivo, dificultando a revisão.

## 6. Validação crítica antes de responder

Se a seção 4 rodou, espere a notificação de término do script e interprete o resultado conforme a 4.3 antes de fechar a validação. Depois, remova tudo: `git worktree remove --force "<RB>/wt"` e `rm -rf "<RB>"`. Se o script abortou ou a restauração falhou, remova mesmo assim — o tree principal não foi tocado — e cite a falha na resposta.

Junte todos os achados (seus + dos agentes), deduplique por `arquivo:linha` e avalie **cada um separadamente**:

- Leia o código real ao redor — não confie no resumo do agente.
- Descreva o cenário concreto de falha: entrada/estado → resultado errado. Se você não conseguir escrever esse cenário, o achado não sobrevive.
- Verifique se algo antes no fluxo já impede o cenário (validação no controller, `[Required]`, guard, tipo não-nulo, constraint no banco).
- Verifique se é pré-existente ao diff. Se é, marque como pré-existente e rebaixe a prioridade — não é bloqueio deste PR. Problema introduzido pela branch-pai também é pré-existente aqui: cite como "vem de `<branch-pai>`", sem bloquear.
- Confronte com a issue: o "problema" pode ser comportamento pedido explicitamente no card ou nos comentários.
- Descarte nit de formatação e preferência de estilo que não muda comportamento nem leitura.

Achados sobreviventes ganham severidade: **crítico** (bug, falha de segurança, perda de dado, quebra de contrato, teste que não testa, critério de aceite não implementado), **importante** (edge-case não tratado, erro engolido, duplicidade real, performance ruim em caminho quente), **sugestão** (manutenibilidade, nomes, reuso).

## 7. Formato da resposta

```markdown
## Revisão — <branch> (<N> arquivos, base <branch-pai> — detectada via PR/heurística)

**Issue <KEY>**: <título> — <uma linha sobre o que o card pede>

### Escopo vs. critérios de aceite
- <critério> — coberto em `arquivo:linha`
- <critério> — **não encontrado no diff**
- Fora do escopo do card: <mudança> em `arquivo:linha`

### Testes red/green
- <NomeDoTeste> — green OK / red OK
- <NomeDoTeste> — green OK / **red FALHOU: passa mesmo com o código quebrado**
- Suíte completa: <resultado> · Build: <resultado>
- (sem teste novo/alterado no diff: "Nenhum teste novo — só a suíte completa rodou" e a linha de Suíte/Build acima)

### Críticos (N)
1. `arquivo.cs:42` — <problema em uma frase>
   - Cenário: <entrada/estado → resultado errado>
   - Fix: <mudança concreta, com snippet se ajudar>

### Importantes (N)
### Sugestões (N)

### Pontos de review anterior
- <ponto> — resolvido em `arquivo:linha` / **não resolvido**

### Descartados
- <achado do agente X> — por que não procede

### Veredito
Pronto para merge / Corrigir antes do merge (itens 1, 3)
```

Omita as seções que não se aplicam (sem PR aberto, sem review anterior). Sempre inclua **Descartados** quando algum agente reportar algo que não sobreviveu — mostra o que foi checado. Se nada crítico apareceu, diga direto, sem inventar problema para preencher lista.

Não aplique correções nesta skill, exceto se o dev pedir. A entrega é o diagnóstico com o fix proposto.
