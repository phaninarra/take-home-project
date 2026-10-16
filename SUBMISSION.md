# Sending it back

## 1. Make it a git repo

You received this as a zip with no git history. Commit it as it arrived, before
you change anything:

```
git init
git add .
git commit -m "Assessment as received"
```

Then work in commits as you normally would. We read the history.

## 2. Zip it back up

When you are done, zip the whole project directory — including the `.git`
folder, so we can see your commit history:

```
zip -r submission.zip .
```

## 3. Upload it and share a link

**Please do not attach the zip to an email** — our email system blocks zip
attachments, so we would never receive it.

Instead:

1. Upload `submission.zip` to a file-sharing service you already use, such as
   Google Drive, Dropbox, OneDrive, or Box.
2. Set the sharing so that **anyone with the link can download** the file — no
   sign-in or access request needed on our end.
3. Reply to the email that sent you this with the link.

That reply is your submission — no extra step needed. Please keep the link
active until we have confirmed we've downloaded it.

## If something is broken

If `./preflight` fails, or a service will not start, or anything about the setup
wastes your time — **reply to the email that sent you this, straight away.**

Getting this running is our problem, not yours. It does not count against your
one to two hours, and we will stop the clock while we sort it out. Please do
not spend your afternoon debugging our Docker setup.

## Your API key

If you asked for a Claude Code API key, it's yours alone and we switch it off
once you submit. Spend on it is not something we look at.

## Deadline

One week from when you received this. If you want longer, ask — the answer is
yes, and it does not count against you.
