# Icon110

A minimal SpringBoard tweak based on Atria's icon-layer scaling approach.

- Fixed app/folder icon scale: 110%
- Context-menu dismissal keeps its temporary icon snapshot at 110%
- Transparent Dock background while preserving Dock icons
- Transparent folder background while preserving folder icon animations
- Transparent Home Screen folder thumbnail background while preserving its miniature icons
- Transparency is limited to dedicated SpringBoard Dock and folder APIs
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

Build the Dopamine RootHide-only package with Theos:

```sh
gmake clean
gmake package FINALPACKAGE=1
```

The RootHide package scheme and iOS 15 minimum deployment target are enforced
by the Makefile. The included `build-roothide.yml` workflow uses the official
RootHide Theos fork, validates the final DEB contents and metadata, and uploads
it as the `Icon110-RootHide` artifact.
