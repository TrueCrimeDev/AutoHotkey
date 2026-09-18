# Contribute to the documentation

The site source lives in `website/` in the Console repository. It is built with VitePress and published to GitHub Pages at the `/AutoHotkey/` project path.

## Work locally

```powershell
cd website
npm ci
npm run dev
```

Before publishing:

```powershell
npm run build
npm run check
npm run preview
```

The build checks Markdown links. The additional site checker examines generated pages, local links and assets, expected documentation sections, and personal-path patterns. It does not replace browser interaction checks or executable example tests.

## Add or improve a page

1. Put the Markdown page in the appropriate topic directory.
2. Add its sidebar entry in `.vitepress/config.mts`.
3. State build requirements and expected results next to runnable examples.
4. Include source links and preserve failure/partial evidence.
5. Use neutral paths in examples and manually inspect image contents.

Homepage interactions live in `.vitepress/theme/`; downloads and captured PNGs live in `public/`. Images used here were reviewed individually; a text scanner cannot inspect pixels.

## Publication

The `Documentation Pages` workflow builds and validates on documentation changes. On the `alpha` branch it publishes the generated site through GitHub Actions Pages. Pull requests only validate. Do not publish the whole repository as a site: only `.vitepress/dist` is the deployable artifact.

Framework reference: [VitePress deployment guide](https://vuejs.github.io/vitepress/v1/guide/deploy). Installation source: [VitePress 1.6 documentation](https://vuejs.github.io/vitepress/v1/guide/getting-started).
