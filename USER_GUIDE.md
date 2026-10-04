# Cashy User Guide

Cashy is a private, fully offline expense and income tracker. Speak or type a transaction in plain English or Chinese, and Cashy figures out the amount, currency, category, and date for you — all processed on your own device, nothing sent to the cloud.

## Contents

- [Getting Started](#getting-started)
- [Adding a Transaction](#adding-a-transaction)
- [Reading the Dashboard](#reading-the-dashboard)
- [Categories](#categories)
- [Settings](#settings)
- [Backup & Restore](#backup--restore)
- [Getting the Best Voice Recognition](#getting-the-best-voice-recognition)
- [Troubleshooting](#troubleshooting)
- [Your Privacy](#your-privacy)

## Getting Started

On first launch, Cashy defaults to **MYR** (Malaysian Ringgit) as your base currency and **English** as the default language. Head to **Settings** (gear icon, top right) to change either before you start logging transactions — see [Settings](#settings) below.

## Adding a Transaction

Tap the **Speak** button (bottom right of the dashboard) to open the entry sheet. You have two ways to log a transaction:

### By voice

1. Choose **EN** or **中文** at the top of the sheet.
2. **Press and hold** the microphone button, say your transaction in one sentence, then **release**.
3. Cashy transcribes it, parses out an amount, category, and note, and shows you the result to review.

Examples that work well:

| Language | Example |
|---|---|
| English | "I spent 15 ringgit on lunch at McDonalds" |
| English | "received salary 5000 dollars yesterday" |
| English | "paid electricity bill 150" |
| Chinese | "中午在麦当劳花了15块钱" |
| Chinese | "昨天发工资5000" |
| Chinese | "交了150块电费" |

### By text

Below the mic, there's a text field ("Type your transaction…") — type the same kind of sentence and press send. This uses the same parsing as voice, just without speaking, and is a good fallback if voice recognition isn't cooperating.

### Reviewing before saving

Whichever way you entered it, Cashy always shows you the parsed result — amount, currency, expense/income, category, note, and date — before saving. Correct anything that's wrong, then tap **Save**. Nothing is saved to your history without this confirmation step.

## Reading the Dashboard

- **Balance card** — this month's balance, income, and expense totals in your base currency, with an income/expense ratio bar.
- **Budget indicator** — appears on the balance card once you set a Monthly Budget Limit in Settings; shows a progress bar and how much you have left (or a "🔥 Over budget!" warning).
- **Category chart** — a breakdown of this month's expenses by category.
- **Trend chart** — income vs. expense over the last 6 months.
- **Recent transactions** — your latest entries; tap **See All** for the full history.
- **Month navigation** — use the arrows, or swipe left/right anywhere on the dashboard, to move between months.

## Categories

Cashy ships with a built-in set of categories, each pre-loaded with English and Chinese keywords it uses to auto-detect the category from what you say:

**Expense:** Food, Transport, Bills & Utilities, Shopping, Entertainment, Health, Education, Others
**Income:** Salary, Freelance, Gift, Others

To rename a category or add your own keywords (so Cashy recognizes more phrases as that category), go to **Settings → Categories** and tap one.

## Settings

- **Base Currency** — the currency all dashboard totals are shown in.
- **Default Language** — the language the voice sheet opens in by default (you can still switch per-entry).
- **Monthly Budget Limit** — set an amount to enable the budget indicator on the dashboard. Leave at 0 to disable it.
- **Exchange Rates** — the rates Cashy uses to convert other currencies into your base currency. These start as approximate defaults. If rate updates are switched on, Cashy downloads current rates about once a month when you're online (or when you tap **Update now**). You can also type your own rate for any currency — it's marked "set by you" and is kept when new rates download; choose **Use automatic** to go back. Changing a rate only affects future transactions, not past ones already saved.
- **Backup & Restore** — see below.

## Backup & Restore

Your data lives only on this device, so it's worth backing up.

- **Export Backup** — saves all your transactions and categories to a file and opens your device's share sheet, so you can save it to cloud storage, email it to yourself, or send it anywhere you like.
- **Restore from Backup** — shows a list of backup files found on this device and lets you pick one. Restoring **merges** the backup into your current data — it never deletes anything already here. You can optionally also restore the currency/language/budget/exchange-rate settings from that backup (off by default).

**Moving to a new device:** on iOS and desktop (Windows/macOS/Linux), you can copy the exported backup file into Cashy's own documents folder using the Files app (iOS) or a normal file browser (desktop), then use Restore. On Android, this currently only works for restoring a backup you exported from that same device — there's no cross-app file picker yet.

## Getting the Best Voice Recognition

- **Hold the mic button for at least a second or two** and say a full sentence. A very short hold cuts your phrase off before it's finished, and Cashy will now tell you to hold longer instead of guessing.
- **Speak at a normal volume, not shouting close to the mic.** If your microphone's input level is too high, your voice can clip/distort, which makes recognition come out garbled even though it "heard" something. On Windows, check Settings → Sound → Input → your microphone's volume if this happens often.
- **Say the amount and a category word in the same sentence** — "spent 15 on lunch" works much better than just "15", since the category keyword also helps Cashy get the amount and intent right.
- If voice keeps mis-hearing you, use the **text input** fallback — it uses the exact same parsing, just skips the microphone.

## Troubleshooting

**"Hold the mic a little longer and speak clearly, then release."**
Your recording was too short to contain a full phrase. Try again holding the button down for the whole sentence.

**"No speech detected. Try again."**
Cashy didn't detect any usable speech — check that your microphone is enabled and not muted, and try speaking closer to it.

**"Could not understand the expense. Please type it in."**
Cashy transcribed something, but couldn't find an amount or a recognizable pattern in it. Use the text field instead, or rephrase with a clearer number and category word.

**The wrong currency was detected.**
Say the currency explicitly ("15 dollars", "15令吉") rather than a bare number — Cashy defaults to your base currency when no currency word is heard.

**The category is wrong or missing.**
Add the word you used to that category's keyword list in **Settings → Categories**, so Cashy recognizes it next time.

**"No Backups Found" when restoring.**
You haven't exported a backup on this device yet, or (if restoring from another device) you haven't copied the backup file into Cashy's documents folder yet — see [Backup & Restore](#backup--restore).

## Your Privacy

Voice recognition and transaction parsing both run entirely on your device — nothing is uploaded to any server. Your transaction history lives in a local database on your device and is only ever shared if you explicitly use the Export Backup feature.
