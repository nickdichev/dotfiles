---
description: Create and apply a database migration
argument-hint: <target branch, default(origin/main)>
allowed-tools: Bash(gh:*), Bash(git:*), Edit, Write, Read
---

Your task is to fetch the origin git remote and rebase the branch we are currently on top of $0 or `origin/main` if an argument was not provided.

If any rebase conflicts arise, use your best judgement based on the conflict and the changes present on the target branch and the git history of the source branch. If anything is unclear or you don't think you can make a reasonable conflict resolution: prompt the user with what the conflict is and some details of the changes on the source branch which are incompatible with the target branch. 
