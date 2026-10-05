# 应用图标与显示名称

- 显示名称：`哔哩哔哩`（CFBundleDisplayName、CFBundleName 和 ChunUI appName）。
- 用户指定参考：[白底黑色小电视，原图右半部分](https://p0.itc.cn/q_70/images03/20201116/6546281cd12a4bd480609260be28597a.png)。
- 处理方式：内置 image_gen，使用原图作为编辑输入，仅重绘右侧图案并清理低分辨率边缘。生成后仅作 iOS 资源所需的 1024 × 1024 尺寸标准化；PNG 为不透明 RGB。
- 系统、浅色与深色图标选项均使用用户指定的白底黑色版本。系统负责图标圆角裁切，文件不预画圆角。
- 资源：`bili/Assets.xcassets/AppIcon.appiconset/piliplus-icon.png`，另外两个 appiconset 采用相同文件。
- 项目内部名、Bundle ID、Keychain 与已有存储标识保留原值。
- 图案及品牌归各自权利人所有；本仓库 GPL 许可针对代码，不意味着获得相关品牌商标授权。

## 生图提示词

```text
Use case: precise-object-edit.
Asset type: final iOS app icon, a single 1024 x 1024 pixel square, opaque PNG.
Input image 1 is the edit target: a two-panel black-and-white Bilibili television logo reference. Extract and faithfully redraw ONLY the RIGHT-HAND logo: black outlined little television face on a pure white background. This is restoration and high-resolution cleanup, not a redesign.
Preserve exactly the right-hand logo's silhouette, rounded trapezoidal TV body, two short thick outward-slanting antennas, double outline (thick outer black stroke and thinner inner black screen outline), slanted rounded black eyes and small rounded w-shaped smiling mouth. Match the reference proportions and stroke hierarchy, with exceptionally clean smooth high-resolution edges and no JPEG artifacts.
Center the single black television mark optically on a uniform pure #FFFFFF white full-bleed square. The mark should occupy roughly 62 percent of the canvas width and about 60 percent of its height, with balanced whitespace. Keep everything within safe app-icon margins. Flat near-black ink only, no gradients, no shadow, no perspective, no gloss, no extra elements.
Do not include the left-hand panel, the center dividing line, a black background, any border around the canvas, pre-rounded app icon corners, transparency, words, letters, or a device mockup. The app name is not part of the artwork.
```
