# Security policy

Stadig Lift and Stadig Macro keep a person's training and food log on their own devices and in their own iCloud. There is no Stadig server and no account, so most of what could go wrong is in the apps themselves, in the files they share with each other, or in the website's support form.

## Supported versions

| Version | Supported |
| --- | --- |
| The latest version of each app on the App Store | Yes |
| `main` | Yes |
| Older versions | No: update to the latest |

A fix ships in the next version of the app. Older versions aren't patched.

## Reporting a vulnerability

Please don't open a public issue or pull request for it. Report it privately, either way:

- **On GitHub:** this repository's Security tab, then "Report a vulnerability" ([open a report](https://github.com/swsvindland/Stadig/security/advisories/new)).
- **Without a GitHub account:** the form at [stadig.dev/support](https://stadig.dev/support), which is read privately. Leave an email address if you'd like a reply.

It helps to say:

- which app or part (Stadig Lift, Stadig Macro, a Watch app, the website), and its version;
- the device and OS version;
- what you found and how to reproduce it;
- what someone could do with it.

## What to expect

Stadig is one person's project, so there's no promised response time, but every report is read. You'll hear back when it has been looked at: either what the fix is and roughly when it ships, or why it isn't being treated as a vulnerability. Please allow time for a fixed version to reach the App Store before publishing details. If you'd like credit in the release notes, say so.

## What's covered

- The apps and their Watch apps, the Swift packages in `Packages/`, and the files the apps share through their App Group and iCloud.
- The website in `Site/`, including the function behind its support form.
- The scripts in `Scripts/` that build the apps and the food catalogs.

Not covered here: Apple's frameworks and iCloud, GitHub and the site's host (report those to them), and food or supplement data that's simply wrong, which is a bug for the [support form](https://stadig.dev/support).
