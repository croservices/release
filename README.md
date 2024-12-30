How to do a release
===================

- Change the version numbers in `versions.json` to the versions you want to
  release. Keep the versions of modules you don't want to release unchanged.
- Run `release.raku --prepare`. This will do a release in all modules that have
  a changed version number.
- Complete the pre-generated release notes in `cro-website/docs/releases.md`
  commit / push / release those.

