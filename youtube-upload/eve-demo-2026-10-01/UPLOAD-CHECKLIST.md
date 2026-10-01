# EVE demo upload checklist

## Before opening YouTube Studio

- [ ] Provide the approved final video file.
- [ ] Verify the final duration, spoken wording, visible claims, end frame, and any music or third-party assets.
- [ ] Create and validate `captions-en.srt` against the final audio.
- [ ] Create chapters from the actual timeline only.
- [ ] Export a real-frame thumbnail as a 16:9 JPG or PNG; inspect it at master size, 1280 × 720, and about 320 pixels wide.
- [ ] Confirm the thumbnail is under 50 MB for desktop upload and contains no invented UI, outcome, or expression.
- [ ] Generate fresh SHA-256 checksums for the final video, captions, and thumbnail.

## Upload fields

- [ ] Paste the recommended title from `youtube-metadata.md`.
- [ ] Paste the description and then add only verified chapters.
- [ ] Add the three listed hashtags and focused Studio tags.
- [ ] Set original language to English after checking final audio.
- [ ] Set category to Science & Technology.
- [ ] Set audience to not made for kids.
- [ ] Use Standard YouTube License unless channel policy differs.
- [ ] Confirm there is no paid promotion.
- [ ] Answer the altered-content question from the final edit. Select Yes only if it includes realistic, meaningfully AI-generated or altered footage; title, caption, thumbnail, or minor production assistance alone do not require it.
- [ ] Keep comments enabled, likes visible, and embedding allowed unless a channel-level preference differs.
- [ ] Add an end screen only if the final video is at least 25 seconds and there is a clean end-card window.
- [ ] Review automatic chapters setting. Manual chapters override it.

## Final QA before publish

- [ ] Preview on desktop and mobile.
- [ ] Check title, description, tags, thumbnail spelling, captions, chapter timestamps, and visibility.
- [ ] Confirm every public claim matches the final video and `README.md`.
- [ ] Confirm no private repository URL, credential, test key, or user calendar/location data is visible.
- [ ] Upload as Private first for review. Any later visibility change is a separate manual action.

## After a separate manual publish decision

- [ ] Watch the published playback once with captions enabled.
- [ ] Confirm thumbnail, chapters, comments, description links, and end screen render correctly.
- [ ] Save the final YouTube URL and replace the `_VIDEO_URL_` placeholder in `../../README.md` only if requested.
