# Station Cat Music project instructions

## Version updates and release notes

Whenever a version or build number is updated for a package delivered to the user, update the in-app release notes in the same change. This includes a build-number override passed to Xcode: do not ship a newer number with the previous release's notes.

- Describe the actual user-visible changes and fixes for that package. Include the release date, retain earlier update records, and do not claim unimplemented or unverified features.
- Keep Simplified Chinese, Traditional Chinese, English and Japanese notes complete and consistent. Edit `scripts/seed_resources.py` and regenerate `Resources/Localizations.json`.
- Keep the version/build in `scripts/generate_project.py` and the generated Xcode project consistent. Regenerate the project after changing those values.
- Before installing or delivering the package, check its actual `Info.plist` and bundled localization resources, and confirm that the version and current update entries match. Verify the existing version/update-notes UI flow when its structure or version expectation changes.
- Preserve accounts, personal-library data and cached songs during an in-place device update. Record successful installation separately from successful launch or on-device inspection.

This rule reflects the user's instruction of 2026-09-25: every future version-number update must also include complete update notes.
