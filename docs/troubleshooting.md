# Troubleshooting

<p class="ebb-lead">
When something does not work as expected — from silent buttons to odd Autopilot decisions.
For feature explanations, see the <a href="faq.md">FAQ</a>.
</p>

## Something visibly failed

Settings -> Windows & Tools -> **Error log**. If an error was caught, it's there with a stack trace -- paste it into a [bug report](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues/new/choose). An empty error log next to something clearly broken is useful information too: say so in the report, it may point at a handler that isn't error-wrapped yet.

## A button does nothing

Enable **Log every button click** (Settings -> Automation), reproduce, then check Windows & Tools -> **Click Trace log**. Whether the click registered at all changes where the bug lives.

## Automation made a weird decision

The **Logbook** records every decision with its reasoning and the next-best alternative -- find the moment, open the decision, and the score breakdown usually answers it. If the numbers themselves look wrong, the AI report (build editor footer) exports the complete configuration for a second pair of eyes.

## The Tuning Advisor shows no data

DPS-based features need Details! installed and per-character tracking consent (Settings). Since 3.23 tracking is opt-in -- if you played before that, your setting was reset to off and the login panel asked once.

## For maintainers: from error text to cause

`sh scripts/triage-error.sh -` with a pasted error dump prints every mentioned `file:line` with surrounding source and the last commits touching that exact range.
