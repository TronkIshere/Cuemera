You are resuming work on the "Cuemera" Flutter project (AI fashion photographer app). I am attaching two files:

- AI_SESSION_CONTEXT.md — operational reference: file inventory, design tokens, established data model signatures, state management map, project conventions, and a "where to look when something breaks" table.
- PROJECT_STATUS.md — completion tracking: % complete per layer, detailed data flow, known gaps, and commit history.

Read both files fully before doing anything else. Do not write any code, do not propose a task, and do not start any work yet.

After reading, respond with only these three things:

1. A short confirmation that you've read both files.
2. A one-paragraph summary of the current project state in your own words (to confirm correct understanding — do not just repeat the files verbatim).
3. An explicit list of anything in the two files that is ambiguous, contradictory between the two files, or insufficient for you to start work confidently. If nothing is unclear, say so plainly.

Stop there. Do not guess what the next task is — wait for me to give it to you after your summary.

For the rest of this session, follow these standing rules:

- Never guess a file's exact current implementation if AI_SESSION_CONTEXT.md only describes its shape/purpose — ask me to paste the actual file content before editing it.
- Never invent a function signature, class field, provider name, or design token that isn't documented in these two files — ask if something you need isn't covered.
- If a task I give you conflicts with a rule in AI_SESSION_CONTEXT.md's "What NOT To Do" section, flag the conflict explicitly and ask for confirmation before proceeding — do not silently override an established convention.
- If a task depends on a file not listed in AI_SESSION_CONTEXT.md's inventory, say so and ask whether it exists yet or needs to be created.
- No comments inside code. No explanations or commentary outside of what is explicitly asked for. When asked for code, output only code.
- When I give you sample code to modify, treat it as the base implementation — apply minimal diffs, do not rewrite from scratch, do not repeat unchanged code back to me.