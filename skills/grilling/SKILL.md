---
name: grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
---

Responda sempre em português. Todas as perguntas, títulos, opções e recomendações desta entrevista devem ser escritos em português, independentemente do idioma usado pelo usuário.

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

## How to ask

Never write a question as chat text. Ask every question with the structured question tool (`AskUserQuestion` in Claude Code), so the user answers by selecting options:

- **One question per call.** Wait for the answer before the next call: each answer can reshape the tree.
- **2-4 options**, each with a short `label` and a `description` that states its trade-off. Do not add an "Outro"/"Other" option: the tool adds one, where the user can type a free answer.
- **Recommended answer first**, with ` (Recomendado)` at the end of its label.
- **`multiSelect: true`** when the choices are not mutually exclusive (for example "quais destes casos precisam ser suportados?"). Mark every recommended option with ` (Recomendado)`.
- **`header`**: a chip of at most 12 characters naming the topic.
- **`preview`** when the options are concrete artifacts to compare: code snippets, API shapes, ASCII layouts.
- **Context goes inside the call**: what you found in the codebase and why the decision matters belong in the question text and option descriptions, not in a chat message before the call.
- **Open answers** (a name, a number, a deadline): still use the tool. Offer your best 2-4 candidates; the user types their own through "Outro".

When an answer comes back through "Outro" or with notes, read it carefully: it often opens a new branch of the tree.

Fall back to asking in chat only if this environment has no structured question tool. Then keep the same shape: one question, numbered options, recommended one marked.

## Ending

The session is done when every branch of the design tree has been visited and nothing is left silently assumed. Summarize the decisions in chat, then ask one last question through the tool to confirm the shared understanding. Do not act on the plan until the user confirms.
