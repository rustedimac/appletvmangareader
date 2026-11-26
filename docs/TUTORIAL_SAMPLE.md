# Controls tutorial sample

The controls tutorial (`ReaderTutorial` in MangaCore, `ReaderTutorialView`
in the app) reads three bundled pages in `App/Resources/Tutorial/`.

| File | Source |
| --- | --- |
| `tutorial-pepper-carrot-e01p01.jpg` | `en_Pepper-and-Carrot_by-David-Revoy_E01P01.jpg` |
| `tutorial-pepper-carrot-e01p02.jpg` | `en_Pepper-and-Carrot_by-David-Revoy_E01P02.jpg` |
| `tutorial-pepper-carrot-e01p03.jpg` | `en_Pepper-and-Carrot_by-David-Revoy_E01P03.jpg` |

- Work: *Pepper&Carrot*, Episode 1: The Potion of Flight (published 2014-05-10).
- Author: David Revoy (art and scenario). English is the original version;
  proofreading by Amireeti and Alex Gryson (from the episode's `info.json`).
- Source: https://www.peppercarrot.com/0_sources/ep01_Potion-of-Flight/low-res/
  (downloaded 2026-11-26). Files are byte-identical to the source, only
  renamed; 1200 × 1660 px, about 1.2 MB together.
- License: Creative Commons Attribution 4.0,
  https://creativecommons.org/licenses/by/4.0/ . Commercial use allowed with
  credit. The site also asks that the work not be used to train or derive AI
  models; the app only displays it.
- Credit shown in the app (`ReaderTutorial.sampleCredit`): on the
  tutorial's last step and under Settings > Remote and Controller >
  Learn the Controls.

Human-made work with a clear license, as the project's sample rule
requires. Don't swap in AI-generated or commercial pages; code-drawn
pages belong only in tests.
