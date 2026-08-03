# Icon110

A minimal SpringBoard tweak based on Atria's icon-layer scaling approach.

- Fixed app/folder icon scale: 110%
- Widgets remain at the system scale
- Application and folder labels are hidden
- No settings bundle
- No PreferenceLoader, Alderis, or other third-party tweak libraries
- Injects only into `com.apple.springboard`
- Scales only the inner `contentContainerView` layer. SpringBoard keeps full
  ownership of the outer app and folder transition transforms, preventing a
  110% to 100% handoff at either animation endpoint
- Reports 110% only for collapsed folder icons and icons whose location is
  inside a folder; ordinary Home Screen app transitions retain the stock scale

Build with Theos:

```sh
make package FINALPACKAGE=1
```

The included `build-roothide.yml` workflow uses the official RootHide Theos
fork and builds with `THEOS_PACKAGE_SCHEME=roothide`. Its package is uploaded
as the `Icon110-RootHide` artifact.
