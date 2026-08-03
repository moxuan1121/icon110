# Icon110

A minimal SpringBoard tweak based on Atria's icon-layer scaling approach.

- Fixed app/folder icon scale: 110%
- Widgets remain at the system scale
- Application and folder labels are hidden
- No settings bundle
- No PreferenceLoader, Alderis, or other third-party tweak libraries
- Injects only into `com.apple.springboard`
- Reports 110% for every non-widget icon at both ends of folder transitions,
  preventing folder contents from returning through a temporary 100% endpoint
- Composes 110% with SpringBoard's live app transition scale so returning from
  an application to the Home Screen does not flatten or hitch at the endpoint

Build with Theos:

```sh
make package FINALPACKAGE=1
```

The included `build-roothide.yml` workflow uses the official RootHide Theos
fork and builds with `THEOS_PACKAGE_SCHEME=roothide`. Its package is uploaded
as the `Icon110-RootHide` artifact.
