# Global programming rules

These rules apply to every coding agent working with me (Claude, Codex, Cursor Agent, and any other). Apply **Collaboration**, **Environment and tooling** and **Code** to all work. Apply **Enterprise** and **Personal** only when the project clearly fits that category — if unsure, ask. Rules marked **HARD GATE** have no exceptions beyond the ones they list and are never skipped on judgment. Breaking one is a failed task, even when the result works.

**HARD GATE — Don't be pedantic.** Judge things by common sense and practical use, not by technicalities. Don't reject or correct a choice because of a narrow distinction that changes nothing in practice.

## Collaboration with Claude, Codex and Cursor Agent

- **Tone: direct, plain, no fluff.** Answer and stop: no preamble, padding, or restating what I asked. Don't be pedantic: no lectures or over-qualified hedging. Don't be condescending: no over-explaining the obvious, talk to me as a peer.
- **HARD GATE — Never bury a question or decision.** Anything you need me to answer or decide must be impossible to miss. Give each one its own `>` callout at the end of the message, or use the question tool (AskUserQuestion) when available. One question per callout, phrased explicitly so I can answer without rereading the rest. Number every question (1, 2, 3), even when there is only one, so I can reference them by number in my reply. Never put a question inside a paragraph, a list of findings, or a long report. I skim long text and will ignore anything buried in it. If a message has both a report and a question, keep the report short and put the question last, set apart.
- **HARD GATE — Discuss until I say go. Don't rush to edit.** When we're discussing something, stay in discussion — propose, weigh options, refine wording — and do not start editing files or writing code until I explicitly say we're ready. A question or a design conversation is not a signal to start implementing. Applies to all file edits, not just code.
- **Criticism means fix, not revert.** When I criticize your work, don't give up and revert everything. Evaluate the criticism, then fix and improve what you built. Revert only when the work is fundamentally broken beyond repair or when I explicitly ask for a revert.
- **HARD GATE — Never write memories.** Don't save anything to the auto-memory system, of any type. When something should persist across sessions, ask whether to add it to the project's `CLAUDE.md` or to this global `CLAUDE.md`, and edit the chosen file.
- **Never offer to measure. Only measure when I ask.** Don't propose benchmarks, timings, profiling runs, or "let me measure this to confirm" — not as a suggestion, not as a next step, not as a closing line. If I want a measurement I'll ask for one explicitly; until then, do what I asked and stop. Stating a known performance fact is fine; volunteering to go measure it is not.
- **In a `/loop`, never declare "nothing left to do".** A loop means I want you working on that subject indefinitely. When the initially defined scope is done, that's not the end — move on to related improvements (adjacent bugs, rough edges, missing coverage, follow-ups the work surfaced) and start attacking them. Reporting that there's nothing more to do is slacking; if there were truly nothing left, I wouldn't have started a loop.
- **HARD GATE — Never start a subagent without my explicit authorization.**
- **Web searches go through a subagent, only with my authorization.** Web searches fill my quota fast, so don't run them yourself: ask my permission to hand them to a Sonnet or Haiku subagent and use its summary. One subagent per batch of related queries, not per query.
- **HARD GATE — Subagents never spawn subagents.** If you are a subagent, do the work yourself; don't spawn another subagent. When you spawn a subagent, say in its prompt that it is a subagent and must not spawn subagents.

## Environment and tooling

- **HARD GATE — LF line endings, always.** Every file you create or change uses LF, never CRLF. On Windows, text-mode writes produce CRLF:
  - Python, the most common source: `newline="\n"` on every `Path.write_text` and write-mode `open`, or a read-replace-write script turns an LF file into CRLF; `lineterminator="\n"` on `csv.writer` and `DataFrame.to_csv`.
  - Shell redirects (`python ... > f`, `uv run ... > f`, `pwsh -c ... > f`): write the file from the script, or pipe through `tr -d '\r'`.
  - PowerShell `>`, `>>`, `Out-File`, `Set-Content`, `Add-Content`: use the write/edit tool, or `[IO.File]::WriteAllText` with `` `n ``.
  - Claude Code's `check-crlf` hook blocks these writes; other agents must follow this rule themselves.
- **HARD GATE — No scraping of services tied to my accounts.** Don't scrape or bulk-crawl stores and communities (Steam and similar) where my IP or account could be flagged. Official APIs within their rate limits are fine. Stop at the first sign of throttling (429, captcha) and ask; never retry around it.
- **HARD GATE — Task runner: `just`, no other runner** (no `make`, npm scripts, or shell scripts as the runner). In a project with a justfile, use its recipes instead of raw `uv`/`gradle`/`mvn`/`npm`; raw commands only for what it doesn't cover. Add or change recipes only when I ask or when a convention already established in the project calls for it; never add one for your own work (a check, a debug run, a one-off script). Justfile shape:
  - Windows: `windows-shell := ["pwsh.exe", "-NoLogo", "-NoProfile", "-Command"]`.
  - First recipe is `default`, which only runs `@just --list --unsorted`; plain `just` never runs a task.
  - Every recipe has `[doc("...")]` (short, no articles or filler) and `[group("...")]`; no `#` doc comments.
  - Groups in order: `project` (setup, lint), `run` (build, run), `llm` (local LLM servers the app calls), `test`, `data` (refresh), `debug`. Subgroups `<group>/<subgroup>` (e.g. `project/report`) follow their parent. Within a group, same-subject recipes sit together; subjects and recipes ordered by importance.
  - Frequent recipes get an `alias` right after them: a different name, not a variant (no `tests` for `test`), never one letter.
- **Local-first runnability** (enterprise projects, and personal projects past a single-file script). A project boots from a fresh clone in a few commands. The `justfile` is the source of truth for how to run things; read it first. Every project has:
  - A **setup task** (`just setup`): one idempotent command that installs dependencies, starts local infrastructure via Docker, fetches credentials, and writes `.env` files.
  - A **run task** (`just run`): starts the application in local dev mode against that infrastructure.

  No copy-paste shell blocks in the README: every required step is a `just` recipe.
- **HARD GATE — Python projects: uv, never pip.** The justfile exports `UV_PROJECT_ENVIRONMENT := data_local_directory() / "_dev" / "uv" / "envs" / "<project>"` so the venv lives outside the project.
- **Conventional Commits** in every repo.

## Code (applies to everything)

### Shape

- **The shape of the code is everything.** How code is arranged carries its meaning: a reader understands the flow from the structure before reading any single line. When two versions do the same thing, the one with the clearer shape wins; HARD GATE rules are not open to this trade.
  - **A function is a sequence of phases** (e.g. load → validate → compute → save), in the order they run, each separated by a blank line, optionally with a phase separator.
  - **A file goes from high level to detail**: entry point first, then what it calls (see *Member ordering*).
  - **Related code sits together; unrelated code stays apart** (see *Co-locate*).
  - **Too many phases to read means missing modeling**: move behavior to a domain object or module function (see the helper gate's order), never to a private helper.

  Before delivering, check each function you wrote or changed: you must be able to name its phases from its blocks alone. If you can't, reshape it.
- **Member ordering: consistent, by role.** Members are grouped by role, never in random order, and classes of the same kind use the same order. Static members and factories come first, then high-level entry points, then mutations, then queries, with private helpers below the code that calls them. Constructor dependencies keep the same name and position across classes. When the language or the project already has an order, follow it.
- **Early returns / guard clauses over deep nesting.** Handle edge cases at the top with early `return`/`continue`/`throw` so the main path stays at one indentation level; no nested `if`/`else` chains.
- **HARD GATE — Never extract a private helper without a listed exception.** Wanting a private helper is a sign the domain model or the module structure is missing something. Give the code a home, in this order:
  1. **A method on a domain object** (entity or value object) that owns the data.
  2. **A public function in the module** whose responsibility it fits, when no class or domain object applies.
  3. **Inline**, when neither exists.

  The home must be a real domain concept or module responsibility, never a class or module created to hold the helper. A private helper is allowed only when you can name which of these exceptions justifies it:
  - **Reuse** — it is called from **two or more** call sites (one caller is not reuse).
  - **Multiple implementations** — the same task has provider/strategy variants behind a common shape.
  - **Recursion** — the function genuinely needs to call itself.

  No other reason counts. Never extract to improve readability, name a step, shorten a function, separate concerns, make code testable, or make each function do one thing; when you reach for one of these, go back to the order above.
- **Co-locate things that are read together.** Input/output types, file-scoped constants, small helper classes: if you only read them alongside their owner (a use case, a payload, an entity), they live in its file. Don't fragment for the sake of "one class per file."
- **Import order: stdlib → third-party → project**, with one blank line between groups, in any language with an import/use/include section.
- **Named arguments at the call site when the language supports them.** Pass by name when a call takes several parameters or relies on defaults: `createOrder(customer = customer, priority = Priority.High)`. Positional is fine for one or two obvious arguments (`Money.of(amount, currency)`). The reader should see what each value *means* without opening the declaration.

### Types and domain modeling

- **DDD is the design reference.** For design questions no rule here answers, reason the way Eric Evans would: model the domain, use its language, put behavior on the objects that own the data, draw aggregate boundaries. *Clean Code* (Robert C. Martin) is not a reference: never cite its principles to justify a change, and never apply its recipes (tiny functions, one thing at every granularity).
- **Type safety, with compile-time invariants.** Type every function signature and data structure, in dynamically-typed languages too; no untyped containers, and mark a genuinely unknown type explicitly. Express constraints in the type system so invalid states don't compile, instead of runtime checks and tests; runtime validation is the fallback for what types can't express (external input, dynamic data, true runtime conditions).
- **Pragmatism, but type safety counts.** Don't overengineer — abstractions, layers, and patterns must earn their keep. But constructs that *look* like ceremony (newtypes, value classes around primitives, sum types instead of boolean flags) often earn it by making invalid states unrepresentable. Judge by whether the type system gets stronger, not by surface line count.
- **Prefer libraries over hand-rolled plumbing.** For anything outside the application's core (date parsing, HTTP, retries, validation, etc.), use a maintained library. Hand-rolled code is for the actual business logic.
- **Business rules live on entities/values, not services** (*tell, don't ask*). Behavior belongs on the object that owns the data, not in a service that reads its state and decides externally. Use a service only when logic genuinely spans multiple aggregates or needs external collaborators.
- **Immutable by default; contained mutation inside domain objects.** Produce new values rather than mutate in place. Entities mutate only through named behavior methods (`order.markAsShipped()`), never raw setters.
- **Construct objects via factories / named-parameter constructors; validation lives on the domain types.** Use factory methods (`User.register(...)`, `Order.fromCart(...)`) or named-parameter constructors that require every mandatory field. Never pass `null`/`None` to skip a field; add a factory for that case. Factories enforce invariants so an invalid instance can't exist; the domain types reject bad input themselves; never rely on DTO validation.
- **No interfaces unless the scenario demands one.** An interface (or abstract base class) with a single implementation is noise; use the concrete class. With multiple implementations, consider whether a sum type with pattern matching / `switch` on a discriminator is clearer than dynamic dispatch. Use an interface only for a genuine seam: external boundary, true plugin point, or a test double that can't be replaced more simply.
- **No boolean mode switches — use an enum.** When code picks a behavior by passing `true`/`false` to a function (`send(invoice, true)`), use an enum (`send(invoice, Delivery.Email)`).
  Booleans that are **data** are fine and never get flagged: query params, path/header values, payload/DTO/record/entity fields, constructor arguments that set a field, config values, columns. Don't suggest enums for any of these.
  The test: is this boolean a value the system receives or stores (fine), or a switch a programmer hardcodes to pick a code path (enum)?
- **Sync by default, async only when it pays.** Use async/non-blocking code only for I/O-bound paths that genuinely benefit (concurrent fan-out, high-throughput services), never by reflex. Synchronous code is easier to reason about, debug, and test.

### Naming

- **Domain language in names.** Business vocabulary, not technical jargon: `Order.cancel()` not `OrderManager.processStatusUpdate()`. Avoid generic suffixes (`*Manager`, `*Helper`, `*Util`, `*Processor`). Class and method names read like the domain expert would phrase them.
- **Domain verbs over operators and conditional chains.** Prefer named helpers that read like sentences: `toggle.disabled()` over `!toggle.isEnabled`, `order.canBeCancelled()` over a multi-clause boolean expression at the call site.
- **No abbreviations, except cross-domain common ones.** `user` not `usr`. Allowed: abbreviations any programmer knows regardless of the app (`id`, `db`, `url`, `api`, loop `i`). **Never** abbreviate domain terms: `invoice` not `inv`. The test: would a programmer new to this codebase know the short form?
- **One concept, one word.** One term per domain concept, used everywhere: if it's `customer`, never `client` or `user` for the same thing. Synonym drift breaks grep and forces readers to learn the mapping. When an external system uses a different term, translate at the boundary.
- **Methods start with a verb; one verb per concept.** You don't get to be a thesaurus: pick one verb per concept and reuse it everywhere. Fixed verbs:
  - `get*`: must exist; throws if missing.
  - `find*`: value or absence; never throws on "not found".
  - `parse*`: external input → typed value (`parseInvoiceTotal(text)` → `Money`); pure, fails on invalid input.
  - `to*` / `from*`: conversions, on one of the two types (`user.toDto()`, `UserDto.fromEntity(user)`); never `asDto`, `convertToDto`.
  - `create*`: new entity from raw input; prefer a domain verb where one fits (`User.register`, `Order.fromCart`).
  - `ensure*`: fails if a condition doesn't hold; never creates or changes anything.
  - `getOrCreate*`: returns the existing thing, or creates and returns it.
- **Naming order: subject first, state second.** `userActive`, not `activeUser`; `ordersPending`, not `pendingOrders`.

### Errors

- **Read operations return absence, never throw.** Lookups must not throw when nothing is found: return `null`/`Option`/`Optional` for single items, an empty collection for queries. Exceptions are for genuine errors (I/O failure, programming bugs), not for "the row didn't exist."
- **Always propagate errors; log location depends on language.** Never swallow an error silently to return a default — propagate it.
  - **Rust / Go** — errors don't carry a real stack trace, so the original call site has the most context. Log there with the relevant fields *before* returning or wrapping the error, then propagate.
  - **Java / Kotlin / Python / JS / C#** — the exception carries the full stack trace, so the top-level handler logs it once. Don't log-and-rethrow at every layer.

### Writing

- **HARD GATE — No comments unless I ask for one.** The default is none: no explanatory comments, section headers, docstrings, or `# why` notes in code you write or change. The only exception is **phase separators**: a comment above a block that names the phase, **at most 4 words**, lowercase, with no punctuation (`// load data`, `// checks`, `// execute`). Never longer, and never explaining why or how. Don't strip comments a human wrote. When I explicitly ask for one, write only what's necessary.
- **Write plain in code, comments, and docs.** Everything you write into files (code, identifiers, comments, commit messages, documentation) is plain, direct, and objective. No figures of speech or literary phrasing. Use one word for one thing and keep using it; don't rotate synonyms for variety. In conversation with me you can talk however you like.

### Tests

- **Tests should be short.** Arrange-act-assert in a handful of lines; push repetitive setup into helper functions/fixtures so the test body shows intent, not plumbing. If a test needs heavy setup even with helpers, the code under test is probably reaching for the wrong abstraction (too many collaborators, leaky boundaries, missing aggregate). Fix the design, don't grow the test.

## Enterprise / company applications

- **Follow existing conventions first.** In an established codebase it's often impractical to apply every best practice — surrounding code, frameworks, and team agreements constrain what's reasonable. Match the conventions already in the file/module/project before reaching for the rules below. The rest of this section describes preferences for *new* code or greenfield areas; don't refactor existing code to match them unless asked.
- **No primitive obsession.** Wrap domain concepts in newtypes / value classes (`UserId`, `Money`) instead of raw `string`, `int`, so the type carries meaning and invariants are enforced at construction.
- **Mapping external payloads:**
  1. **Map only the fields you actually use.** Don't mirror the upstream schema "for completeness"; unused fields are dead weight that breaks when the upstream changes shape.
  2. **Enums as strings, not native enums.** External vocabularies gain and lose values, and a closed enum breaks at runtime when they do. Keep the string; convert only where your code branches on it, and handle unknown values explicitly.
  3. **Nested structs as inner classes** of the top-level payload type, in the same file, not one file per DTO.
- **Serialization defaults.**
  1. **Newtypes serialize as their inner value.** `UserId(42)` goes over the wire as `42`, not `{"value": 42}`. Configure the serializer (Jackson `@JsonValue`, serde `#[serde(transparent)]`, Pydantic `RootModel`).
  2. **Dates and times use ISO 8601.** Instants carry an offset. Calendar dates with no clock-time meaning (e.g. date of birth) are date-only, modeled as `LocalDate` or the language equivalent, never a datetime. Flag any calendar-date field I model as a datetime.
- **External writes: persist-pending → call → update.** When dispatching work to an external system:
  1. **Write a local record in a `pending` state** with a correlation reference (the external ID if known up-front, or a locally-generated idempotency key you send with the request).
  2. **Make the external call.**
  3. **Update the local record** to its final state (succeeded / failed / whatever the domain calls for) based on the response.

  A recovery job can then reconcile `pending` rows against the external system using the stored reference. Never call the external system *before* persisting: if the process dies after the call, nothing records it.
- **DTOs at the border, not between layers.** DTOs / payload types describe the *wire shape* and exist only at transport boundaries (controllers, listeners, clients). Internally (use case → domain → integration), pass entities, value objects, and newtypes directly; no parallel flat/primitive DTOs between layers. **Use cases may still have dedicated input/output types** (`CreateOrderInput`, `CreateOrderOutput`): these aren't DTOs, because their fields *are* entities, value objects, and newtypes. A DTO holds primitives shaped for the wire; a use case I/O type holds domain objects shaped for the use case's contract.
- **No mapper services.** Conversion belongs on one of the two types involved (`UserDto.fromEntity(user)` or `user.toDto()`), not in a separate `XMapper`/`XConverter` service. The type that *may depend on* the other owns the conversion.
- **Module layout: layered, with the domain at the core.** Greenfield projects only; if an existing project uses a different layout, follow it and don't restructure.
  - `app/rest`, `app/<protocol>`, `app/listeners` — transport adapters.
  - `domain/entities`, `domain/services`, `domain/usecases` — business model and orchestration.
  - `integration/` — repositories and outbound clients.
  - `shared/` — cross-cutting concerns: logging, metrics, security, cloud SDK wrappers.

  Domain code calls `integration/` directly — no ports/adapters indirection.
- **Extract magic numbers/strings to named constants** so the *intent* shows at the call site, not just the value.
- **Structured logging throughout, with discipline.** Log across layers where there's real signal, always structured (key/value pairs, not interpolated strings) and always with context (correlation/trace IDs, user/tenant where relevant). `info` is for what an operator would want to see; debug noise stays at `debug`. No `System.out.println`-style logs.
- **WireMock-in-Docker is acceptable for external dependencies.** Tests don't need to hit real third-party services. A [WireMock](https://wiremock.org/) container (or equivalent HTTP stub) gives realistic HTTP behavior without the flakiness, cost, or rate limits of the real service. Prefer it over in-process HTTP-client mocks when the integration shape matters.
- **Use cases orchestrate, not controllers/listeners/services.** Each application action has a dedicated *use case* (interactor / application service) that orchestrates the business rules end-to-end. Controllers, listeners, and CLI entry points stay thin: parse input, invoke the use case, format output. Don't chain services-calling-services to compose a workflow, and don't push orchestration into transport-layer code.
- **The use case entry point has a legible shape.** The main execution method (`execute`, `handle`) reads as a sequence of phases — typically *load inputs → validate → compute → execute → persist* — visually separated (blank lines or phase separators). Consistent shape across use case entry points beats clever flow inside any one of them. Applies only to the entry point, not to private helpers on the same class.

## Personal scripts

- **No tests required.** Personal scripts don't need unit, integration, or e2e tests. Don't add a test suite, test files, or test scaffolding unless I explicitly ask. Manual verification is fine.
- **Magic numbers/strings are usually fine inline.** Don't extract constants just to give a literal a name in a one-off script. Extract only when the value is genuinely reused or its meaning is unclear in context.
- **Parallelism: cap NAS I/O at 8 workers, CPU work can go wide.** Machine: i9, 32 threads. NAS: Synology 1522+, HDDs. CPU-bound work can use many threads. Any task that reads/writes the NAS in parallel must cap concurrency at **8 workers** — HDDs thrash under heavy parallel I/O, so going wider *lowers* throughput instead of raising it.
- **GPU: RTX 5080, 16 GB VRAM.** Scripts that run local models (llama.cpp and similar) must choose model size, quantization and context length to fit in 16 GB VRAM.
