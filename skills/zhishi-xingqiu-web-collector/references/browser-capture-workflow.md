# Browser Capture Workflow

This reference describes the intended operating contract for the `zhishi-xingqiu-web-collector` skill.

## Inputs

- `target_dir`: required destination directory
- `file_stem`: optional output name stem
- `title_substring`: optional browser window hint, default `Google Chrome`
- `max_rounds`: optional cap on capture rounds
- `max_pages`: optional cap on pagination advances

## Capture Order

1. Activate the browser window.
2. Recover the current URL from the address bar.
3. Copy the current page text.
4. Save a visible screenshot for the round.
5. Parse directly exposed image URLs from the copied text and download them when possible.
6. Scroll further down the current page.
7. Repeat until content stalls.
8. Probe pagination.
9. Continue until both scrolling and pagination stop yielding new content.

## What Counts As New Content

Treat a round as new when one or more of these changes:

- copied text hash changes
- copied text length grows materially
- discovered image URL set grows
- page URL changes after pagination

## End Conditions

Finish when all of these hold:

- repeated rounds produce the same normalized text
- no new image URLs appear
- pagination probing does not move to a new page

## Image Strategy

Preferred order:

1. download image URLs exposed in copied text
2. keep visible-page screenshots for image-bearing pages

This means the Markdown remains useful even when the site is authenticated and the raw DOM is not safely accessible.

## Markdown Assembly Rules

- build one Markdown file per task
- create a sibling asset directory named from the Markdown stem
- use relative links for all images
- split text into de-duplicated content blocks
- keep longer versions of repeated blocks
- append a screenshot section so page state is preserved

## Known Limits

- keyboard pagination probing is best-effort
- some sites expose little or no selectable text
- authenticated pages may not reveal direct image URLs
- pages with hostile clipboard behavior may require slower pacing or manual re-anchoring
