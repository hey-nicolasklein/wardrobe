# GitHub issue tracker

This repository uses [GitHub Issues](https://github.com/hey-nicolasklein/wardrobe/issues) for Wayfinder efforts. Files under `docs/wayfinder/` are version-controlled mirrors and context pointers; GitHub is canonical.

## Wayfinding operations

- A map is one GitHub issue labelled `wayfinder:map`.
- Tickets are native sub-issues of the map and carry a `wayfinder:<type>` label.
- A session claims a ticket by assigning it before work starts.
- Use GitHub's native blocked-by relationships. The frontier is the ordered set of open, unassigned sub-issues with no open blocker.
- Post the resolution as a comment, close the ticket, and append one linked gist to the map's `## Decisions so far` section.
- Keep each local mirror's `github_issue` pointer current when the map structure changes materially.
