# Icon110 + IconShadow integration

A single Dopamine RootHide SpringBoard tweak combining the stable Icon110 main
branch with IconShadow 1.26 (the same tweak implementation as its 1.19 baseline).

- Fixed app/folder icon scale: 110%
- Context-menu dismissal keeps its temporary icon snapshot at 110%
- Transparent Dock background while preserving Dock icons
- Transparent folder background while preserving folder icon animations
- Transparent Home Screen folder thumbnail background while preserving its miniature icons
- Transparency is limited to dedicated SpringBoard Dock and folder APIs
- Widgets remain at the system scale
- Application and folder labels are hidden, including recently-updated dots
- Home Screen and folder page dots are hidden, including their hit area
- Native PNG shadows below supported app and folder icons
- Shadow geometry compensates for Icon110's 110% `sublayerTransform`
- App-return shadows follow SpringBoard's native icon alpha animation
- IconShadow's stable folder visibility and transition-generation behavior
- No settings bundle
- No PreferenceLoader, Alderis, or other third-party tweak libraries
- Injects only into `com.apple.springboard`
- Scales only the inner `contentContainerView` layer. SpringBoard keeps full
  ownership of the outer app and folder transition transforms, preventing a
  110% to 100% handoff at either animation endpoint
- Uses the real folder push/pop completion callbacks to report 110% for folder
  contents only during folder transitions. App-to-folder returns retain one
  scale layer, avoiding the compounded 121% animation
- `SBIconView.layoutSubviews` is shared: Icon110 applies its scale first, then
  IconShadow reads that final transform and updates its inverse compensation
- Folder push/pop methods are shared and wrap each system completion once,
  preserving both plugins' state without dependency on dylib hook order
- The package replaces `com.wkk.iconshadow`; do not install the standalone
  IconShadow package alongside this integrated build

Build the Dopamine RootHide-only package with Theos:

```sh
gmake clean
gmake package FINALPACKAGE=1
```

The RootHide package scheme and iOS 15 minimum deployment target are enforced
by the Makefile. The included `build-roothide.yml` workflow builds the isolated
`icon` integration branch with the official RootHide Theos fork, validates the
final DEB contents and metadata, and uploads it as the `Icon110-RootHide`
artifact.

## Drag diagnostic build

Version `1.4.1~diagnostic1` records the iOS 15 SpringBoard drag callback order
without changing shadow visibility or layout. After one drag and drop, collect:

```text
/var/mobile/Library/Preferences/com.moxuan.icon110.drag.log
```

The log is reset whenever SpringBoard starts. This diagnostic is temporary and
will be removed once the actual moving-view path is confirmed.
