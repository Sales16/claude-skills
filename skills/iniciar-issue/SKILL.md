---
name: iniciar-issue
description: Inicia o trabalho numa issue do Jira — lê a issue da branch atual (ou da chave passada como argumento), analisa o código com agentes, tira todas as dúvidas com o grilling, monta o plano de desenvolvimento e só implementa depois da aprovação do dev, sugerindo orchestrated-work quando o escopo é grande. Use quando pedirem /iniciar-issue, "inicia a issue", "começa essa issue", "planeja essa issue" ou "lê a issue e monta o plano".
argument-hint: "[ISSUE-KEY]"
---

# Iniciar issue

Objetivo: sair da issue do Jira para um plano aprovado pelo dev, sem deixar dúvida assumida em silêncio. **Nenhum arquivo é editado antes da aprovação do plano.**

**Responda sempre em português (pt-BR).** Termos técnicos, nomes de API, código e mensagens de erro ficam no original.

Fluxo: chave → Jira → análise do código → grilling → plano → aprovação → implementação.

## 1. Chave da issue

1. Se veio argumento (`/iniciar-issue EN-1234`), use-o como chave. Ele tem prioridade sobre a branch.
2. Sem argumento, extraia a chave de `git rev-parse --abbrev-ref HEAD` no padrão `{tipo}/{ISSUE-KEY}` (ex.: `feature/EN-5386` → `EN-5386`).
3. Sem argumento e sem chave reconhecível na branch, pergunte a chave pelo `AskUserQuestion`.

Anote se a branch atual é a base (`main`, `master`, `develop`). Isso só importa na seção 7.

## 2. Jira

Leia pelo MCP Atlassian (`getJiraIssue`, cloudId `lacuna.atlassian.net`):

1. **Issue**: título, tipo (bug/feature/refactor), status, descrição, critérios de aceite.
2. **Comentários**: costumam conter a regra de negócio real, exceções combinadas e mudanças de escopo que não estão na descrição.
3. **Subtasks e issues relacionadas**: mostram dependências e o que **não** é escopo desta issue.
4. **Epic pai**: contexto do objetivo maior.
5. **Páginas do Confluence linkadas** na issue ou nos comentários (`getConfluenceContent`): leia quando a issue apontar para uma spec.
6. Se for **bug**: extraia o passo-a-passo de reprodução. Ele vira roteiro de teste.

Se o MCP falhar ou a issue não existir, pare e avise. Não planeje sem a issue.

## 3. Análise do código

Delegue **sempre** a agentes. O main loop não lê o código em massa: guarda contexto para a implementação.

1. A partir da issue, liste as áreas prováveis (backend, frontend, migrations, testes, configs, integração com outro sistema).
2. Dispare agentes `Explore` **numa única mensagem**, com escopos disjuntos — um por área relevante. Issue pequena: um agente basta.
3. Escolha o modelo de cada agente pelo custo mínimo que dê conta:
   - `model: "haiku"` — localizar arquivos, mapear chamadores, achar padrões existentes, checagem grep-driven.
   - `model: "sonnet"` — entender fluxo entre camadas, regra de negócio espalhada, contrato com outro sistema.
   - Sem override (herda o main loop) — só quando a interpretação errada sai cara: lógica de domínio complexa, concorrência, segurança.
4. Cada agente recebe: resumo da issue, a pergunta concreta da sua área e a instrução de retornar `arquivo:linha` + o que existe hoje + o que precisaria mudar + dúvidas que o código não responde. Peça também testes existentes que cobrem a área e componentes/helpers reutilizáveis.
5. Leia o `CLAUDE.md` da raiz e os das pastas tocadas: as regras deles valem para o plano.

Se o resultado de um agente for vago ou contraditório, dispare outro mais focado. Não preencha a lacuna com suposição.

## 4. Grilling

Chame a skill `grilling` pelo Skill tool (com o prefixo do plugin quando instalada como plugin, ex.: `sales16-toolkit:grilling`).

Contexto para a entrevista: a issue, os comentários e os achados dos agentes. O alvo são as dúvidas que o Jira e o código não respondem: regra de negócio ambígua, edge-case não especificado, escolha de abordagem, contrato, migração de dados, escopo.

Ajustes ao fluxo do `grilling`:

- Pergunta que o código responde não vai para o dev: dispare um agente e responda sozinho.
- **Pule a confirmação final do grilling.** Ao visitar todos os ramos, vá direto para o plano: a aprovação do plano já cobre o entendimento.
- Se não sobrar dúvida real (issue trivial e bem especificada), diga isso em uma linha e vá direto para o plano, sem grilling.

## 5. Plano

Mostre o plano **no chat**, em markdown, com estas seções:

1. **Resumo**: o que a issue pede, em 2-4 linhas.
2. **Decisões**: o que ficou decidido no grilling, uma linha por decisão.
3. **Passos**: lista ordenada por camada, cada passo com os arquivos tocados (`arquivo` ou `arquivo:linha`) e o que muda. Marque reuso de código existente.
4. **Testes**: testes a criar ou alterar, e como cada critério de aceite (e cada passo de reprodução, se bug) fica coberto.
5. **Riscos e fora de escopo**: pontos de regressão, migração de dados, contrato quebrado, e o que deliberadamente não será feito.
6. **Execução recomendada**: `orchestrated-work` ou direto, com a razão em uma linha (seção 6).

## 6. Recomendação de execução

- **`orchestrated-work`**: o plano cruza vários arquivos ou camadas, envolve backend + frontend, é um bug não-trivial ou um refactor de subsistema.
- **Direto**: 1-2 arquivos, edição mecânica ou fix totalmente especificado.

Se a skill `orchestrated-work` não existir no ambiente (ex.: `workflow:orchestrated-work`), não a ofereça: recomende só o caminho direto.

## 7. Aprovação

Termine com uma pergunta em texto no chat (não precisa ser `AskUserQuestion`), oferecendo:

- **Aprovado com `orchestrated-work`** (só se a skill existir)
- **Aprovado, implementação direta**
- **Ajustes**: o dev descreve o que mudar

Marque qual é a recomendada. **Não edite nenhum arquivo antes da resposta.**

Ajustes: refaça o plano (e o grilling do ponto afetado, se a mudança abrir dúvida nova) e pergunte de novo.

Se a branch atual for a base (`main`/`master`/`develop`), antes de implementar pergunte se quer criar a branch da issue (sugira `/start-issue` se existir) ou seguir na base.

## 8. Implementação

- **`orchestrated-work`**: chame a skill passando o plano aprovado e as decisões como especificação. Ela conduz daí em diante.
- **Direto**: implemente o plano na ordem dos passos, incluindo os testes. Depois compile e rode os testes afetados e reporte o resultado real: passou, falhou (com a saída) ou não deu para rodar (dizendo por quê).

Não commite e não dê push. Commit e PR ficam com o dev (`/finish-issue` ou manual).

Se durante a implementação aparecer algo que contradiz o plano aprovado, pare e pergunte em vez de decidir sozinho.
