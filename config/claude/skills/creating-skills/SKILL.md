---
name: creating-skills
description: Creates and refines Claude Code skills with proper structure, frontmatter, and best practices. Use when the user wants to create a new skill, improve an existing skill, or needs guidance on skill authoring.
---

# Creating Skills

## Skill structure

Every skill requires a `SKILL.md` file with YAML frontmatter:

```yaml
---
name: skill-name
description: What the skill does and when to use it
---

# Skill Name

[Instructions for Claude to follow]
```

## Frontmatter requirements

**name** (required):
- Max 64 characters
- Lowercase letters, numbers, hyphens only
- Use gerund form: `processing-pdfs`, `analyzing-data`, `managing-databases`

**description** (required):
- Max 1024 characters
- Write in third person
- Include BOTH what it does AND when to use it
- Be specific with key terms for discovery

## Core principles

1. **Be concise** - Only add context Claude doesn't already have
2. **Set appropriate freedom** - Match specificity to task fragility
3. **Use progressive disclosure** - Keep SKILL.md under 500 lines, split complex content into separate files

## Workflow for creating a skill

```
Skill Creation Progress:
- [ ] Step 1: Identify the reusable pattern
- [ ] Step 2: Write frontmatter (name + description)
- [ ] Step 3: Write core instructions
- [ ] Step 4: Add examples if helpful
- [ ] Step 5: Split large content into reference files
- [ ] Step 6: Test with real tasks
```

**Step 1: Identify the reusable pattern**

What context do you repeatedly provide? What domain knowledge, workflows, or preferences should Claude know?

**Step 2: Write frontmatter**

```yaml
---
name: your-skill-name
description: [What it does]. [When to use it].
---
```

**Step 3: Write core instructions**

Focus on what Claude needs to know that it doesn't already. Avoid explaining basics.

**Step 4: Add examples if helpful**

Provide input/output pairs for output-sensitive tasks:

````markdown
**Example:**
Input: [user request]
Output: [expected Claude behavior]
````

**Step 5: Split large content**

If approaching 500 lines, move details to separate files:

```
my-skill/
├── SKILL.md (overview, ~300 lines)
├── REFERENCE.md (detailed docs)
└── EXAMPLES.md (extended examples)
```

Reference them: `See [REFERENCE.md](REFERENCE.md) for details`

**Step 6: Test with real tasks**

Use the skill on actual work. Observe and iterate.

## Description template

```
[Verb phrase describing capability]. [Additional capabilities]. Use when [trigger conditions] or when the user [user intent signals].
```

**Examples:**

```yaml
# Good - specific and actionable
description: Generates git commit messages by analyzing staged changes. Use when the user asks for help with commit messages or wants to review changes before committing.

# Good - clear triggers
description: Processes CSV files into structured reports with charts. Use when working with CSV data, spreadsheets, or when the user mentions data analysis or reporting.

# Bad - too vague
description: Helps with files.
```

## Anti-patterns to avoid

- **Over-explaining**: Don't explain what PDFs are or how libraries work
- **Time-sensitive info**: Use "old patterns" sections for deprecated approaches
- **Inconsistent terms**: Pick one term (e.g., "field" not "field/box/element")
- **Deep nesting**: Keep file references one level deep from SKILL.md
- **Windows paths**: Always use forward slashes (`scripts/helper.py`)

## Degree of freedom guide

**High freedom** (general guidance):
```markdown
Review the code for potential issues and suggest improvements.
```

**Medium freedom** (template with parameters):
```markdown
Use this structure, customize as needed:
[template]
```

**Low freedom** (exact instructions):
```markdown
Run exactly: `python scripts/validate.py --strict`
Do not modify flags.
```

Match to task fragility - fragile operations need low freedom.
