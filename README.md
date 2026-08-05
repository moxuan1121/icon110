# Icon110

A minimal SpringBoard tweak based on Atria's icon-layer scaling approach.

- Fixed app/folder icon scale: 110%
- Long-press layout refreshes remain at 110% without a 100% handoff frame
- Widgets remain at the system scale
- Application and folder labels are hidden
- Home Screen and folder page dots are hidden, including their hit area
- No settings bundle
- No PreferenceLoader, Alderis, or other third-party tweak libraries
- Injects only into `com.apple.springboard`
- Scales only the inner `contentContainerView` layer. SpringBoard keeps full
  ownership of the outer app and folder transition transforms, preventing a
  110% to 100% handoff at either animation endpoint
- Uses the real folder push/pop completion callbacks to report 110% for folder
  contents only during folder transitions. App-to-folder returns retain one
  scale layer, avoiding the compounded 121% animation

Build with Theos:

```sh
make package FINALPACKAGE=1
```

The included `build-roothide.yml` workflow uses the official RootHide Theos
fork and builds with `THEOS_PACKAGE_SCHEME=roothide`. Its package is uploaded
as the `Icon110-RootHide` artifact.
