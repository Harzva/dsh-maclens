# Changelog

All notable changes to dsh-maclens are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-08-19

### Fixed

- Plugin now `chmod`s the bundled `bin/maclens` at runtime: npm tarballs drop the executable bit, which broke `maclens_*` tools installed from the registry (`EACCES` on spawn).
- Slimmed the npm package to sources + compiled binary (excluded `swift/.build`).

## [0.1.0] - 2026-08-19

### Added

- Initial release: `maclens_ocr`, `maclens_classify`, `maclens_faces`, `maclens_document` tools backed by a Swift CLI over Apple's on-device Vision framework.
- `maclens_describe` combined read (OCR + classification + faces + layout).
- `--max-lines` OCR cap and explicit missing-file errors.
- `--slice` / `--slice-height` tall-image slicing for long screenshots.
- Swift Testing suite and GitHub Actions CI.

[0.1.1]: https://github.com/Harzva/dsh-maclens/releases/tag/v0.1.1
[0.1.0]: https://github.com/Harzva/dsh-maclens/releases/tag/v0.1.0
