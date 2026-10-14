---
name: revisar-branch
description: Revisão profunda da branch atual (ou do PR aberto dela) contra develop/main, usando a issue do Jira do nome da branch como contexto de escopo. Dispara múltiplos agentes em paralelo — bugs, exceções, edge-cases, duplicidade, segurança, performance, manutenibilidade —, verifica red/green de cada teste novo ou alterado, valida criticamente cada achado e propõe um fix por achado. Use quando pedirem "revise essa branch", "revise meu PR", "review antes de abrir PR", ou antes de /finish-issue.
---

# Revisão de branch / PR

Objetivo: entregar uma lista curta de problemas **reais**, cada um com localização exata (`arquivo:linha`), severidade e um fix concreto. Falsos positivos custam mais que achados perdidos — todo achado passa por validação antes de aparecer na resposta.

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

1. Base: `git merge-base HEAD origin/develop` (ou `main` se o repo usar main).
2. Diff completo: `git diff <base>...HEAD` e `git diff --stat <base>...HEAD`.
3. Inclua mudanças não commitadas (`git status`, `git diff`) — fazem parte do PR que vai sair.
4. Histórico: `git log --oneline <base>..HEAD` — commits `WIP`, revert seguido de reaplicação e "fix review points" indicam pontos frágeis; olhe esses arquivos com mais atenção.
5. PR aberto: `gh pr view` e `gh pr view --comments`. Se houver review anterior, **verifique um por um se os pontos apontados foram realmente resolvidos** — não assuma pelo commit message.
6. Leia o `CLAUDE.md` da raiz e os aninhados nas pastas tocadas; as regras deles são critério de revisão.
7. Liste os arquivos por camada (backend, frontend, migrations, testes, configs) — isso define quais agentes valem a pena.

Não revise código fora do diff, exceto para entender o contexto de uma linha alterada (chamadores, contrato, invariantes).

## 3. Agentes em paralelo

Dispare os agentes aplicáveis **numa única mensagem** para rodarem concorrentes. Cada um recebe: resumo da issue do Jira, lista de arquivos alterados, o comando de diff que deve rodar e a instrução de retornar achados como `arquivo:linha — severidade — problema — fix sugerido`, sem elogios e sem sugestões fora do diff.

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

## 4. Verificação red/green dos testes

Para **cada** teste novo ou alterado no diff, um por vez (não em lote):

1. **Green**: rode o teste isolado (filtro pelo nome, não a suíte toda) e confirme que passa.
2. **Red**: quebre deliberadamente o código de produção que o teste deveria proteger — inverta a condição, remova a validação, retorne o valor errado — e confirme que **esse** teste falha, na asserção certa.
3. **Restaure** o código imediatamente e rode o teste de novo para confirmar green.

Antes de começar: garanta que a árvore está limpa ou que as mudanças estão salvas, para que a restauração seja verificável (`git diff` volta ao estado inicial ao final). Nunca deixe a etapa red aplicada; se qualquer restauração falhar, pare e avise em vez de continuar.

Registre por teste: passou green? falhou red? A falha red apontou a asserção esperada? Teste que passa green mas **não** falha no red é achado de severidade alta — não testa nada.

Depois dos testes individuais, rode a suíte completa e o build uma vez para pegar quebra colateral. Se não houver como rodar no ambiente, diga isso explicitamente em vez de assumir que passam.

Cobertura vs. Jira: cada critério de aceite e cada passo de reprodução do bug deveria ter um teste. Aponte os que não têm.

## 5. Higiene do diff

Checagem mecânica rápida, direto no diff:

- `console.log`, `debugger`, `Debug.WriteLine`, print de depuração, código comentado, `TODO`/`FIXME` novo sem issue.
- Segredo, token, senha, connection string ou URL de ambiente em código ou config commitada.
- Arquivo gerado/binário/lock desnecessário, arquivo de IDE, arquivo temporário, pasta de build.
- Arquivo tocado sem relação com a issue (rename automático do editor, reformatação de arquivo inteiro escondendo a mudança real).
- Mudança de formatação misturada com mudança de lógica no mesmo arquivo, dificultando a revisão.

## 6. Validação crítica antes de responder

Junte todos os achados (seus + dos agentes), deduplique por `arquivo:linha` e avalie **cada um separadamente**:

- Leia o código real ao redor — não confie no resumo do agente.
- Descreva o cenário concreto de falha: entrada/estado → resultado errado. Se você não conseguir escrever esse cenário, o achado não sobrevive.
- Verifique se algo antes no fluxo já impede o cenário (validação no controller, `[Required]`, guard, tipo não-nulo, constraint no banco).
- Verifique se é pré-existente ao diff. Se é, marque como pré-existente e rebaixe a prioridade — não é bloqueio deste PR.
- Confronte com a issue: o "problema" pode ser comportamento pedido explicitamente no card ou nos comentários.
- Descarte nit de formatação e preferência de estilo que não muda comportamento nem leitura.

Achados sobreviventes ganham severidade: **crítico** (bug, falha de segurança, perda de dado, quebra de contrato, teste que não testa, critério de aceite não implementado), **importante** (edge-case não tratado, erro engolido, duplicidade real, performance ruim em caminho quente), **sugestão** (manutenibilidade, nomes, reuso).

## 7. Formato da resposta

```markdown
## Revisão — <branch> (<N> arquivos, base <base>)

**Issue <KEY>**: <título> — <uma linha sobre o que o card pede>

### Escopo vs. critérios de aceite
- <critério> — coberto em `arquivo:linha`
- <critério> — **não encontrado no diff**
- Fora do escopo do card: <mudança> em `arquivo:linha`

### Testes red/green
- <NomeDoTeste> — green OK / red OK
- <NomeDoTeste> — green OK / **red FALHOU: passa mesmo com o código quebrado**
- Suíte completa: <resultado> · Build: <resultado>

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
