# Recipe template

A recipe describes a repeatable change once, so briefs can say "follow recipe `<path>` for `<target>`" instead of re-explaining it. Keep recipes in the repo they apply to, as `<repo>/ai/recipes/<name>.md`, or next to the plan. The orchestrator looks in both places.

~~~markdown
# Recipe: <name>

<one paragraph: what this change is and when to use it>

## Inputs
- `<target>`: <what the brief names, e.g. the resource or page being ported>

## Files to touch
- `<path pattern with <target>>`: <what changes there>
- Reference implementation: `<path to a finished example>`

## Steps
1. <step>
2. <step>

## Validation
```bash
<commands that must pass, in order>
```

## Done when
- <checkable criterion>
- <checkable criterion>

## PR
Title: `<template, e.g. "Port <target> to Ash">`
Body:
- What changed: <…>
- How it was validated: <commands above>
- Follow-ups: <none | …>

## Pitfalls
- <known trap and how to avoid it>
~~~

Recipes suit work that follows an established pattern, which is the `sonnet` tier's job. If a recipe needs judgement at every step, it's a plan, not a recipe.
