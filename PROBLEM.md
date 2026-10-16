# The problem

## Where we are

Paying someone out involves four of our systems. They are owned by four
different teams, they were built years apart, and none of them agree on
anything — not the format, not the identifiers, not the way you authenticate.

Every client that wants to know about a payout currently talks to all four and
stitches the answer together itself. Four clients, four copies of that logic,
four sets of bugs.

## What we want

One API in front of all four.

It will be called by our own web app, by a partner integration, and by an
internal ops tool. It will be reachable from the internet, and it serves several
funding programs whose data must not mix.

Design that API. Then build enough of it to prove it works.

## Design it

Write the design down in `DESIGN.md`. This is the main thing we read.

Cover the whole API, not just the parts you build — the resources, what the
requests and responses look like, how errors are reported, and how callers
authenticate. Explain the decisions you made and what you traded away.

Two things you will have to take a position on:

- **The four systems disagree.** Roughly sixty payouts have settled according to
  the executor and been sent back by the bank. What does your API say the status
  of one of those is?
- **Nothing shares an identifier.** An instruction, an execution and a bank
  return all refer to the same payout by different names.

## Build it

One thing, working, against the real services:

**Look up one payout.** A client has one identifier and wants the whole
picture: who is being paid, what was instructed, whether it went out, and
whether the bank sent it back. This touches all four services.

Include tests. What kind, and how many, is your call.

## Rules

- **You cannot change the four services.** Treat them as belonging to other
  teams. No edits, no forks, no reimplementations. If you would ask a team to
  change something, write that down instead — we want to read it.
- Everything runs locally. Nothing needs to be deployed.
- **Write your code in TypeScript, Python or .NET.** Pick whichever you are
  strongest in — we have no preference between the three. We constrain it
  because these are what we maintain, and because judging whether code is good
  is far easier in a language the reviewer knows well.
- Within that, the framework is yours. So is the shape of the thing — one
  service, several, or something thinner.
- You may still put off-the-shelf infrastructure in front of or alongside your
  code — a proxy, a gateway, a cache. That choice interests us, so say why in
  the design doc.

## Optional

Only if you have time, and only if the lookup endpoint is done properly. Cover
these in `DESIGN.md` regardless of whether you build them:

- **Create a payout.** A client submits one. If they retry because they did not
  see our response, it must not go out twice. Design this either way; build it
  only if lookup is solid and you have time left.
- Amend or cancel a payout. Think about what those even mean here before you
  build anything.
- A report of payouts where the systems disagree.

We would rather read a clear note about why you skipped these than see them half
finished.

## Time

**Spend one to two hours.** Not more.

If you hit the limit, stop and write down what you would do next. Knowing where
to stop is part of the job, and we read that section carefully.

You have a week to return it. If you need longer, just ask — the answer is yes.

## Using AI

Use it. If you would like a Claude Code API key so cost is not a factor, just
ask and we will send one.

We want to see how you think, so leave a trail. Commit as you go, and tell us in
`AI-USAGE.md` what you used it for and how you checked its output. If you want
to include a session transcript, feel free — it is entirely optional and we do
not read anything you do not send us.

## What we look at

- The API you designed, and whether the reasoning holds up.
- Whether the code is something we would want to maintain.
- How you handled the parts of this that do not have a clean answer.
- Your tests.
- Whether the whole thing is production-ready, and what you say is missing.

Deliver three documents: `DESIGN.md`, `README.md` (how to run it), and
`AI-USAGE.md`.

If it goes well, we will spend an hour talking through your design choices, what
else you considered, and what you would do differently.
