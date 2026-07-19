# 前端设计依据

## 实现基线

设计以 Material 3 Expressive 的色彩、形状、尺寸、运动和 containment 原则为基线。官方资料强调通过高对比容器、更大触控目标、强调排版和自然弹簧运动建立清晰层级，而不是无差别地增加装饰。

截至 Flutter 3.44.6，Material 官方 Flutter 页面仍标明 M3 Expressive 尚未完整提供，Flutter 跟踪议题为 `flutter/flutter#168813`。因此工程没有假设 `ThemeData` 已存在 Expressive 开关。

参考资料：

- [Material 3 Expressive](https://m3.material.io/)
- [Material 3 Get started](https://m3.material.io/get-started)
- [Expressive design research](https://design.google/library/expressive-material-design-google-research)
- [Material 3 for Flutter](https://m3.material.io/develop/flutter)
- [Flutter M3 Expressive tracking issue](https://github.com/flutter/flutter/issues/168813)
- [`m3e_core`](https://pub.dev/packages/m3e_core)

## 信息层级

首页不使用地图，第一视线只保留时间、状态和今日工时。服务器校准状态与工作状态置于 Hero 卡顶部，时间使用 tabular figures 避免秒数跳动造成横向抖动，工时目标使用波形进度提供持续但低干扰的生命感。

近七日工时位于第二层。图表隐藏无必要坐标轴，只保留工作日标签、8 小时背景杆和按压 tooltip。当前日同时改变柱宽与颜色，避免仅依靠色相区分。

生物识别、设备信任、连续天数和最近操作属于第三层。信息被拆分到不同 tonal container，不与主操作竞争视觉注意力。

## 色彩

主题通过 `ColorScheme.fromSeed` 和 `DynamicSchemeVariant.expressive` 生成完整 light/dark 色彩角色。主 Hero 使用 `primary/onPrimary`，图表使用 `secondaryContainer`，连续记录使用 `tertiaryContainer`，下班动作使用语义化 `errorContainer`。

代码始终配对 `container/onContainer` 角色。状态同时使用图标和文字，错误状态不只使用红色。

## 形状

卡片基础半径为 28dp。Hero 和提示条使用一个收紧角形成方向感，主打卡按钮在上班时从圆形变为带收紧角的停止形态。`m3e_core` 的 sunny、cookie 和 puffy 形状只用于 Hero 装饰、头像和连续记录等少量时刻，避免每个组件都使用异形造成噪声。

## 运动

Floating Toolbar 使用 `M3EMotion.expressiveSpatialFast`。状态图标使用 scale transition，加载态每 650ms 在扩展形状间切换并以 4666ms 周期旋转。波形进度使用独立 repaint painter，避免整棵 Widget 树持续重建。

所有自定义持续动画读取 `MediaQuery.disableAnimations`。关闭动画时停止旋转、形状定时器和波形相位，普通状态切换使用零时长。

## 自适应与无障碍

小于 840dp 时采用单列；更宽窗口将 Hero 与数据列并排。内容最大宽度 1120dp，避免平板上无限拉伸。安全信息在 500dp 以下改为纵向排列。

所有核心操作具有 tooltip 或 Semantics 标签。Hero 提供合并后的时间、状态和工时语义；图表提供逐日文本摘要；加载态提供明确语义。触控目标不低于 48dp，Floating Toolbar 总高度为 80dp。

## 依赖策略

`m3e_core` 固定为 `0.1.2` 而不是 caret 范围，因为该包仍处于早期版本且曾发生 breaking changes。项目只依赖稳定发布包中实际导出的 Floating Toolbar、按钮、运动和形状。GitHub 主分支中尚未发布的 ColorSpec2026、loading indicator 和 wavy progress 没有被直接引用。
