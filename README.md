# Icon110

A minimal SpringBoard tweak based on Atria's icon-layer scaling approach.

- Fixed app/folder icon scale: 110%
- Widgets remain at the system scale
- No settings bundle
- No PreferenceLoader, Alderis, or other third-party tweak libraries
- Injects only into `com.apple.springboard`
- Reports the visible 110% content scale for folder transition calculations,
  preventing SpringBoard from applying a final container scale correction

Build with Theos:

```sh
make package FINALPACKAGE=1
```

The included `build-roothide.yml` workflow uses the official RootHide Theos
fork and builds with `THEOS_PACKAGE_SCHEME=roothide`. Its package is uploaded
as the `Icon110-RootHide` artifact.
